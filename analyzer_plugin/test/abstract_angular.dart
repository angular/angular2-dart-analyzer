import 'package:analyzer/context/context_root.dart';
import 'package:analyzer/source/package_map_resolver.dart';
import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/src/generated/sdk.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:angular_analyzer_plugin/notification_manager.dart';
import 'package:angular_analyzer_plugin/src/model.dart';
import 'package:angular_analyzer_plugin/src/selector.dart';
import 'package:angular_analyzer_plugin/src/angular_driver.dart';
import 'package:typed_mock/typed_mock.dart';
import 'package:tuple/tuple.dart';
import 'package:unittest/unittest.dart';

import 'package:front_end/src/incremental/byte_store.dart';
import 'package:front_end/src/base/performace_logger.dart';
import 'package:analyzer/src/dart/analysis/driver.dart'
    show AnalysisDriver, AnalysisDriverScheduler;
import 'package:analyzer/src/dart/analysis/file_state.dart';
import 'package:analyzer/src/generated/engine.dart';

import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/src/dart/analysis/driver.dart';
import 'package:analyzer/src/generated/source_io.dart';

import 'mock_sdk.dart';

void assertComponentReference(
    ResolvedRange resolvedRange, Component component) {
  final ElementNameSelector selector = component.selector;
  final element = resolvedRange.element;
  expect(element, selector.nameElement);
  expect(resolvedRange.range.length, selector.nameElement.name.length);
}

PropertyAccessorElement assertGetter(ResolvedRange resolvedRange) {
  final PropertyAccessorElement element =
      (resolvedRange.element as DartElement).element;
  expect(element.isGetter, isTrue);
  return element;
}

void assertPropertyReference(
    ResolvedRange resolvedRange, AbstractDirective directive, String name) {
  final element = resolvedRange.element;
  for (final input in directive.inputs) {
    if (input.name == name) {
      expect(element, same(input));
      return;
    }
  }
  fail('Expected input "$name", but $element found.');
}

Component getComponentByClassName(
        List<AbstractDirective> directives, String className) =>
    getDirectiveByClassName(directives, className);

AbstractDirective getDirectiveByClassName(
        List<AbstractDirective> directives, String className) =>
    directives.firstWhere(
        (directive) => directive.classElement.name == className, orElse: () {
      fail('DirectiveMetadata with the class "$className" was not found.');
      return null;
    });

ResolvedRange getResolvedRangeAtString(
    String code, List<ResolvedRange> ranges, String str,
    [ResolvedRangeCondition condition]) {
  final offset = code.indexOf(str);
  return ranges.firstWhere((range) {
    if (range.range.offset == offset) {
      return condition == null || condition(range);
    }
    return false;
  }, orElse: () {
    fail('ResolvedRange at $offset was not found in [\n${ranges.join('\n')}]');
    return null;
  });
}

View getViewByClassName(List<View> views, String className) =>
    views.firstWhere((view) => view.classElement.name == className, orElse: () {
      fail('View with the class "$className" was not found.');
      return null;
    });

typedef bool ResolvedRangeCondition(ResolvedRange range);

class AbstractAngularTest {
  MemoryResourceProvider resourceProvider;

  DartSdk sdk;
  AngularDriver angularDriver;
  AnalysisDriver dartDriver;

  GatheringErrorListener errorListener;

  Source newSource(String path, [String content = '']) {
    final file = resourceProvider.newFile(path, content);
    final source = file.createSource();
    angularDriver.addFile(path);
    dartDriver.addFile(path);
    return source;
  }

  void setUp() {
    final logger = new PerformanceLog(new StringBuffer());
    final byteStore = new MemoryByteStore();

    final scheduler = new AnalysisDriverScheduler(logger)..start();
    resourceProvider = new MemoryResourceProvider();

    sdk = new MockSdk(resourceProvider: resourceProvider);
    final packageMap = <String, List<Folder>>{
      "angular2": [resourceProvider.getFolder("/angular2")]
    };
    final packageResolver =
        new PackageMapUriResolver(resourceProvider, packageMap);
    final sf = new SourceFactory([
      new DartUriResolver(sdk),
      packageResolver,
      new ResourceUriResolver(resourceProvider)
    ]);
    final testPath = resourceProvider.convertPath('/test');
    final contextRoot = new ContextRoot(testPath, []);

    dartDriver = new AnalysisDriver(
        scheduler,
        logger,
        resourceProvider,
        byteStore,
        new FileContentOverlay(),
        contextRoot,
        sf,
        new AnalysisOptionsImpl());
    angularDriver = new AngularDriver(new MockNotificationManager(), dartDriver,
        scheduler, byteStore, sf, new FileContentOverlay());

    errorListener = new GatheringErrorListener();
    _addAngularSources();
  }

  void fillErrorListener(List<AnalysisError> errors) {
    errorListener.addAll(errors);
  }

  void _addAngularSources() {
    newSource(
        '/angular2/angular2.dart',
        r'''
library angular2;

export 'src/core/async.dart';
export 'src/core/metadata.dart';
export 'src/core/ng_if.dart';
export 'src/core/ng_for.dart';
''');
    newSource(
        '/angular2/src/core/metadata.dart',
        r'''
import 'dart:async';

abstract class Directive {
  const Directive(
      {String selector,
      List<String> inputs,
      List<String> outputs,
      @Deprecated('Use `inputs` or `@Input` instead') List<String> properties,
      @Deprecated('Use `outputs` or `@Output` instead') List<String> events,
      Map<String, String> host,
      @Deprecated('Use `providers` instead') List bindings,
      List providers,
      String exportAs,
      String moduleId,
      Map<String, dynamic> queries})
      : super(
            selector: selector,
            inputs: inputs,
            outputs: outputs,
            properties: properties,
            events: events,
            host: host,
            bindings: bindings,
            providers: providers,
            exportAs: exportAs,
            moduleId: moduleId,
            queries: queries);
}

class Component extends Directive {
  const Component(
      {String selector,
      List<String> inputs,
      List<String> outputs,
      @Deprecated('Use `inputs` or `@Input` instead') List<String> properties,
      @Deprecated('Use `outputs` or `@Output` instead') List<String> events,
      Map<String, String> host,
      @Deprecated('Use `providers` instead') List bindings,
      List providers,
      String exportAs,
      String moduleId,
      Map<String, dynamic> queries,
      @Deprecated('Use `viewProviders` instead') List viewBindings,
      List viewProviders,
      ChangeDetectionStrategy changeDetection,
      String templateUrl,
      String template,
      dynamic directives,
      dynamic pipes,
      ViewEncapsulation encapsulation,
      List<String> styles,
      List<String> styleUrls});
}

class View {
  const View(
      {String templateUrl,
      String template,
      dynamic directives,
      dynamic pipes,
      ViewEncapsulation encapsulation,
      List<String> styles,
      List<String> styleUrls});
}

class Input {
  final String bindingPropertyName;
  const Input([this.bindingPropertyName]);
}

class Output {
  final String bindingPropertyName;
  const Output([this.bindingPropertyName]);
}

class Attribute {
  final String attributeName;
  const Attribute(this.attributeName);
}

class ContentChild extends Query {
  const ContentChild(dynamic /* Type | String */ selector,
              {dynamic read: null}) : super(selector);
}

class ContentChildren extends Query {
  const ContentChildren(dynamic /* Type | String */ selector,
              {dynamic read: null}) : super(selector);
}

class Query extends DependencyMetadata {
  final dynamic /* Type | String */ selector;
  const DependencyMetadata(this.selector) : super();
}

class DependencyMetadata {
  const DependencyMetadata();
}

class TemplateRef {}
class ElementRef {}
class QueryList<T> implements Iterable<T> {}
''');
    newSource(
        '/angular2/src/core/async.dart',
        r'''
import 'dart:async';

class EventEmitter<T> extends Stream<T> {
  StreamController<dynamic> _controller;

  /**
   * Creates an instance of [EventEmitter], which depending on [isAsync],
   * delivers events synchronously or asynchronously.
   */
  EventEmitter([bool isAsync = true]) {
    _controller = new StreamController.broadcast(sync: !isAsync);
  }

  StreamSubscription listen(void onData(dynamic line),
      {void onError(Error error), void onDone(), bool cancelOnError}) {
    return _controller.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  void add(value) {
    _controller.add(value);
  }

  void addError(error) {
    _controller.addError(error);
  }

  void close() {
    _controller.close();
  }
}
''');
    newSource(
        '/angular2/src/core/ng_if.dart',
        r'''
import 'metadata.dart';

@Directive(selector: "[ngIf]", inputs: const ["ngIf"])
class NgIf {
  NgIf(TemplateRef tpl);
  set ngIf(newCondition) {}
}
''');
    newSource(
        '/angular2/src/core/ng_for.dart',
        r'''
import 'metadata.dart';

@Directive(
    selector: "[ngFor][ngForOf]",
    inputs: const ["ngForOf", "ngForTemplate"])
class NgFor {
  NgFor(TemplateRef tpl);
  set ngForOf(dynamic value) {}
}
''');
  }

  /// Assert that the [errCode] is reported for [code], highlighting the [snippet].
  void assertErrorInCodeAtPosition(
      ErrorCode errCode, String code, String snippet) {
    final snippetIndex = code.indexOf(snippet);
    expect(snippetIndex, greaterThan(-1),
        reason: 'Error in test: snippet $snippet not part of code $code');
    errorListener.assertErrorsWithCodes(<ErrorCode>[errCode]);
    final error = errorListener.errors.single;
    expect(error.offset, snippetIndex);
    expect(errorListener.errors.single.length, snippet.length);
  }

  /// For [expectedErrors], it is a List of Tuple4 (1 per error):
  ///   code segment where offset begins,
  ///   length of error highlight,
  ///   errorCode,
  ///   and optional error args - pass empty list if not needed.
  void assertMultipleErrorsExplicit(
    Source source,
    String code,
    List<Tuple4<String, int, ErrorCode, List<Object>>> expectedErrors,
  ) {
    final realErrors = errorListener.errors;
    for (Tuple4 expectedError in expectedErrors) {
      final offset = code.indexOf(expectedError.item1);
      assert(offset != -1);
      final currentExpectedError = new AnalysisError(
        source,
        offset,
        expectedError.item2,
        expectedError.item3,
        expectedError.item4,
      );
      expect(
        realErrors.contains(currentExpectedError),
        true,
        reason: 'Expected error code ${expectedError.item3} never occurs at '
            'location $offset of length ${expectedError.item2}.',
      );
      expect(realErrors.length, expectedErrors.length,
          reason: 'Expected error counts do not  match.');
    }
  }
}

/// Instances of the class [GatheringErrorListener] implement an error listener
/// that collects all of the errors passed to it for later examination.
class GatheringErrorListener implements AnalysisErrorListener {
  /// A list containing the errors that were collected.
  final errors = <AnalysisError>[];

  /// Add all of the given errors to this listener.
  void addAll(List<AnalysisError> errors) {
    for (final error in errors) {
      onError(error);
    }
  }

  /// Assert that the number of errors that have been gathered matches the number
  /// of errors that are given and that they have the expected error codes. The
  /// order in which the errors were gathered is ignored.
  void assertErrorsWithCodes(
      [List<ErrorCode> expectedErrorCodes = const <ErrorCode>[]]) {
    final buffer = new StringBuffer();
    //
    // Verify that the expected error codes have a non-empty message.
    //
    for (final errorCode in expectedErrorCodes) {
      expect(errorCode.message.isEmpty, isFalse,
          reason: "Empty error code message");
    }
    //
    // Compute the expected number of each type of error.
    //
    final expectedCounts = <ErrorCode, int>{};
    for (final code in expectedErrorCodes) {
      var count = expectedCounts[code];
      if (count == null) {
        count = 1;
      } else {
        count = count + 1;
      }
      expectedCounts[code] = count;
    }
    //
    // Compute the actual number of each type of error.
    //
    final errorsByCode = <ErrorCode, List<AnalysisError>>{};
    for (final error in errors) {
      final code = error.errorCode;
      var list = errorsByCode[code];
      if (list == null) {
        list = <AnalysisError>[];
        errorsByCode[code] = list;
      }
      list.add(error);
    }
    //
    // Compare the expected and actual number of each type of error.
    //
    expectedCounts.forEach((code, expectedCount) {
      int actualCount;
      final list = errorsByCode.remove(code);
      if (list == null) {
        actualCount = 0;
      } else {
        actualCount = list.length;
      }
      if (actualCount != expectedCount) {
        if (buffer.length == 0) {
          buffer.write("Expected ");
        } else {
          buffer.write("; ");
        }
        buffer
          ..write(expectedCount)
          ..write(" errors of type ")
          ..write(code.uniqueName)
          ..write(", found ")
          ..write(actualCount);
      }
    });
    //
    // Check that there are no more errors in the actual-errors map,
    // otherwise record message.
    //
    errorsByCode.forEach((code, actualErrors) {
      final actualCount = actualErrors.length;
      if (buffer.isEmpty) {
        buffer.write("Expected ");
      } else {
        buffer.write("; ");
      }
      buffer
        ..write("0 errors of type ")
        ..write(code.uniqueName)
        ..write(", found ")
        ..write(actualCount)
        ..write(" (");
      for (var i = 0; i < actualErrors.length; i++) {
        final error = actualErrors[i];
        if (i > 0) {
          buffer.write(", ");
        }
        buffer.write(error.offset);
      }
      buffer.write(")");
    });
    if (buffer.length > 0) {
      fail(buffer.toString());
    }
  }

  /// Assert that no errors have been gathered.
  void assertNoErrors() {
    assertErrorsWithCodes();
  }

  @override
  void onError(AnalysisError error) {
    errors.add(error);
  }
}

class MockNotificationManager extends TypedMock implements NotificationManager {
}
