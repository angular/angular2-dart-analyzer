import 'dart:async';
import 'dart:collection';

import 'package:analyzer_plugin/protocol/protocol_common.dart' as protocol
    show Element, ElementKind;
import 'package:analyzer_plugin/utilities/completion/completion_core.dart';
import 'package:analyzer_plugin/utilities/completion/relevance.dart';
import 'package:analyzer_plugin/src/utilities/completion/optype.dart';
import 'package:analyzer_plugin/src/utilities/completion/completion_core.dart';
import 'package:analysis_server/src/services/completion/dart/completion_manager.dart';
import 'package:analysis_server/src/services/completion/dart/type_member_contributor.dart';
import 'package:analysis_server/src/services/completion/dart/inherited_reference_contributor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/generated/resolver.dart' show TypeProvider;
import 'package:angular_analyzer_plugin/src/converter.dart';
import 'package:angular_analyzer_plugin/src/model.dart';
import 'package:angular_analyzer_plugin/src/selector.dart';
import 'package:angular_analyzer_plugin/ast.dart';
import 'package:angular_analyzer_plugin/src/angular_driver.dart';
import 'package:angular_analysis_plugin/src/resolve_result.dart';

import 'package:analysis_server/src/protocol_server.dart'
    show CompletionSuggestion, CompletionSuggestionKind, Location;

import 'package:analysis_server/src/protocol_server.dart'
    show CompletionSuggestion;

import 'embedded_dart_completion_request.dart';

bool offsetContained(int offset, int start, int length) =>
    start <= offset && start + length >= offset;

AngularAstNode findTarget(int offset, AngularAstNode root) {
  for (final child in root.children) {
    // `*ngIf="x"` creates, inside the template attr, a property binding named
    // `ngIf`, which will confuse our autocompleter. Skip it.
    if (root is TemplateAttribute &&
        child is AttributeInfo &&
        child.name == root.prefix) {
      continue;
    }

    if (child is ElementInfo) {
      if (child.isSynthetic) {
        final target = findTarget(offset, child);
        if (!(target is ElementInfo && target.openingSpan == null)) {
          return target;
        }
      } else {
        if (offsetContained(offset, child.openingNameSpan.offset,
            child.openingNameSpan.length)) {
          return child;
        } else if (offsetContained(offset, child.offset, child.length)) {
          return findTarget(offset, child);
        }
      }
    } else if (offsetContained(offset, child.offset, child.length)) {
      return findTarget(offset, child);
    }
  }
  return root;
}

class DartSnippetExtractor extends AngularAstVisitor {
  AstNode dartSnippet;
  int offset;

  @override
  void visitDocumentInfo(DocumentInfo document) {}

  // don't recurse, findTarget already did that
  @override
  void visitElementInfo(ElementInfo element) {}

  @override
  void visitTextAttr(TextAttribute attr) {}

  @override
  void visitExpressionBoundAttr(ExpressionBoundAttribute attr) {
    if (attr.expression != null &&
        offsetContained(
            offset, attr.expression.offset, attr.expression.length)) {
      dartSnippet = attr.expression;
    }
  }

  @override
  void visitStatementsBoundAttr(StatementsBoundAttribute attr) {
    for (final statement in attr.statements) {
      if (offsetContained(offset, statement.offset, statement.length)) {
        dartSnippet = statement;
      }
    }
  }

  @override
  void visitMustache(Mustache mustache) {
    if (offsetContained(
        offset, mustache.exprBegin, mustache.exprEnd - mustache.exprBegin)) {
      dartSnippet = mustache.expression;
    }
  }

  @override
  void visitTemplateAttr(TemplateAttribute attr) {
    if (attr.value == null ||
        !offsetContained(offset, attr.valueOffset, attr.value.length)) {
      return;
    }

    // if we visit this, we're in a template but after one of its attributes.
    AttributeInfo attributeToAppendTo;
    for (final subAttribute in attr.virtualAttributes) {
      if (subAttribute.valueOffset == null && subAttribute.offset < offset) {
        attributeToAppendTo = subAttribute;
      }
    }

    if (attributeToAppendTo != null &&
        attributeToAppendTo is TextAttribute &&
        !attributeToAppendTo.name.startsWith("let")) {
      final analysisErrorListener = new IgnoringAnalysisErrorListener();
      final dartParser =
          new EmbeddedDartParser(null, analysisErrorListener, null);
      dartSnippet =
          dartParser.parseDartExpression(offset, '', detectTrailing: false);
    }
  }
}

class IgnoringAnalysisErrorListener implements AnalysisErrorListener {
  @override
  void onError(AnalysisError error) {}
}

class LocalVariablesExtractor extends AngularAstVisitor {
  Map<String, LocalVariable> variables;

  // don't recurse, findTarget already did that
  @override
  void visitDocumentInfo(DocumentInfo document) {}

  @override
  void visitElementInfo(ElementInfo element) {}

  @override
  void visitTextAttr(TextAttribute attr) {}

  @override
  void visitExpressionBoundAttr(ExpressionBoundAttribute attr) {
    variables = attr.localVariables;
  }

  @override
  void visitStatementsBoundAttr(StatementsBoundAttribute attr) {
    variables = attr.localVariables;
  }

  @override
  void visitMustache(Mustache mustache) {
    variables = mustache.localVariables;
  }
}

class ReplacementRangeCalculator extends AngularAstVisitor {
  CompletionRequestImpl request;
  CompletionCollector collector;

  ReplacementRangeCalculator(this.request, this.collector);

  @override
  void visitDocumentInfo(DocumentInfo document) {}

  // don't recurse, findTarget already did that
  @override
  void visitElementInfo(ElementInfo element) {
    if (element.openingSpan == null) {
      return;
    }
    final nameSpanEnd =
        element.openingNameSpan.offset + element.openingNameSpan.length;
    if (offsetContained(request.offset, element.openingSpan.offset,
        nameSpanEnd - element.openingSpan.offset)) {
      collector
        ..offset = element.openingSpan.offset
        ..length = element.localName.length + 1;
    }
  }

  @override
  void visitTextAttr(TextAttribute attr) {
    collector
      ..offset = attr.offset
      ..offset = attr.length;
  }

  @override
  void visitTextInfo(TextInfo textInfo) {
    if (request.offset > textInfo.offset &&
        textInfo.text[request.offset - textInfo.offset - 1] == '<') {
      collector.offset--;
      collector.length = 1;
    }
  }

  @override
  void visitExpressionBoundAttr(ExpressionBoundAttribute attr) {
    if (offsetContained(
        request.offset, attr.originalNameOffset, attr.originalName.length)) {
      collector
        ..offset = attr.originalNameOffset
        ..length = attr.originalName.length;
    }
  }

  @override
  void visitStatementsBoundAttr(StatementsBoundAttribute attr) {
    if (offsetContained(
        request.offset, attr.originalNameOffset, attr.originalName.length)) {
      collector
        ..offset = attr.originalNameOffset
        ..length = attr.originalName.length;
    }
  }

  @override
  void visitMustache(Mustache mustache) {}

  @override
  void visitTemplateAttr(TemplateAttribute attr) {
    if (offsetContained(
        request.offset, attr.originalNameOffset, attr.originalName.length)) {
      collector
        ..offset = attr.originalNameOffset
        ..length = attr.originalName.length;
    }
  }
}

/// Contributor to contribute angular entities.
class AngularCompletionContributor extends CompletionContributor {
  final AngularDriver driver;

  /// Initialize a newly created handler to handle requests for the given
  /// [server].
  AngularCompletionContributor(this.driver);

  /// Return a [Future] that completes with a list of suggestions
  /// for the given completion [request].
  @override
  Future<Null> computeSuggestions(
      CompletionRequest request, CompletionCollector collector) async {
    final path = request.result.path;
    final templates = await driver.getTemplatesForFile(path);
    if (templates.isEmpty) {
      return null;
    }

    await driver.getStandardHtml();
    assert(driver.standardHtml != null);

    final events = driver.standardHtml.events.values;
    final attributes = driver.standardHtml.uniqueAttributeElements;

    final templateCompleter = new TemplateCompleter();
    for (final template in templates) {
      // Indicates template comes from .html file.
      final isFromHtmlFile = template.view.templateUriSource != null;

      // A single .dart file can have multiple templates; find
      // template for where autocompletion request occurred on.
      final isFromValidDartTemplate =
          template.view.templateOffset <= request.offset &&
              request.offset < template.view.end;

      if (isFromHtmlFile || isFromValidDartTemplate) {
        await templateCompleter.computeSuggestions(
          request,
          collector,
          template,
          events,
          attributes,
        );
      }
    }
  }
}

class TemplateCompleter {
  static const int RELEVANCE_TRANSCLUSION = DART_RELEVANCE_DEFAULT + 10;

  Future<Null> computeSuggestions(
    CompletionRequest request,
    CompletionCollector collector,
    Template template,
    List<OutputElement> standardHtmlEvents,
    Set<InputElement> standardHtmlAttributes,
  ) async {
    final typeProvider = template.view.component.classElement.enclosingElement
        .enclosingElement.context.typeProvider;
    final target = findTarget(request.offset, template.ast)
      ..accept(new ReplacementRangeCalculator(request, collector));
    final extractor = new DartSnippetExtractor()..offset = request.offset;
    target.accept(extractor);

    // If [CompletionRequest] is in
    // [StatementsBoundAttribute],
    // [ExpressionsBoundAttribute],
    // [Mustache],
    // [TemplateAttribute].
    if (extractor.dartSnippet != null) {
      final dartRequest = new EmbeddedDartCompletionRequest.from(
          request, extractor.dartSnippet);
      final range =
          new ReplacementRange.compute(dartRequest.offset, dartRequest.target);
      collector
        ..offset = range.offset
        ..length = range.length;

      dartRequest.libraryElement = template.view.classElement.library;
      final memberContributor = new TypeMemberContributor();
      final inheritedContributor = new InheritedReferenceContributor();
      inheritedContributor
          .computeSuggestionsForClass(
            template.view.classElement,
            dartRequest,
            skipChildClass: false,
          )
          .forEach(collector.addSuggestion);
      await memberContributor
          .computeSuggestions(dartRequest)
          .then((results) => results.forEach(collector.addSuggestion));

      if (dartRequest.opType.includeIdentifiers) {
        final varExtractor = new LocalVariablesExtractor();
        target.accept(varExtractor);
        if (varExtractor.variables != null) {
          addLocalVariables(
            collector,
            varExtractor.variables,
            dartRequest.opType,
          );
        }
      }
    } else if (target is ElementInfo) {
      if (target.closingSpan != null &&
          offsetContained(request.offset, target.closingSpan.offset,
              target.closingSpan.length)) {
        if (request.offset ==
            (target.closingSpan.offset + target.closingSpan.length)) {
          // In closing tag, but could be directly after it; ex: '</div>^'.
          suggestHtmlTags(template, collector);
          if (target.parent != null || target.parent is! DocumentInfo) {
            suggestTransclusions(target.parent, collector);
          }
        }
      } else if (!offsetContained(request.offset, target.openingNameSpan.offset,
          target.openingNameSpan.length)) {
        // If request is not in [openingNameSpan], suggest decorators.
        suggestInputs(
          target.boundDirectives,
          collector,
          standardHtmlAttributes,
          target.boundStandardInputs,
          typeProvider,
          includePlainAttributes: true,
        );
        suggestOutputs(
          target.boundDirectives,
          collector,
          standardHtmlEvents,
          target.boundStandardOutputs,
        );
        suggestBananas(
          target.boundDirectives,
          collector,
          target.boundStandardInputs,
          target.boundStandardOutputs,
        );
        suggestFromAvailableDirectives(
          target.availableDirectives,
          collector,
          suggestPlainAttributes: true,
          suggestInputs: true,
          suggestBananas: true,
        );
        if (!target.isOrHasTemplateAttribute) {
          suggestStarAttrs(template, collector);
        }
      } else {
        // Otherwise, suggest HTML tags and transclusions.
        suggestHtmlTags(template, collector);
        if (target.parent != null || target.parent is! DocumentInfo) {
          suggestTransclusions(target.parent, collector);
        }
      }
    } else if (target is AttributeInfo && target.parent is TemplateAttribute) {
      // `let foo`. Nothing to suggest.
      if (target is TextAttribute && target.name.startsWith("let-")) {
        return null;
      }

      if (offsetContained(request.offset, target.originalNameOffset,
          target.originalName.length)) {
        suggestInputsInTemplate(target.parent, collector, currentAttr: target);
      } else {
        suggestInputsInTemplate(target.parent, collector);
      }
    } else if (target is ExpressionBoundAttribute &&
        offsetContained(request.offset, target.originalNameOffset,
            target.originalName.length)) {
      final _suggestInputs = target.bound == ExpressionBoundType.input;
      var _suggestBananas = target.bound == ExpressionBoundType.twoWay;

      if (_suggestInputs) {
        _suggestBananas = target.nameOffset == request.offset;
        suggestInputs(
            target.parent.boundDirectives,
            collector,
            standardHtmlAttributes,
            target.parent.boundStandardInputs,
            typeProvider,
            currentAttr: target);
      }
      if (_suggestBananas) {
        suggestBananas(
          target.parent.boundDirectives,
          collector,
          target.parent.boundStandardInputs,
          target.parent.boundStandardOutputs,
          currentAttr: target,
        );
      }
      suggestFromAvailableDirectives(
        target.parent.availableDirectives,
        collector,
        suggestBananas: _suggestBananas,
        suggestInputs: _suggestInputs,
      );
    } else if (target is StatementsBoundAttribute) {
      suggestOutputs(target.parent.boundDirectives, collector,
          standardHtmlEvents, target.parent.boundStandardOutputs,
          currentAttr: target);
    } else if (target is TemplateAttribute) {
      if (offsetContained(request.offset, target.originalNameOffset,
          target.originalName.length)) {
        suggestStarAttrs(template, collector);
      }
      suggestInputsInTemplate(target, collector);
    } else if (target is TextAttribute &&
        target.nameOffset != null &&
        offsetContained(
            request.offset, target.nameOffset, target.name.length)) {
      suggestInputs(
          target.parent.boundDirectives,
          collector,
          standardHtmlAttributes,
          target.parent.boundStandardInputs,
          typeProvider,
          includePlainAttributes: true);
      suggestOutputs(target.parent.boundDirectives, collector,
          standardHtmlEvents, target.parent.boundStandardOutputs);
      suggestBananas(
        target.parent.boundDirectives,
        collector,
        target.parent.boundStandardInputs,
        target.parent.boundStandardOutputs,
      );
      suggestFromAvailableDirectives(
        target.parent.availableDirectives,
        collector,
        suggestPlainAttributes: true,
        suggestInputs: true,
        suggestBananas: true,
      );
    } else if (target is TextInfo) {
      suggestHtmlTags(template, collector);
      suggestTransclusions(target.parent, collector);
    }
  }

  void suggestTransclusions(
      ElementInfo container, CompletionCollector collector) {
    for (final directive in container.directives) {
      if (directive is! Component) {
        continue;
      }

      final Component component = directive;
      final view = component?.view;
      if (view == null) {
        continue;
      }

      for (final ngContent in component.ngContents) {
        if (ngContent.selector == null) {
          continue;
        }

        final tags = ngContent.selector.suggestTags();
        for (final tag in tags) {
          final location = new Location(view.templateSource.fullName,
              ngContent.offset, ngContent.length, 0, 0);
          collector.addSuggestion(_createHtmlTagSuggestion(
              tag.toString(),
              RELEVANCE_TRANSCLUSION,
              _createHtmlTagTransclusionElement(tag.toString(),
                  protocol.ElementKind.CLASS_TYPE_ALIAS, location)));
        }
      }
    }
  }

  void suggestHtmlTags(Template template, CompletionCollector collector) {
    final elementTagMap = template.view.elementTagsInfo;
    for (final elementTagName in elementTagMap.keys) {
      final currentSuggestion = _createHtmlTagSuggestion(
          '<$elementTagName',
          DART_RELEVANCE_DEFAULT,
          _createHtmlTagElement(
              elementTagName,
              elementTagMap[elementTagName].first,
              protocol.ElementKind.CLASS_TYPE_ALIAS));
      if (currentSuggestion != null) {
        collector.addSuggestion(currentSuggestion);
      }
    }
  }

  void suggestInputs(
    List<DirectiveBinding> directives,
    CompletionCollector collector,
    Set<InputElement> standardHtmlAttributes,
    List<InputBinding> boundStandardAttributes,
    TypeProvider typeProvider, {
    ExpressionBoundAttribute currentAttr,
    bool includePlainAttributes: false,
  }) {
    for (final directive in directives) {
      final usedInputs = new HashSet.from(directive.inputBindings
          .where((b) => b.attribute != currentAttr)
          .map((b) => b.boundInput)).toSet();

      for (final input in directive.boundDirective.inputs) {
        // don't recommend [name] [name] [name]
        if (usedInputs.contains(input)) {
          continue;
        }

        if (includePlainAttributes && typeProvider != null) {
          if (typeProvider.stringType.isAssignableTo(input.setterType)) {
            final relevance = input.setterType.displayName == 'String'
                ? DART_RELEVANCE_DEFAULT
                : DART_RELEVANCE_DEFAULT - 1;
            collector.addSuggestion(_createPlainAttributeSuggestions(
                input.name,
                relevance,
                _createPlainAttributeElement(
                  input.name,
                  input.nameOffset,
                  input.source.fullName,
                  protocol.ElementKind.SETTER,
                )));
          }
        }
        collector.addSuggestion(_createInputSuggestion(
            input,
            DART_RELEVANCE_DEFAULT,
            _createInputElement(input, protocol.ElementKind.SETTER)));
      }
    }

    final usedStdInputs = new HashSet.from(boundStandardAttributes
        .where((b) => b.attribute != currentAttr)
        .map((b) => b.boundInput)).toSet();

    for (final input in standardHtmlAttributes) {
      // TODO don't recommend [hidden] [hidden] [hidden]
      if (usedStdInputs.contains(input)) {
        continue;
      }
      if (includePlainAttributes && typeProvider != null) {
        if (typeProvider.stringType.isAssignableTo(input.setterType)) {
          final relevance = input.setterType.displayName == 'String'
              ? DART_RELEVANCE_DEFAULT - 2
              : DART_RELEVANCE_DEFAULT - 3;
          collector.addSuggestion(_createPlainAttributeSuggestions(
              input.name,
              relevance,
              _createPlainAttributeElement(
                input.name,
                input.nameOffset,
                input.source.fullName,
                protocol.ElementKind.SETTER,
              )));
        }
      }
      collector.addSuggestion(_createInputSuggestion(
          input,
          DART_RELEVANCE_DEFAULT - 2,
          _createInputElement(input, protocol.ElementKind.SETTER)));
    }
  }

  void suggestInputsInTemplate(
      TemplateAttribute templateAttr, CompletionCollector collector,
      {AttributeInfo currentAttr}) {
    final directives = templateAttr.boundDirectives;
    for (final binding in directives) {
      final usedInputs = new HashSet.from(binding.inputBindings
          .where((b) => b.attribute != currentAttr)
          .map((b) => b.boundInput)).toSet();

      for (final input in binding.boundDirective.inputs) {
        // don't recommend trackBy: x trackBy: x trackBy: x
        if (usedInputs.contains(input)) {
          continue;
        }
        // edge case. Don't think this comes up in standard.
        if (!input.name.startsWith(templateAttr.prefix)) {
          continue;
        }
        collector.addSuggestion(_createInputInTemplateSuggestion(
            templateAttr.prefix,
            input,
            DART_RELEVANCE_DEFAULT,
            _createInputElement(input, protocol.ElementKind.SETTER)));
      }
    }
  }

  void suggestOutputs(
      List<DirectiveBinding> directives,
      CompletionCollector collector,
      List<OutputElement> standardHtmlEvents,
      List<OutputBinding> boundStandardOutputs,
      {BoundAttributeInfo currentAttr}) {
    for (final directive in directives) {
      final usedOutputs = new HashSet.from(directive.outputBindings
          .where((b) => b.attribute != currentAttr)
          .map((b) => b.boundOutput)).toSet();
      for (final output in directive.boundDirective.outputs) {
        // don't recommend (close) (close) (close)
        if (usedOutputs.contains(output)) {
          continue;
        }
        collector.addSuggestion(_createOutputSuggestion(
            output,
            DART_RELEVANCE_DEFAULT,
            _createOutputElement(output, protocol.ElementKind.GETTER)));
      }
    }

    final usedStdOutputs = new HashSet.from(boundStandardOutputs
        .where((b) => b.attribute != currentAttr)
        .map((b) => b.boundOutput)).toSet();

    for (final output in standardHtmlEvents) {
      // don't recommend (click) (click) (click)
      if (usedStdOutputs.contains(output)) {
        continue;
      }
      collector.addSuggestion(_createOutputSuggestion(
          output,
          DART_RELEVANCE_DEFAULT - 1, // just below regular relevance
          _createOutputElement(output, protocol.ElementKind.GETTER)));
    }
  }

  void suggestBananas(
      List<DirectiveBinding> directives,
      CompletionCollector collector,
      List<InputBinding> boundStandardAttributes,
      List<OutputBinding> boundStandardOutputs,
      {BoundAttributeInfo currentAttr}) {
    // Handle potential two-way found in bound directives
    // There are no standard event/attribute that fall under two-way binding.
    for (final directive in directives) {
      final usedInputs = new HashSet.from(directive.inputBindings
          .where((b) => b.attribute != currentAttr)
          .map((b) => b.boundInput)).toSet();
      final usedOutputs = new HashSet.from(directive.outputBindings
          .where((b) => b.attribute != currentAttr)
          .map((b) => b.boundOutput)).toSet();

      final availableInputs = new HashSet.from(directive.boundDirective.inputs)
          .difference(usedInputs);
      final availableOutputs =
          new HashSet.from(directive.boundDirective.outputs)
              .difference(usedOutputs);
      for (final input in availableInputs) {
        final inputName = input.name;
        final complementName = '${inputName}Change';
        final output = availableOutputs
            .firstWhere((o) => o.name == complementName, orElse: () => null);
        if (output != null) {
          collector.addSuggestion(_createBananaSuggestion(
              input,
              DART_RELEVANCE_DEFAULT,
              _createBananaElement(input, protocol.ElementKind.SETTER)));
        }
      }
    }
  }

  void suggestStarAttrs(Template template, CompletionCollector collector) {
    template.view.directives.where((d) => d.looksLikeTemplate).forEach(
        (directive) =>
            suggestStarAttrsForSelector(directive.selector, collector));
  }

  void suggestStarAttrsForSelector(
      Selector selector, CompletionCollector collector) {
    if (selector is OrSelector) {
      for (final subselector in selector.selectors) {
        suggestStarAttrsForSelector(subselector, collector);
      }
    } else if (selector is AndSelector) {
      for (final subselector in selector.selectors) {
        suggestStarAttrsForSelector(subselector, collector);
      }
    } else if (selector is AttributeSelector) {
      if (selector.nameElement.name == "ngForOf") {
        // `ngFor`'s selector includes `[ngForOf]`, but `*ngForOf=..` won't ever
        // work, because it then becomes impossible to satisfy the other half,
        // `[ngFor]`. Hardcode to filter this out, rather than using some kind
        // of complex heuristic.
        return;
      }

      collector.addSuggestion(_createStarAttrSuggestion(
          selector,
          DART_RELEVANCE_DEFAULT,
          _createStarAttrElement(selector, protocol.ElementKind.CLASS)));
    }
  }

  /// Goes through all the available, but not yet-bound directives
  /// and extracts non-violating plain-text attribute-directives
  /// and inputs (if name overlaps with attribute-directive).
  void suggestFromAvailableDirectives(
    Map<AbstractDirective, List<AttributeSelector>> availableDirectives,
    CompletionCollector collector, {
    bool suggestInputs: false,
    bool suggestBananas: false,
    bool suggestPlainAttributes: false,
  }) {
    availableDirectives.forEach((directive, selectors) {
      final attributeSelectors = <String, AttributeSelector>{};
      final validInputs = <InputElement>[];

      for (final aSelector in selectors) {
        attributeSelectors[aSelector.nameElement.name] = aSelector;
      }

      for (final input in directive.inputs) {
        if (attributeSelectors.keys.contains(input.name)) {
          attributeSelectors.remove(input.name);
          validInputs.add(input);
        }
      }

      for (final input in validInputs) {
        final outputComplement = '${input.name}Change';
        final output = directive.outputs.firstWhere(
            (output) => output.name == outputComplement,
            orElse: () => null);
        if (output != null && suggestBananas) {
          collector.addSuggestion(_createBananaSuggestion(
              input,
              DART_RELEVANCE_DEFAULT,
              _createBananaElement(input, protocol.ElementKind.SETTER)));
        }
        if (suggestInputs) {
          collector.addSuggestion(_createInputSuggestion(
              input,
              DART_RELEVANCE_DEFAULT,
              _createInputElement(input, protocol.ElementKind.SETTER)));
        }
      }

      if (suggestPlainAttributes) {
        attributeSelectors.forEach((name, selector) {
          final nameOffset = selector.nameElement.nameOffset;
          final locationSource = selector.nameElement.source.fullName;
          collector.addSuggestion(_createPlainAttributeSuggestions(
              name,
              DART_RELEVANCE_DEFAULT,
              _createPlainAttributeElement(name, nameOffset, locationSource,
                  protocol.ElementKind.SETTER)));
        });
      }
    });
  }

  void addLocalVariables(CompletionCollector collector,
      Map<String, LocalVariable> localVars, OpType optype) {
    for (final eachVar in localVars.values) {
      collector.addSuggestion(_addLocalVariableSuggestion(
          eachVar,
          eachVar.dartVariable.type,
          protocol.ElementKind.LOCAL_VARIABLE,
          optype,
          relevance: DART_RELEVANCE_LOCAL_VARIABLE));
    }
  }

  CompletionSuggestion _addLocalVariableSuggestion(LocalVariable variable,
      DartType typeName, protocol.ElementKind elemKind, OpType optype,
      {int relevance: DART_RELEVANCE_DEFAULT}) {
    // ignore: parameter_assignments
    relevance = optype.returnValueSuggestionsFilter(
            variable.dartVariable.type, relevance) ??
        DART_RELEVANCE_DEFAULT;
    return _createLocalSuggestion(variable, relevance, typeName,
        _createLocalElement(variable, elemKind, typeName));
  }

  CompletionSuggestion _createLocalSuggestion(LocalVariable localVar,
      int defaultRelevance, DartType type, protocol.Element element) {
    final completion = localVar.name;
    return new CompletionSuggestion(CompletionSuggestionKind.INVOCATION,
        defaultRelevance, completion, completion.length, 0, false, false,
        returnType: type.toString(), element: element);
  }

  protocol.Element _createLocalElement(
      LocalVariable localVar, protocol.ElementKind kind, DartType type) {
    final name = localVar.name;
    final location = new Location(localVar.source.fullName, localVar.nameOffset,
        localVar.nameLength, 0, 0);
    final flags = protocol.Element.makeFlags();
    return new protocol.Element(kind, name, flags,
        location: location, returnType: type.toString());
  }

  CompletionSuggestion _createHtmlTagSuggestion(String elementTagName,
          int defaultRelevance, protocol.Element element) =>
      new CompletionSuggestion(
          CompletionSuggestionKind.INVOCATION,
          defaultRelevance,
          elementTagName,
          elementTagName.length,
          0,
          false,
          false,
          element: element);

  protocol.Element _createHtmlTagElement(String elementTagName,
      AbstractDirective directive, protocol.ElementKind kind) {
    final selector = directive.elementTags.firstWhere(
        (currSelector) => currSelector.toString() == elementTagName);
    final offset = selector.nameElement.nameOffset;
    final length = selector.nameElement.nameLength;

    final location =
        new Location(directive.source.fullName, offset, length, 0, 0);
    final flags = protocol.Element
        .makeFlags(isAbstract: false, isDeprecated: false, isPrivate: false);
    return new protocol.Element(kind, '<$elementTagName', flags,
        location: location);
  }

  protocol.Element _createHtmlTagTransclusionElement(
      String elementTagName, protocol.ElementKind kind, Location location) {
    final flags = protocol.Element
        .makeFlags(isAbstract: false, isDeprecated: false, isPrivate: false);
    return new protocol.Element(kind, elementTagName, flags,
        location: location);
  }

  CompletionSuggestion _createInputSuggestion(InputElement inputElement,
      int defaultRelevance, protocol.Element element) {
    final completion = '[${inputElement.name}]';
    return new CompletionSuggestion(CompletionSuggestionKind.INVOCATION,
        defaultRelevance, completion, completion.length, 0, false, false,
        element: element);
  }

  CompletionSuggestion _createInputInTemplateSuggestion(
      String prefix,
      InputElement inputElement,
      int defaultRelevance,
      protocol.Element element) {
    final capitalized = inputElement.name.substring(prefix.length);
    final firstLetter = capitalized.substring(0, 1).toLowerCase();
    final remaining = capitalized.substring(1);
    final completion = '$firstLetter$remaining:';
    return new CompletionSuggestion(CompletionSuggestionKind.INVOCATION,
        defaultRelevance, completion, completion.length, 0, false, false,
        element: element);
  }

  protocol.Element _createInputElement(
      InputElement inputElement, protocol.ElementKind kind) {
    final name = '[${inputElement.name}]';
    final location = new Location(inputElement.source.fullName,
        inputElement.nameOffset, inputElement.nameLength, 0, 0);
    final flags = protocol.Element
        .makeFlags(isAbstract: false, isDeprecated: false, isPrivate: false);
    return new protocol.Element(kind, name, flags, location: location);
  }

  CompletionSuggestion _createPlainAttributeSuggestions(
          String completion, int defaultRelevance, protocol.Element element) =>
      new CompletionSuggestion(CompletionSuggestionKind.INVOCATION,
          defaultRelevance, completion, completion.length, 0, false, false,
          element: element);

  protocol.Element _createPlainAttributeElement(String name, int nameOffset,
      String locationSource, protocol.ElementKind kind) {
    final location =
        new Location(locationSource, nameOffset, name.length, 0, 0);
    final flags = protocol.Element
        .makeFlags(isAbstract: false, isDeprecated: false, isPrivate: false);
    return new protocol.Element(kind, name, flags, location: location);
  }

  CompletionSuggestion _createOutputSuggestion(OutputElement outputElement,
      int defaultRelevance, protocol.Element element) {
    final completion = '(${outputElement.name})';
    return new CompletionSuggestion(CompletionSuggestionKind.INVOCATION,
        defaultRelevance, completion, completion.length, 0, false, false,
        element: element, returnType: outputElement.eventType.toString());
  }

  protocol.Element _createOutputElement(
      OutputElement outputElement, protocol.ElementKind kind) {
    final name = '(${ outputElement.name})';
    final location = new Location(outputElement.source.fullName,
        outputElement.nameOffset, outputElement.nameLength, 0, 0);
    final flags = protocol.Element.makeFlags();
    return new protocol.Element(kind, name, flags,
        location: location, returnType: outputElement.eventType.toString());
  }

  CompletionSuggestion _createBananaSuggestion(InputElement inputElement,
      int defaultRelevance, protocol.Element element) {
    final completion = '[(${inputElement.name})]';
    return new CompletionSuggestion(CompletionSuggestionKind.INVOCATION,
        defaultRelevance, completion, completion.length, 0, false, false,
        element: element, returnType: inputElement.setterType.toString());
  }

  protocol.Element _createBananaElement(
      InputElement inputElement, protocol.ElementKind kind) {
    final name = '[(${inputElement.name})]';
    final location = new Location(inputElement.source.fullName,
        inputElement.nameOffset, inputElement.nameLength, 0, 0);
    final flags = protocol.Element.makeFlags();
    return new protocol.Element(kind, name, flags,
        location: location, returnType: inputElement.setterType.toString());
  }

  CompletionSuggestion _createStarAttrSuggestion(AttributeSelector selector,
      int defaultRelevance, protocol.Element element) {
    final completion = '*${selector.nameElement.name}';
    return new CompletionSuggestion(CompletionSuggestionKind.IDENTIFIER,
        defaultRelevance, completion, completion.length, 0, false, false,
        element: element);
  }

  protocol.Element _createStarAttrElement(
      AttributeSelector selector, protocol.ElementKind kind) {
    final name = '*${selector.nameElement.name}';
    final location = new Location(
        selector.nameElement.source.fullName,
        selector.nameElement.nameOffset,
        selector.nameElement.name.length,
        0,
        0);
    final flags = protocol.Element.makeFlags();
    return new protocol.Element(kind, name, flags, location: location);
  }
}
