import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/src/dart/analysis/byte_store.dart';
import 'package:analyzer/src/dart/analysis/driver.dart';
import 'package:analyzer/src/dart/analysis/file_state.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/sdk.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/summary/api_signature.dart';
import 'package:analyzer_plugin/utilities/completion/completion_core.dart';
import 'package:angular_analyzer_plugin/errors.dart';
import 'package:angular_analyzer_plugin/notification_manager.dart';
import 'package:angular_analyzer_plugin/src/converter.dart';
import 'package:angular_analyzer_plugin/src/directive_extraction.dart';
import 'package:angular_analyzer_plugin/src/directive_linking.dart';
import 'package:angular_analyzer_plugin/src/file_tracker.dart';
import 'package:angular_analyzer_plugin/src/from_file_prefixed_error.dart';
import 'package:angular_analyzer_plugin/src/model.dart';
import 'package:angular_analyzer_plugin/src/options.dart';
import 'package:angular_analyzer_plugin/src/pipe_extraction.dart';
import 'package:angular_analyzer_plugin/src/resolver.dart';
import 'package:angular_analyzer_plugin/src/standard_components.dart';
import 'package:angular_analyzer_plugin/src/summary/format.dart';
import 'package:angular_analyzer_plugin/src/summary/idl.dart';
import 'package:angular_analyzer_plugin/src/view_extraction.dart';
import 'package:crypto/crypto.dart';

class AngularDriver
    implements
        AnalysisDriverGeneric,
        FileDirectiveProvider,
        FilePipeProvider,
        DirectiveLinkerEnablement,
        FileHasher {
  final ResourceProvider _resourceProvider;
  // TODO(mfairhurst) remove NotificationManager & old plugin loader.
  final NotificationManager notificationManager;
  final AnalysisDriverScheduler _scheduler;
  final AnalysisDriver dartDriver;
  final FileContentOverlay contentOverlay;
  final AngularOptions options;
  StandardHtml standardHtml;
  StandardAngular standardAngular;
  SourceFactory _sourceFactory;
  final _addedFiles = new LinkedHashSet<String>();
  final _dartFiles = new LinkedHashSet<String>();
  final _changedFiles = new LinkedHashSet<String>();
  final _requestedDartFiles = <String, List<Completer<DirectivesResult>>>{};
  final _requestedHtmlFiles = <String, List<Completer<DirectivesResult>>>{};
  final _filesToAnalyze = new HashSet<String>();
  final _htmlFilesToAnalyze = new HashSet<String>();
  final ByteStore byteStore;
  FileTracker _fileTracker;
  final lastSignatures = <String, String>{};
  bool _hasAngularImported = false;
  bool _hasAngular2Imported = false; // TODO only support package:angular
  final completionContributors = <CompletionContributor>[];

  final _dartResultsController = new StreamController<DirectivesResult>();

  // ignore: close_sinks
  final _htmlResultsController = new StreamController<DirectivesResult>();

  AngularDriver(
      this._resourceProvider,
      this.notificationManager,
      this.dartDriver,
      this._scheduler,
      this.byteStore,
      SourceFactory sourceFactory,
      this.contentOverlay,
      this.options) {
    _sourceFactory = sourceFactory.clone();
    _scheduler.add(this);
    _fileTracker = new FileTracker(this, options);
    // TODO only support package:angular once we all move to that
    _hasAngularImported =
        _sourceFactory.resolveUri(null, "package:angular/angular.dart") != null;
    _hasAngular2Imported =
        _sourceFactory.resolveUri(null, "package:angular2/angular2.dart") !=
            null;
  }

  // ignore: close_sinks
  Stream<DirectivesResult> get dartResultsStream =>
      _dartResultsController.stream;

  @override
  bool get hasFilesToAnalyze =>
      _filesToAnalyze.isNotEmpty ||
      _htmlFilesToAnalyze.isNotEmpty ||
      _requestedDartFiles.isNotEmpty ||
      _requestedHtmlFiles.isNotEmpty;

  Stream<DirectivesResult> get htmlResultsStream =>
      _htmlResultsController.stream;

  List<String> get priorityFiles => [];

  /// This is implemented in order to satisfy the [AnalysisDriverGeneric]
  /// interface. Ideally, we analyze these files first. For the moment, this lets
  /// the analysis server team add this method to the interface without breaking
  /// any code.
  @override
  set priorityFiles(List<String> priorityPaths) {
    // TODO analyze these files first
  }

  @override
  AnalysisDriverPriority get workPriority {
    if (!_hasAngularImported && !_hasAngular2Imported) {
      return AnalysisDriverPriority.nothing;
    }
    if (standardHtml == null) {
      return AnalysisDriverPriority.interactive;
    }
    if (_requestedDartFiles.isNotEmpty) {
      return AnalysisDriverPriority.interactive;
    }
    if (_requestedHtmlFiles.isNotEmpty) {
      return AnalysisDriverPriority.interactive;
    }
    if (_filesToAnalyze.isNotEmpty) {
      return AnalysisDriverPriority.general;
    }
    if (_htmlFilesToAnalyze.isNotEmpty) {
      return AnalysisDriverPriority.general;
    }
    if (_changedFiles.isNotEmpty) {
      return AnalysisDriverPriority.general;
    }
    return AnalysisDriverPriority.nothing;
  }

  @override
  void addFile(String path) {
    if (_ownsFile(path)) {
      _addedFiles.add(path);
      if (path.endsWith('.dart')) {
        _dartFiles.add(path);
      }
      fileChanged(path);
    }
  }

  AnalysisError deserializeError(Source source, SummarizedAnalysisError error) {
    final errorName = error.errorCode;
    final errorCode = angularWarningCodeByUniqueName(errorName) ??
        errorCodeByUniqueName(errorName);
    if (errorCode == null) {
      return null;
    }
    return new AnalysisError.forValues(source, error.offset, error.length,
        errorCode, error.message, error.correction);
  }

  List<AnalysisError> deserializeErrors(
          Source source, List<SummarizedAnalysisError> errors) =>
      errors
          .map((error) => deserializeError(source, error))
          .where((e) => e != null)
          .toList();

  /// Notify the driver that the client is going to stop using it.
  @override
  void dispose() {
    _dartResultsController.close();
    _htmlResultsController.close();
  }

  void fileChanged(String path) {
    if (_ownsFile(path)) {
      _fileTracker.rehashContents(path);

      if (path.endsWith('.html')) {
        _htmlFilesToAnalyze.add(path);
        for (final path in _fileTracker.getHtmlPathsReferencingHtml(path)) {
          _htmlFilesToAnalyze.add(path);
        }
        for (final path in _fileTracker.getDartPathsAffectedByHtml(path)) {
          _filesToAnalyze.add(path);
        }
      } else {
        _changedFiles.add(path);
      }
    }
    _scheduler.notify(this);
  }

  Future<DirectivesResult> getAngularTopLevels(String path) async {
    final baseKey = _fileTracker.getContentSignature(path).toHex();
    final key = '$baseKey.ngunlinked';
    final bytes = byteStore.get(key);
    if (bytes != null) {
      final summary = new UnlinkedDartSummary.fromBuffer(bytes);
      return new DirectivesResult(
        path,
        await resynthesizeDirectives(summary, path),
        await resynthesizePipes(summary, path),
        deserializeErrors(getSource(path), summary.errors),
      );
    }

    final dartResult = await dartDriver.getResult(path);
    if (dartResult == null) {
      return null;
    }

    final context = dartResult.unit.declaredElement.context;
    final ast = dartResult.unit;
    final source = dartResult.unit.declaredElement.source;
    final extractor =
        new DirectiveExtractor(ast, context.typeProvider, source, context);
    final topLevels = extractor.getAngularTopLevels();

    final directives = new List<AbstractDirective>.from(
        topLevels.where((c) => c is AbstractDirective));

    final viewExtractor = new ViewExtractor(
        ast, directives, context, source, await getStandardAngular())
      ..getViews();

    final tplErrorListener = new RecordingErrorListener();
    final errorReporter = new ErrorReporter(tplErrorListener, source);

    // collect inline ng-content tags
    for (final directive in directives) {
      if (directive is Component && directive?.view != null) {
        final view = directive.view;
        if ((view.templateText ?? "") != "") {
          final template = new Template(view);
          view.template = template;

          final tplParser = new TemplateParser()
            ..parse(view.templateText, source, offset: view.templateOffset);

          final parser =
              new EmbeddedDartParser(source, tplErrorListener, errorReporter);

          template.ast = new HtmlTreeConverter(parser, source, tplErrorListener)
              .convertFromAstList(tplParser.rawAst);
          template.ast.accept(new NgContentRecorder(directive, errorReporter));
        }
      }
    }

    // collect Pipes
    final pipeExtractor =
        new PipeExtractor(ast, source, await getStandardAngular());
    final pipes = pipeExtractor.getPipes();
    final errors = new List<AnalysisError>.from(extractor.errorListener.errors)
      ..addAll(viewExtractor.errorListener.errors)
      ..addAll(pipeExtractor.errorListener.errors);
    final result = new DirectivesResult(path, topLevels, pipes, errors);
    final summary = serializeDartResult(result);
    final newBytes = summary.toBuffer();
    byteStore.put(key, newBytes);
    return result;
  }

  @override
  ApiSignature getContentHash(String path) {
    final key = new ApiSignature();
    final contentBytes = utf8.encode(getFileContent(path));
    key.addBytes(md5.convert(contentBytes).bytes);
    return key;
  }

  Future<OutputElement> getCustomOutputElement(
      CustomEvent event, DartType dynamicType) async {
    OutputElement defaultOutput() => new OutputElement(
        event.name,
        event.nameOffset,
        event.name.length,
        options.source,
        null,
        null,
        dynamicType);

    final typePath =
        event.typePath ?? (event.typeName != null ? 'dart:core' : null);
    if (typePath == null) {
      return defaultOutput();
    }

    final typeSource = _sourceFactory.resolveUri(null, typePath);
    if (typeSource == null) {
      return defaultOutput();
    }

    final typeResult = await dartDriver.getResult(typeSource.fullName);
    if (typeResult == null) {
      return defaultOutput();
    }

    final typeElement =
        typeResult.libraryElement.publicNamespace.get(event.typeName);
    if (typeElement is ClassElement) {
      var type = typeElement.type;
      if (type is ParameterizedType) {
        type = type.instantiate(
            type.typeParameters.map((p) => p.bound ?? dynamicType).toList());
      }
      return new OutputElement(event.name, event.nameOffset, event.name.length,
          options.source, null, null, type);
    }
    if (typeElement is TypeDefiningElement) {
      return new OutputElement(event.name, event.nameOffset, event.name.length,
          options.source, null, null, typeElement.type);
    }

    return defaultOutput();
  }

  String getFileContent(String path) =>
      contentOverlay[path] ??
      ((Source source) => // ignore: avoid_types_on_closure_parameters
          source.exists() ? source.contents.data : "")(getSource(path));

  Future<String> getHtmlKey(String htmlPath) async {
    final key = await _fileTracker.getHtmlSignature(htmlPath);
    return '${key.toHex()}.ngresolved';
  }

  @override
  Future<List<NgContent>> getHtmlNgContent(String path) async {
    final baseKey = _fileTracker.getContentSignature(path).toHex();
    final key = '$baseKey.ngunlinked';
    final bytes = byteStore.get(key);
    final source = getSource(path);
    if (bytes != null) {
      return new DirectiveLinker(this, standardAngular).deserializeNgContents(
          new UnlinkedHtmlSummary.fromBuffer(bytes).ngContents, source);
    }

    final htmlContent = getFileContent(path);
    final tplErrorListener = new RecordingErrorListener();
    final errorReporter = new ErrorReporter(tplErrorListener, source);

    final tplParser = new TemplateParser()..parse(htmlContent, source);

    final parser =
        new EmbeddedDartParser(source, tplErrorListener, errorReporter);

    final ast = new HtmlTreeConverter(parser, source, tplErrorListener)
        .convertFromAstList(tplParser.rawAst);
    final contents = <NgContent>[];
    ast.accept(new NgContentRecorder.forFile(contents, source, errorReporter));

    final summary = new UnlinkedHtmlSummaryBuilder()
      ..ngContents = serializeNgContents(contents);
    final newBytes = summary.toBuffer();
    byteStore.put(key, newBytes);

    return contents;
  }

  @override
  Source getSource(String path) =>
      _resourceProvider.getFile(path).createSource();

  Future<StandardAngular> getStandardAngular() async {
    if (standardAngular == null) {
      final source =
          _sourceFactory.resolveUri(null, "package:angular/angular.dart");

      if (source == null) {
        return standardAngular;
      }

      final securitySource =
          _sourceFactory.resolveUri(null, "package:angular/security.dart");
      final protoSecuritySource = _sourceFactory.resolveUri(
          null, 'package:webutil.html.types.proto/html.pb.dart');

      standardAngular = new StandardAngular.fromAnalysis(
          angularResult: await dartDriver.getResult(source.fullName),
          securityResult: await dartDriver.getResult(securitySource.fullName),
          protoSecurityResult: protoSecuritySource == null
              ? null
              : await dartDriver.getResult(protoSecuritySource.fullName));
    }

    return standardAngular;
  }

  Future<StandardHtml> getStandardHtml() async {
    if (standardHtml == null) {
      final source = _sourceFactory.resolveUri(null, DartSdk.DART_HTML);

      final result = await dartDriver.getResult(source.fullName);
      final securitySchema = (await getStandardAngular()).securitySchema;

      final components = <String, Component>{};
      final standardEvents = <String, OutputElement>{};
      final customEvents = <String, OutputElement>{};
      final attributes = <String, InputElement>{};
      result.unit.accept(new BuildStandardHtmlComponentsVisitor(
          components, standardEvents, attributes, source, securitySchema));

      for (final event in options.customEvents.values) {
        customEvents[event.name] = await getCustomOutputElement(
            event, result.typeProvider.dynamicType);
      }

      standardHtml = new StandardHtml(
          components,
          attributes,
          standardEvents,
          customEvents,
          result.libraryElement.exportNamespace.get('Element') as ClassElement,
          result.libraryElement.exportNamespace.get('HtmlElement')
              as ClassElement);
    }

    return standardHtml;
  }

  Future<List<Template>> getTemplatesForFile(String filePath) async {
    final templates = <Template>[];
    final isDartFile = filePath.endsWith('.dart');
    if (!isDartFile && !filePath.endsWith('.html')) {
      return templates;
    }

    final directiveResults = isDartFile
        ? await requestDartResult(filePath)
        : await requestHtmlResult(filePath);
    final directives = directiveResults.directives;
    if (directives == null) {
      return templates;
    }
    for (var directive in directives) {
      if (directive is Component) {
        final view = directive.view;
        final match = isDartFile
            ? view.source.toString() == filePath
            : view.templateUriSource?.fullName == filePath;
        if (match && view.template != null) {
          templates.add(view.template);
        }
      }
    }
    return templates;
  }

  @override
  Future<CompilationUnitElement> getUnit(String path) async =>
      (await dartDriver.getUnitElement(path)).element;

  @override
  Future<String> getUnitElementSignature(String path) =>
      dartDriver.getUnitElementSignature(path);

  @override
  Future<List<AngularTopLevel>> getUnlinkedAngularTopLevels(path) async =>
      (await getAngularTopLevels(path)).angularTopLevels;

  @override
  Future<List<Pipe>> getUnlinkedPipes(path) async =>
      (await getAngularTopLevels(path)).pipes;

  @override
  Future<Null> performWork() async {
    if (standardAngular == null) {
      await getStandardAngular();
      return;
    }

    if (standardHtml == null) {
      await getStandardHtml();
      return;
    }

    if (_changedFiles.isNotEmpty) {
      _changedFiles.clear();
      _filesToAnalyze.addAll(_dartFiles);
      return;
    }

    if (_requestedDartFiles.isNotEmpty) {
      final path = _requestedDartFiles.keys.first;
      final completers = _requestedDartFiles.remove(path);
      try {
        final result = await _resolveDart(path,
            onlyIfChangedSignature: false, ignoreCache: true);
        completers.forEach((completer) => completer.complete(result));
      } catch (e, st) {
        completers.forEach((completer) => completer.completeError(e, st));
      }

      return;
    }

    if (_requestedHtmlFiles.isNotEmpty) {
      final path = _requestedHtmlFiles.keys.first;
      final completers = _requestedHtmlFiles.remove(path);
      DirectivesResult result;

      try {
        // Try resolving HTML using the existing dart/html relationships which may
        // be already known. However, if we don't see any relationships, try using
        // the .dart equivalent. Better than no result -- the real one WILL come.
        if (_fileTracker.getDartPathsReferencingHtml(path).isEmpty) {
          result =
              await _resolveHtmlFrom(path, path.replaceAll(".html", ".dart"));
        } else {
          result = await _resolveHtml(path, ignoreCache: true);
        }

        // After whichever resolution is complete, push errors.
        completers.forEach((completer) => completer.complete(result));
      } catch (e, st) {
        completers.forEach((completer) => completer.completeError(e, st));
      }

      return;
    }

    if (_filesToAnalyze.isNotEmpty) {
      final path = _filesToAnalyze.first;
      await pushDartErrors(path);
      _filesToAnalyze.remove(path);
      return;
    }

    if (_htmlFilesToAnalyze.isNotEmpty) {
      final path = _htmlFilesToAnalyze.first;
      await pushHtmlErrors(path);
      _htmlFilesToAnalyze.remove(path);
      return;
    }

    return;
  }

  Future pushDartErrors(String path) async {
    final result = await _resolveDart(path);
    if (result == null) {
      return;
    }
    final errors = result.errors;
    final lineInfo = new LineInfo.fromContent(getFileContent(path));
    // TODO(mfairhurst) remove this with old plugin loader
    notificationManager.recordAnalysisErrors(path, lineInfo, errors);
  }

  Future pushDartNavigation(String path) async {}

  Future pushDartOccurrences(String path) async {}

  Future pushHtmlErrors(String htmlPath) async {
    final errors = (await _resolveHtml(htmlPath)).errors;
    final lineInfo = new LineInfo.fromContent(getFileContent(htmlPath));
    // TODO(mfairhurst) remove this with old plugin loader
    notificationManager.recordAnalysisErrors(htmlPath, lineInfo, errors);
  }

  @deprecated
  Future<List<AnalysisError>> requestDartErrors(String path) async {
    final result = await requestDartResult(path);
    return result.errors;
  }

  /// Get a fully linked (warning: slow) [DirectivesResult] for the components
  /// this Dart path, and their templates (if defined in the component directly
  /// rather than linking to a different html file).
  Future<DirectivesResult> requestDartResult(String path) {
    final completer = new Completer<DirectivesResult>();
    _requestedDartFiles
        .putIfAbsent(path, () => <Completer<DirectivesResult>>[])
        .add(completer);
    _scheduler.notify(this);
    return completer.future;
  }

  @deprecated
  Future<List<AnalysisError>> requestHtmlErrors(String path) async {
    final result = await requestDartResult(path);
    return result.errors;
  }

  /// Get a fully linked (warning: slow) [DirectivesResult] for the templates in
  /// this HTML path. Note that you may get an empty HTML file if dart analysis
  /// has not finished finding all `templateUrl`s.
  Future<DirectivesResult> requestHtmlResult(String path) {
    final completer = new Completer<DirectivesResult>();
    _requestedHtmlFiles
        .putIfAbsent(path, () => <Completer<DirectivesResult>>[])
        .add(completer);
    _scheduler.notify(this);
    return completer.future;
  }

  Future<List<AngularTopLevel>> resynthesizeDirectives(
          UnlinkedDartSummary unlinked, String path) async =>
      new DirectiveLinker(this, standardAngular)
          .resynthesizeDirectives(unlinked, path);

  Future<List<Pipe>> resynthesizePipes(
      UnlinkedDartSummary unlinked, String path) async {
    if (unlinked == null) {
      return [];
    }
    final unit = await getUnit(path);
    final pipes = <Pipe>[];

    for (final dirSum in unlinked.pipeSummaries) {
      final classElem = unit.getType(dirSum.decoratedClassName);
      pipes.add(new Pipe(dirSum.pipeName, dirSum.pipeNameOffset, classElem,
          isPure: dirSum.isPure));
    }

    final pipeExtractor = new PipeExtractor(null, unit.source, null);
    pipes.forEach(pipeExtractor.loadTransformInformation);
    return pipes;
  }

  SummarizedClassAnnotationsBuilder serializeAnnotatedClass(
      AngularAnnotatedClass clazz) {
    final className = clazz.classElement.name;
    final inputs = <SummarizedBindableBuilder>[];
    final outputs = <SummarizedBindableBuilder>[];
    final contentChildFields = <SummarizedContentChildFieldBuilder>[];
    final contentChildrenFields = <SummarizedContentChildFieldBuilder>[];
    for (final input in clazz.inputs) {
      final name = input.name;
      final nameOffset = input.nameOffset;
      final propName = input.setter.name.replaceAll('=', '');
      final propNameOffset = input.setterRange.offset;
      inputs.add(new SummarizedBindableBuilder()
        ..name = name
        ..nameOffset = nameOffset
        ..propName = propName
        ..propNameOffset = propNameOffset);
    }
    for (final output in clazz.outputs) {
      final name = output.name;
      final nameOffset = output.nameOffset;
      final propName = output.getter.name.replaceAll('=', '');
      final propNameOffset = output.getterRange.offset;
      outputs.add(new SummarizedBindableBuilder()
        ..name = name
        ..nameOffset = nameOffset
        ..propName = propName
        ..propNameOffset = propNameOffset);
    }
    for (final childField in clazz.contentChildFields) {
      contentChildFields.add(new SummarizedContentChildFieldBuilder()
        ..fieldName = childField.fieldName
        ..nameOffset = childField.nameRange.offset
        ..nameLength = childField.nameRange.length
        ..typeOffset = childField.typeRange.offset
        ..typeLength = childField.typeRange.length);
    }
    for (final childrenField in clazz.contentChildrenFields) {
      contentChildrenFields.add(new SummarizedContentChildFieldBuilder()
        ..fieldName = childrenField.fieldName
        ..nameOffset = childrenField.nameRange.offset
        ..nameLength = childrenField.nameRange.length
        ..typeOffset = childrenField.typeRange.offset
        ..typeLength = childrenField.typeRange.length);
    }
    return new SummarizedClassAnnotationsBuilder()
      ..className = className
      ..inputs = inputs
      ..outputs = outputs
      ..contentChildFields = contentChildFields
      ..contentChildrenFields = contentChildrenFields;
  }

  UnlinkedDartSummaryBuilder serializeDartResult(DirectivesResult result) {
    final dirSums = serializeDirectives(result.directives);
    final pipeSums = serializePipes(result.pipes);
    final classSums = result.angularAnnotatedClasses
        .where((c) => c is! AbstractDirective)
        .map(serializeAnnotatedClass)
        .toList();
    final summary = new UnlinkedDartSummaryBuilder()
      ..directiveSummaries = dirSums
      ..pipeSummaries = pipeSums
      ..annotatedClasses = classSums
      ..errors = summarizeErrors(result.errors);
    return summary;
  }

  List<SummarizedDirectiveBuilder> serializeDirectives(
      List<AbstractDirective> directives) {
    final dirSums = <SummarizedDirectiveBuilder>[];
    for (final directive in directives) {
      final selector = directive.selector.originalString;
      final selectorOffset = directive.selector.offset;
      final exportAs = directive?.exportAs?.name;
      final exportAsOffset = directive?.exportAs?.nameOffset;
      final exports = <SummarizedExportedIdentifierBuilder>[];
      if (directive is Component) {
        for (final export in directive?.view?.exports ?? <Null>[]) {
          exports.add(new SummarizedExportedIdentifierBuilder()
            ..name = export.identifier
            ..prefix = export.prefix
            ..offset = export.span.offset
            ..length = export.span.length);
        }
      }
      List<SummarizedDirectiveUseBuilder> dirUseSums;
      List<SummarizedPipesUseBuilder> pipeUseSums;
      final ngContents = <SummarizedNgContentBuilder>[];
      String templateUrl;
      int templateUrlOffset;
      int templateUrlLength;
      String templateText;
      int templateTextOffset;
      SourceRange constDirectivesSourceRange;
      if (directive is Component && directive.view != null) {
        templateUrl = directive.view?.templateUriSource?.fullName;
        templateUrlOffset = directive.view?.templateUrlRange?.offset;
        templateUrlLength = directive.view?.templateUrlRange?.length;
        templateText = directive.view.templateText;
        templateTextOffset = directive.view.templateOffset;

        dirUseSums = directive.view.directivesStrategy.resolve(
            (references) => references
                .map((reference) => new SummarizedDirectiveUseBuilder()
                  ..name = reference.name
                  ..prefix = reference.prefix
                  ..offset = reference.range.offset
                  ..length = reference.range.length)
                .toList(),
            (constValue, _) => null);

        pipeUseSums = directive.view.pipeReferences
            .map((pipe) => new SummarizedPipesUseBuilder()
              ..name = pipe.identifier
              ..prefix = pipe.prefix)
            .toList();

        constDirectivesSourceRange = directive.view.directivesStrategy.resolve(
            (references) => null, (constValue, sourceRange) => sourceRange);

        if (directive.ngContents != null) {
          ngContents.addAll(serializeNgContents(directive.ngContents));
        }
      }

      dirSums.add(new SummarizedDirectiveBuilder()
        ..classAnnotations = directive is AbstractClassDirective
            ? serializeAnnotatedClass(directive)
            : null
        ..isComponent = directive is Component
        ..functionName =
            directive is FunctionalDirective ? directive.name : null
        ..selectorStr = selector
        ..selectorOffset = selectorOffset
        ..exportAs = exportAs
        ..exportAsOffset = exportAsOffset
        ..templateText = templateText
        ..templateOffset = templateTextOffset
        ..templateUrl = templateUrl
        ..templateUrlOffset = templateUrlOffset
        ..templateUrlLength = templateUrlLength
        ..ngContents = ngContents
        ..exports = exports
        ..usesArrayOfDirectiveReferencesStrategy = dirUseSums != null
        ..subdirectives = dirUseSums
        ..pipesUse = pipeUseSums
        ..constDirectiveStrategyOffset = constDirectivesSourceRange?.offset
        ..constDirectiveStrategyLength = constDirectivesSourceRange?.length);
    }

    return dirSums;
  }

  List<SummarizedNgContentBuilder> serializeNgContents(
          List<NgContent> ngContents) =>
      ngContents
          .map((ngContent) => new SummarizedNgContentBuilder()
            ..selectorStr = ngContent.selector?.originalString
            ..selectorOffset = ngContent.selector?.offset
            ..offset = ngContent.offset
            ..length = ngContent.length)
          .toList();

  List<SummarizedPipeBuilder> serializePipes(List<Pipe> pipes) {
    final pipeSums = <SummarizedPipeBuilder>[];
    for (final pipe in pipes) {
      pipeSums.add(new SummarizedPipeBuilder(
          pipeName: pipe.pipeName,
          pipeNameOffset: pipe.pipeNameOffset,
          decoratedClassName: pipe.classElement.name,
          isPure: pipe.isPure));
    }
    return pipeSums;
  }

  SummarizedAnalysisErrorBuilder summarizeError(AnalysisError error) =>
      new SummarizedAnalysisErrorBuilder(
          offset: error.offset,
          length: error.length,
          errorCode: error.errorCode.uniqueName,
          message: error.message,
          correction: error.correction);

  List<SummarizedAnalysisErrorBuilder> summarizeErrors(
          List<AnalysisError> errors) =>
      errors.map(summarizeError).toList();

  bool _ownsFile(String path) =>
      path.endsWith('.dart') || path.endsWith('.html');

  Future<DirectivesResult> _resolveDart(String path,
      {bool ignoreCache: false, bool onlyIfChangedSignature: true}) async {
    // This happens when the path is..."hidden by a generated file"..whch I
    // don't understand, but, can protect against. Should not be analyzed.
    // TODO detect this on file add rather than on file analyze.
    if (await dartDriver.getUnitElementSignature(path) == null) {
      _dartFiles.remove(path);
      return null;
    }

    final baseKey = (await _fileTracker.getUnitElementSignature(path)).toHex();
    final key = '$baseKey.ngresolved';

    if (lastSignatures[path] == key && onlyIfChangedSignature) {
      return null;
    }

    lastSignatures[path] = key;

    if (!ignoreCache) {
      final bytes = byteStore.get(key);
      if (bytes != null) {
        final summary = new LinkedDartSummary.fromBuffer(bytes);

        for (final htmlPath in summary.referencedHtmlFiles) {
          _htmlFilesToAnalyze.add(htmlPath);
        }

        _fileTracker
          ..setDartHasTemplate(path, summary.hasDartTemplates)
          ..setDartHtmlTemplates(path, summary.referencedHtmlFiles)
          ..setDartImports(path, summary.referencedDartFiles);

        final result = new DirectivesResult.fromCache(
            path, deserializeErrors(getSource(path), summary.errors));
        _dartResultsController.add(result);
        return result;
      }
    }

    final result = await getAngularTopLevels(path);
    final directives = result.directives;
    final pipes = result.pipes;
    final unit = (await dartDriver.getUnitElement(path)).element;
    if (unit == null) {
      return null;
    }
    final context = unit.context;
    final source = unit.source;

    final errors = new List<AnalysisError>.from(result.errors);
    final standardHtml = await getStandardHtml();

    final linkErrorListener = new RecordingErrorListener();
    final linkErrorReporter = new ErrorReporter(linkErrorListener, source);

    final linker = new ChildDirectiveLinker(this, this,
        await getStandardAngular(), await getStandardHtml(), linkErrorReporter);
    await linker.linkDirectivesAndPipes(directives, pipes, unit.library);
    final attrValidator = new AttributeAnnotationValidator(linkErrorReporter);
    new List<AbstractClassDirective>.from(
            directives.where((d) => d is AbstractClassDirective))
        .forEach(attrValidator.validate);
    errors.addAll(linkErrorListener.errors);

    final htmlViews = <String>[];
    final usesDart = <String>[];
    final fullyResolvedDirectives = <AbstractDirective>[];

    var hasDartTemplate = false;
    for (final directive in directives) {
      if (directive is Component) {
        final view = directive.view;
        if ((view?.templateText ?? '') != '') {
          hasDartTemplate = true;
          final tplErrorListener = new RecordingErrorListener();
          final errorReporter = new ErrorReporter(tplErrorListener, source);
          final template = new Template(view);
          view.template = template;

          final tplParser = new TemplateParser()
            ..parse(view.templateText, source, offset: view.templateOffset);

          final document = tplParser.rawAst;
          final parser =
              new EmbeddedDartParser(source, tplErrorListener, errorReporter);

          template.ast = new HtmlTreeConverter(parser, source, tplErrorListener)
              .convertFromAstList(tplParser.rawAst);
          template.ast.accept(new NgContentRecorder(directive, errorReporter));
          setIgnoredErrors(template, document);
          new TemplateResolver(
                  context.typeProvider,
                  context.typeSystem,
                  standardHtml.components.values.toList(),
                  standardHtml.events,
                  standardHtml.attributes,
                  await getStandardAngular(),
                  await getStandardHtml(),
                  tplErrorListener,
                  options)
              .resolve(template);
          errors
            ..addAll(tplParser.parseErrors.where(
                (e) => !view.template.ignoredErrors.contains(e.errorCode.name)))
            ..addAll(tplErrorListener.errors.where((e) =>
                !view.template.ignoredErrors.contains(e.errorCode.name)));
          fullyResolvedDirectives.add(directive);
        } else if (view?.templateUriSource != null) {
          _htmlFilesToAnalyze.add(view.templateUriSource.fullName);
          htmlViews.add(view.templateUriSource.fullName);
        }

        for (final subDirective in (view?.directives ?? <Null>[])) {
          usesDart.add(subDirective.source.fullName);
        }
      }
    }

    _fileTracker
      ..setDartHasTemplate(path, hasDartTemplate)
      ..setDartHtmlTemplates(path, htmlViews)
      ..setDartImports(path, usesDart);

    final summary = new LinkedDartSummaryBuilder()
      ..errors = summarizeErrors(errors)
      ..referencedHtmlFiles = htmlViews
      ..referencedDartFiles = usesDart
      ..hasDartTemplates = hasDartTemplate;
    final newBytes = summary.toBuffer();
    byteStore.put(key, newBytes);
    final directivesResult = new DirectivesResult(
        path, directives, pipes, errors,
        fullyResolvedDirectives: fullyResolvedDirectives);
    _dartResultsController.add(directivesResult);
    return directivesResult;
  }

  Future<DirectivesResult> _resolveHtml(
    String htmlPath, {
    bool ignoreCache: false,
  }) async {
    final key = await getHtmlKey(htmlPath);
    final bytes = byteStore.get(key);
    final htmlSource = _sourceFactory.forUri('file:$htmlPath');
    if (!ignoreCache && bytes != null) {
      final summary = new LinkedHtmlSummary.fromBuffer(bytes);
      final errors = deserializeErrors(htmlSource, summary.errors);
      final result = new DirectivesResult.fromCache(htmlPath, errors);
      _htmlResultsController.add(result);
      return result;
    }

    final result = new DirectivesResult(htmlPath, [], [], []);

    for (final dartContext
        in _fileTracker.getDartPathsReferencingHtml(htmlPath)) {
      final pairResult = await _resolveHtmlFrom(htmlPath, dartContext);
      result.angularTopLevels.addAll(pairResult.angularTopLevels);
      result.errors.addAll(pairResult.errors);
      result.fullyResolvedDirectives.addAll(pairResult.fullyResolvedDirectives);
    }

    final summary = new LinkedHtmlSummaryBuilder()
      ..errors = summarizeErrors(result.errors);
    final newBytes = summary.toBuffer();
    byteStore.put(key, newBytes);

    _htmlResultsController.add(result);
    return result;
  }

  Future<DirectivesResult> _resolveHtmlFrom(
      String htmlPath, String dartPath) async {
    final result = await getAngularTopLevels(dartPath);
    final directives = result.directives;
    final pipes = result.pipes;
    final unit = (await dartDriver.getUnitElement(dartPath)).element;
    final htmlSource = _sourceFactory.forUri('file:$htmlPath');

    if (unit == null) {
      return null;
    }
    final context = unit.context;
    final dartSource = _sourceFactory.forUri('file:$dartPath');
    final htmlContent = getFileContent(htmlPath);
    final standardHtml = await getStandardHtml();

    final errors = <AnalysisError>[];
    // ignore link errors, they are exposed when resolving dart
    final linkErrorListener = new IgnoringErrorListener();
    final linkErrorReporter = new ErrorReporter(linkErrorListener, dartSource);

    final linker = new ChildDirectiveLinker(this, this,
        await getStandardAngular(), await getStandardHtml(), linkErrorReporter);
    await linker.linkDirectivesAndPipes(directives, pipes, unit.library);
    final attrValidator = new AttributeAnnotationValidator(linkErrorReporter);

    new List<AbstractClassDirective>.from(
            directives.where((d) => d is AbstractClassDirective))
        .forEach(attrValidator.validate);

    final fullyResolvedDirectives = <AbstractDirective>[];

    for (final directive in directives) {
      if (directive is Component) {
        final view = directive.view;
        if (view.templateUriSource?.fullName == htmlPath) {
          final tplErrorListener = new RecordingErrorListener();
          final errorReporter = new ErrorReporter(tplErrorListener, dartSource);
          final template = new Template(view);
          view.template = template;

          final tplParser = new TemplateParser()
            ..parse(htmlContent, htmlSource);

          final document = tplParser.rawAst;
          final parser = new EmbeddedDartParser(
              htmlSource, tplErrorListener, errorReporter);

          template.ast =
              new HtmlTreeConverter(parser, htmlSource, tplErrorListener)
                  .convertFromAstList(tplParser.rawAst);
          template.ast.accept(new NgContentRecorder(directive, errorReporter));
          setIgnoredErrors(template, document);
          new TemplateResolver(
                  context.typeProvider,
                  context.typeSystem,
                  standardHtml.components.values.toList(),
                  standardHtml.events,
                  standardHtml.attributes,
                  await getStandardAngular(),
                  await getStandardHtml(),
                  tplErrorListener,
                  options)
              .resolve(template);

          bool rightErrorType(AnalysisError e) =>
              !view.template.ignoredErrors.contains(e.errorCode.name);
          String shorten(String filename) {
            final index = filename.lastIndexOf('.');
            return index == -1 ? filename : filename.substring(0, index);
          }

          errors.addAll(tplParser.parseErrors.where(rightErrorType));

          if (shorten(view.source.fullName) !=
              shorten(view.templateSource.fullName)) {
            errors.addAll(tplErrorListener.errors.where(rightErrorType).map(
                (e) =>
                    prefixError(view.source, directive.classElement.name, e)));
          } else {
            errors.addAll(tplErrorListener.errors.where(rightErrorType));
          }

          fullyResolvedDirectives.add(directive);
        }
      }
    }

    return new DirectivesResult(htmlPath, directives, pipes, errors,
        fullyResolvedDirectives: fullyResolvedDirectives);
  }
}

class DirectivesResult {
  final String filename;
  final List<AngularTopLevel> angularTopLevels;
  final List<AbstractDirective> fullyResolvedDirectives = [];
  List<AnalysisError> errors;
  List<Pipe> pipes;
  bool cacheResult;
  DirectivesResult(
      this.filename, this.angularTopLevels, this.pipes, this.errors,
      {List<AbstractDirective> fullyResolvedDirectives: const []})
      : cacheResult = false {
    // Use `addAll` instead of initializing it to `const []` when not specified,
    // so that the result is not const and we can add to it, while still being
    // final.
    this.fullyResolvedDirectives.addAll(fullyResolvedDirectives);
  }

  DirectivesResult.fromCache(this.filename, this.errors)
      : angularTopLevels = const [],
        cacheResult = true;
  List<AngularAnnotatedClass> get angularAnnotatedClasses =>
      new List<AngularAnnotatedClass>.from(
          angularTopLevels.where((c) => c is AngularAnnotatedClass));

  List<AbstractDirective> get directives => new List<AbstractDirective>.from(
      angularTopLevels.where((c) => c is AbstractDirective));
}
