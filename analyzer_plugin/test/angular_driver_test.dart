library angular2.src.analysis.analyzer_plugin.src.tasks_test;

import 'dart:async';

import 'package:angular_analyzer_plugin/src/standard_components.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:angular_ast/angular_ast.dart';
import 'package:angular_analyzer_plugin/src/from_file_prefixed_error.dart';
import 'package:angular_analyzer_plugin/src/model.dart';
import 'package:angular_analyzer_plugin/src/selector.dart';
import 'package:angular_analyzer_plugin/tasks.dart';
import 'package:angular_analyzer_plugin/ast.dart';
import 'package:angular_analyzer_plugin/src/view_extraction.dart';
import 'package:angular_analyzer_plugin/src/directive_linking.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:unittest/unittest.dart';

import 'abstract_angular.dart';

main() {
  groupSep = ' | ';
  defineReflectiveTests(AngularParseHtmlTest);
  defineReflectiveTests(BuildStandardHtmlComponentsTest);
  defineReflectiveTests(BuildUnitDirectivesTest);
  defineReflectiveTests(BuildUnitViewsTest);
  defineReflectiveTests(ResolveDartTemplatesTest);
  defineReflectiveTests(ResolveHtmlTemplatesTest);
  defineReflectiveTests(ResolveHtmlTemplateTest);
}

@reflectiveTest
class AngularParseHtmlTest extends AbstractAngularTest {
  test_perform() {
    String code = r'''
<!DOCTYPE html>
<html>
  <head>
    <title> test page </title>
  </head>
  <body>
    <h1 myAttr='my value'>Test</h1>
  </body>
</html>
    ''';
    final source = newSource('/test.html', code);
    final tplParser = new TemplateParser();

    tplParser.parse(code, source);
    expect(tplParser.parseErrors, isEmpty);
    // HTML_DOCUMENT
    {
      var asts = tplParser.document;
      expect(asts, isNotNull);
      // verify that attributes are not lower-cased
      ElementAst element = asts[1].childNodes[3].childNodes[1];
      expect(element.attributes.length, 1);
      expect(element.attributes[0].name, 'myAttr');
      expect(element.attributes[0].value, 'my value');
    }
  }

  test_perform_noDocType() {
    String code = r'''
<div>AAA</div>
<span>BBB</span>
''';
    final source = newSource('/test.html', code);
    final tplParser = new TemplateParser();

    tplParser.parse(code, source);
    // validate Document
    {
      List<StandaloneTemplateAst> asts = tplParser.document;
      expect(asts, isNotNull);
      expect(asts.length, 4);
      expect((asts[0] as ElementAst).name, 'div');
      expect((asts[2] as ElementAst).name, 'span');
    }
    // it's OK to don't have DOCTYPE
    expect(tplParser.parseErrors, isEmpty);
  }

  test_perform_noDocType_with_dangling_unclosed_tag() {
    String code = r'''
<div>AAA</div>
<span>BBB</span>
<di''';
    final source = newSource('/test.html', code);
    final tplParser = new TemplateParser();

    tplParser.parse(code, source);
    // quick validate Document
    {
      List<StandaloneTemplateAst> asts = tplParser.document;
      expect(asts, isNotNull);
      expect(asts.length, 5);
      expect((asts[0] as ElementAst).name, 'div');
      expect((asts[2] as ElementAst).name, 'span');
      expect((asts[4] as ElementAst).name, 'di');
    }
  }
}

@reflectiveTest
class BuildStandardHtmlComponentsTest extends AbstractAngularTest {
  Future test_perform() async {
    StandardHtml stdhtml = await angularDriver.getStandardHtml();
    // validate
    Map<String, Component> map = stdhtml.components;
    expect(map, isNotNull);
    // a
    {
      Component component = map['a'];
      expect(component, isNotNull);
      expect(component.classElement.displayName, 'AnchorElement');
      expect(component.selector.toString(), 'a');
      List<InputElement> inputs = component.inputs;
      List<OutputElement> outputElements = component.outputs;
      {
        InputElement input = inputs.singleWhere((i) => i.name == 'href');
        expect(input, isNotNull);
        expect(input.setter, isNotNull);
        expect(input.setterType.toString(), equals("String"));
      }
      expect(outputElements, hasLength(0));
      expect(inputs.where((i) => i.name == '_privateField'), hasLength(0));
    }
    // button
    {
      Component component = map['button'];
      expect(component, isNotNull);
      expect(component.classElement.displayName, 'ButtonElement');
      expect(component.selector.toString(), 'button');
      List<InputElement> inputs = component.inputs;
      List<OutputElement> outputElements = component.outputs;
      {
        InputElement input = inputs.singleWhere((i) => i.name == 'autofocus');
        expect(input, isNotNull);
        expect(input.setter, isNotNull);
        expect(input.setterType.toString(), equals("bool"));
      }
      expect(outputElements, hasLength(0));
    }
    // input
    {
      Component component = map['input'];
      expect(component, isNotNull);
      expect(component.classElement.displayName, 'InputElement');
      expect(component.selector.toString(), 'input');
      List<OutputElement> outputElements = component.outputs;
      expect(outputElements, hasLength(0));
    }
    // body is one of the few elements with special events
    {
      Component component = map['body'];
      expect(component, isNotNull);
      expect(component.classElement.displayName, 'BodyElement');
      expect(component.selector.toString(), 'body');
      List<OutputElement> outputElements = component.outputs;
      expect(outputElements, hasLength(1));
      {
        OutputElement output = outputElements[0];
        expect(output.name, equals("unload"));
        expect(output.getter, isNotNull);
        expect(output.eventType, isNotNull);
      }
    }
    // h1, h2, h3
    expect(map['h1'], isNotNull);
    expect(map['h2'], isNotNull);
    expect(map['h3'], isNotNull);
    // has no mention of 'option' in the source, is hardcoded
    expect(map['option'], isNotNull);
  }

  test_buildStandardHtmlEvents() async {
    StandardHtml stdhtml = await angularDriver.getStandardHtml();
    Map<String, OutputElement> outputElements = stdhtml.events;
    {
      // This one is important because it proves we're using @DomAttribute
      // to generate the output name and not the method in the sdk.
      OutputElement outputElement = outputElements['keyup'];
      expect(outputElement, isNotNull);
      expect(outputElement.getter, isNotNull);
      expect(outputElement.eventType, isNotNull);
    }
    {
      OutputElement outputElement = outputElements['cut'];
      expect(outputElement, isNotNull);
      expect(outputElement.getter, isNotNull);
      expect(outputElement.eventType, isNotNull);
    }
    {
      OutputElement outputElement = outputElements['click'];
      expect(outputElement, isNotNull);
      expect(outputElement.getter, isNotNull);
      expect(outputElement.eventType, isNotNull);
      expect(outputElement.eventType.toString(), equals('MouseEvent'));
    }
    {
      OutputElement outputElement = outputElements['change'];
      expect(outputElement, isNotNull);
      expect(outputElement.getter, isNotNull);
      expect(outputElement.eventType, isNotNull);
    }
    {
      // used to happen from "id" which got truncated by 'on'.length
      OutputElement outputElement = outputElements[''];
      expect(outputElement, isNull);
    }
    {
      // used to happen from "hidden" which got truncated by 'on'.length
      OutputElement outputElement = outputElements['dden'];
      expect(outputElement, isNull);
    }
  }

  test_buildStandardHtmlAttributes() async {
    StandardHtml stdhtml = await angularDriver.getStandardHtml();
    Map<String, InputElement> inputElements = stdhtml.attributes;
    {
      InputElement input = inputElements['tabIndex'];
      expect(input, isNotNull);
      expect(input.setter, isNotNull);
      expect(input.setterType.toString(), equals("int"));
    }
    {
      InputElement input = inputElements['hidden'];
      expect(input, isNotNull);
      expect(input.setter, isNotNull);
      expect(input.setterType.toString(), equals("bool"));
    }
  }
}

@reflectiveTest
class BuildUnitDirectivesTest extends AbstractAngularTest {
  List<AbstractDirective> directives;
  List<AnalysisError> errors;

  Future getDirectives(Source source) async {
    final dartResult = await dartDriver.getResult(source.fullName);
    fillErrorListener(dartResult.errors);
    final result = await angularDriver.getDirectives(source.fullName);
    directives = result.directives;
    errors = result.errors;
    fillErrorListener(errors);
  }

  Future test_Component() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Component(selector: 'comp-a', template:'')
class ComponentA {
}

@Component(selector: 'comp-b', template:'')
class ComponentB {
}
''');
    await getDirectives(source);
    expect(directives, hasLength(2));
    {
      Component component = directives[0];
      expect(component, new isInstanceOf<Component>());
      {
        Selector selector = component.selector;
        expect(selector, new isInstanceOf<ElementNameSelector>());
        expect(selector.toString(), 'comp-a');
      }
      {
        expect(component.elementTags, hasLength(1));
        Selector selector = component.elementTags[0];
        expect(selector, new isInstanceOf<ElementNameSelector>());
        expect(selector.toString(), 'comp-a');
      }
    }
    {
      Component component = directives[1];
      expect(component, new isInstanceOf<Component>());
      {
        Selector selector = component.selector;
        expect(selector, new isInstanceOf<ElementNameSelector>());
        expect(selector.toString(), 'comp-b');
      }
      {
        expect(component.elementTags, hasLength(1));
        Selector selector = component.elementTags[0];
        expect(selector, new isInstanceOf<ElementNameSelector>());
        expect(selector.toString(), 'comp-b');
      }
    }
  }

  Future test_Directive() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Directive(selector: 'dir-a')
class DirectiveA {
}

@Directive(selector: 'dir-b')
class DirectiveB {
}
''');
    await getDirectives(source);
    expect(directives, hasLength(2));
    {
      AbstractDirective directive = directives[0];
      expect(directive, new isInstanceOf<Directive>());
      {
        Selector selector = directive.selector;
        expect(selector, new isInstanceOf<ElementNameSelector>());
        expect(selector.toString(), 'dir-a');
      }
      {
        expect(directive.elementTags, hasLength(1));
        Selector selector = directive.elementTags[0];
        expect(selector, new isInstanceOf<ElementNameSelector>());
        expect(selector.toString(), 'dir-a');
      }
    }
    {
      AbstractDirective directive = directives[1];
      expect(directive, new isInstanceOf<Directive>());
      {
        Selector selector = directive.selector;
        expect(selector, new isInstanceOf<ElementNameSelector>());
        expect(selector.toString(), 'dir-b');
      }
      {
        expect(directive.elementTags, hasLength(1));
        Selector selector = directive.elementTags[0];
        expect(selector, new isInstanceOf<ElementNameSelector>());
        expect(selector.toString(), 'dir-b');
      }
    }
  }

  Future test_Directive_elementTags_OrSelector() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Directive(selector: 'dir-a1, dir-a2, dir-a3')
class DirectiveA {
}

@Directive(selector: 'dir-b1, dir-b2')
class DirectiveB {
}
''');
    await getDirectives(source);
    expect(directives, hasLength(2));
    {
      Directive directive = directives[0];
      expect(directive, new isInstanceOf<Directive>());
      {
        Selector selector = directive.selector;
        expect(selector, new isInstanceOf<OrSelector>());
        expect((selector as OrSelector).selectors, hasLength(3));
      }
      {
        expect(directive.elementTags, hasLength(3));
        expect(
            directive.elementTags[0], new isInstanceOf<ElementNameSelector>());
        expect(directive.elementTags[0].toString(), 'dir-a1');
        expect(
            directive.elementTags[1], new isInstanceOf<ElementNameSelector>());
        expect(directive.elementTags[1].toString(), 'dir-a2');
        expect(
            directive.elementTags[2], new isInstanceOf<ElementNameSelector>());
        expect(directive.elementTags[2].toString(), 'dir-a3');
      }
    }
    {
      Directive directive = directives[1];
      expect(directive, new isInstanceOf<Directive>());
      {
        Selector selector = directive.selector;
        expect(selector, new isInstanceOf<OrSelector>());
        expect((selector as OrSelector).selectors, hasLength(2));
      }
      {
        expect(directive.elementTags, hasLength(2));
        expect(
            directive.elementTags[0], new isInstanceOf<ElementNameSelector>());
        expect(directive.elementTags[0].toString(), 'dir-b1');
        expect(
            directive.elementTags[1], new isInstanceOf<ElementNameSelector>());
        expect(directive.elementTags[1].toString(), 'dir-b2');
      }
    }
  }

  Future test_Directive_elementTags_AndSelector() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Directive(selector: 'dir-a.myClass[myAttr]')
class DirectiveA {
}

@Directive(selector: 'dir-b[myAttr]')
class DirectiveB {
}
''');
    await getDirectives(source);
    expect(directives, hasLength(2));
    {
      Directive directive = directives[0];
      expect(directive, new isInstanceOf<Directive>());
      {
        Selector selector = directive.selector;
        expect(selector, new isInstanceOf<AndSelector>());
        expect((selector as AndSelector).selectors, hasLength(3));
      }
      {
        expect(directive.elementTags, hasLength(1));
        expect(
            directive.elementTags[0], new isInstanceOf<ElementNameSelector>());
        expect(directive.elementTags[0].toString(), 'dir-a');
      }
    }
    {
      Directive directive = directives[1];
      expect(directive, new isInstanceOf<Directive>());
      {
        Selector selector = directive.selector;
        expect(selector, new isInstanceOf<AndSelector>());
        expect((selector as AndSelector).selectors, hasLength(2));
      }
      {
        expect(directive.elementTags, hasLength(1));
        expect(
            directive.elementTags[0], new isInstanceOf<ElementNameSelector>());
        expect(directive.elementTags[0].toString(), 'dir-b');
      }
    }
  }

  Future test_Directive_elementTags_CompoundSelector() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Directive(selector: 'dir-a1.myClass[myAttr], dir-a2.otherClass')
class DirectiveA {
}

@Directive(selector: 'dir-b1[myAttr], dir-b2')
class DirectiveB {
}
''');
    await getDirectives(source);
    expect(directives, hasLength(2));
    {
      Directive directive = directives[0];
      expect(directive, new isInstanceOf<Directive>());
      {
        Selector selector = directive.selector;
        expect(selector, new isInstanceOf<OrSelector>());
        expect((selector as OrSelector).selectors, hasLength(2));
      }
      {
        expect(directive.elementTags, hasLength(2));
        expect(
            directive.elementTags[0], new isInstanceOf<ElementNameSelector>());
        expect(directive.elementTags[0].toString(), 'dir-a1');
        expect(
            directive.elementTags[1], new isInstanceOf<ElementNameSelector>());
        expect(directive.elementTags[1].toString(), 'dir-a2');
      }
    }
    {
      Directive directive = directives[1];
      expect(directive, new isInstanceOf<Directive>());
      {
        Selector selector = directive.selector;
        expect(selector, new isInstanceOf<OrSelector>());
        expect((selector as OrSelector).selectors, hasLength(2));
      }
      {
        expect(directive.elementTags, hasLength(2));
        expect(
            directive.elementTags[0], new isInstanceOf<ElementNameSelector>());
        expect(directive.elementTags[0].toString(), 'dir-b1');
        expect(
            directive.elementTags[1], new isInstanceOf<ElementNameSelector>());
        expect(directive.elementTags[1].toString(), 'dir-b2');
      }
    }
  }

  Future test_exportAs_Component() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'aaa', exportAs: 'export-name', template:'')
class ComponentA {
}

@Component(selector: 'bbb', template:'')
class ComponentB {
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    expect(directives, hasLength(2));
    {
      Component component = getComponentByClassName(directives, 'ComponentA');
      {
        AngularElement exportAs = component.exportAs;
        expect(exportAs.name, 'export-name');
        expect(exportAs.nameOffset, code.indexOf('export-name'));
      }
    }
    {
      Component component = getComponentByClassName(directives, 'ComponentB');
      {
        AngularElement exportAs = component.exportAs;
        expect(exportAs, isNull);
      }
    }
    // no errors
    errorListener.assertNoErrors();
  }

  Future test_exportAs_Directive() async {
    String code = r'''
import '/angular2/angular2.dart';

@Directive(selector: '[aaa]', exportAs: 'export-name')
class DirectiveA {
}

@Directive(selector: '[bbb]')
class DirectiveB {
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    expect(directives, hasLength(2));
    {
      Directive directive = getDirectiveByClassName(directives, 'DirectiveA');
      {
        AngularElement exportAs = directive.exportAs;
        expect(exportAs.name, 'export-name');
        expect(exportAs.nameOffset, code.indexOf('export-name'));
      }
    }
    {
      Directive directive = getDirectiveByClassName(directives, 'DirectiveB');
      {
        AngularElement exportAs = directive.exportAs;
        expect(exportAs, isNull);
      }
    }
    // no errors
    errorListener.assertNoErrors();
  }

  Future test_exportAs_hasError_notStringValue() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Component(selector: 'aaa', exportAs: 42, template:'')
class ComponentA {
}
''');
    await getDirectives(source);
    expect(directives, hasLength(1));
    // has an error
    errorListener.assertErrorsWithCodes(<ErrorCode>[
      AngularWarningCode.STRING_VALUE_EXPECTED,
      StaticWarningCode.ARGUMENT_TYPE_NOT_ASSIGNABLE
    ]);
  }

  Future test_exportAs_constantStringExpressionOk() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Component(selector: 'aaa', exportAs: 'a' + 'b', template:'')
class ComponentA {
}
''');
    await getDirectives(source);
    expect(directives, hasLength(1));
    // has no errors
    errorListener.assertNoErrors();
  }

  Future test_hasError_ArgumentSelectorMissing() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Component(template:'')
class ComponentA {
}
''');
    await getDirectives(source);
    // validate
    errorListener.assertErrorsWithCodes(
        <ErrorCode>[AngularWarningCode.ARGUMENT_SELECTOR_MISSING]);
  }

  Future test_hasError_CannotParseSelector() async {
    String code = r'''
import '/angular2/angular2.dart';
@Component(selector: 'a+bad selector', template: '')
class ComponentA {
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    // validate
    assertErrorInCodeAtPosition(
        AngularWarningCode.CANNOT_PARSE_SELECTOR, code, "+");
  }

  Future test_hasError_selector_notStringValue() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Component(selector: 55, template: '')
class ComponentA {
}
''');
    await getDirectives(source);
    // validate
    errorListener.assertErrorsWithCodes(<ErrorCode>[
      AngularWarningCode.STRING_VALUE_EXPECTED,
      StaticWarningCode.ARGUMENT_TYPE_NOT_ASSIGNABLE
    ]);
  }

  Future test_selector_constantExpressionOk() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Component(selector: 'a' + '[b]', template: '')
class ComponentA {
}
''');
    await getDirectives(source);
    // validate
    errorListener.assertNoErrors();
  }

  Future test_hasError_UndefinedSetter_fullSyntax() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-component', inputs: const ['noSetter: no-setter'], template: '')
class ComponentA {
}
''');
    await getDirectives(source);
    Component component = directives.single;
    List<InputElement> inputs = component.inputs;
    // the bad input should NOT show up, it is not usable see github #183
    expect(inputs, hasLength(0));
    // validate
    errorListener.assertErrorsWithCodes(
        <ErrorCode>[StaticTypeWarningCode.UNDEFINED_SETTER]);
  }

  Future test_hasError_UndefinedSetter_shortSyntax() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-component', inputs: const ['noSetter'], template: '')
class ComponentA {
}
''');
    await getDirectives(source);
    // validate
    errorListener.assertErrorsWithCodes(
        <ErrorCode>[StaticTypeWarningCode.UNDEFINED_SETTER]);
  }

  Future test_hasError_UndefinedSetter_shortSyntax_noInputMade() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-component', inputs: const ['noSetter'], template: '')
class ComponentA {
}
''');
    await getDirectives(source);
    Component component = directives.single;
    List<InputElement> inputs = component.inputs;
    // the bad input should NOT show up, it is not usable see github #183
    expect(inputs, hasLength(0));
    // validate
    errorListener.assertErrorsWithCodes(
        <ErrorCode>[StaticTypeWarningCode.UNDEFINED_SETTER]);
  }

  Future test_inputs() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(
    selector: 'my-component',
    template: '<p></p>',
    inputs: const ['leadingText', 'trailingText: tailText'])
class MyComponent {
  String leadingText;
  int trailingText;
  @Input()
  bool firstField;
  @Input('secondInput')
  String secondField;
  @Input()
  set someSetter(String x) { }
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    Component component = directives.single;
    List<InputElement> inputs = component.inputs;
    expect(inputs, hasLength(5));
    {
      InputElement input = inputs[0];
      expect(input.name, 'leadingText');
      expect(input.nameOffset, code.indexOf("leadingText',"));
      expect(input.setterRange.offset, input.nameOffset);
      expect(input.setterRange.length, 'leadingText'.length);
      expect(input.setter, isNotNull);
      expect(input.setter.isSetter, isTrue);
      expect(input.setter.displayName, 'leadingText');
      expect(input.setterType.toString(), equals("String"));
    }
    {
      InputElement input = inputs[1];
      expect(input.name, 'tailText');
      expect(input.nameOffset, code.indexOf("tailText']"));
      expect(input.setterRange.offset, code.indexOf("trailingText: "));
      expect(input.setterRange.length, 'trailingText'.length);
      expect(input.setter, isNotNull);
      expect(input.setter.isSetter, isTrue);
      expect(input.setter.displayName, 'trailingText');
      expect(input.setterType.toString(), equals("int"));
    }
    {
      InputElement input = inputs[2];
      expect(input.name, 'firstField');
      expect(input.nameOffset, code.indexOf('firstField'));
      expect(input.nameLength, 'firstField'.length);
      expect(input.setterRange.offset, input.nameOffset);
      expect(input.setterRange.length, input.name.length);
      expect(input.setter, isNotNull);
      expect(input.setter.isSetter, isTrue);
      expect(input.setter.displayName, 'firstField');
      expect(input.setterType.toString(), equals("bool"));
    }
    {
      InputElement input = inputs[3];
      expect(input.name, 'secondInput');
      expect(input.nameOffset, code.indexOf('secondInput'));
      expect(input.setterRange.offset, code.indexOf('secondField'));
      expect(input.setterRange.length, 'secondField'.length);
      expect(input.setter, isNotNull);
      expect(input.setter.isSetter, isTrue);
      expect(input.setter.displayName, 'secondField');
      expect(input.setterType.toString(), equals("String"));
    }
    {
      InputElement input = inputs[4];
      expect(input.name, 'someSetter');
      expect(input.nameOffset, code.indexOf('someSetter'));
      expect(input.setterRange.offset, input.nameOffset);
      expect(input.setterRange.length, input.name.length);
      expect(input.setter, isNotNull);
      expect(input.setter.isSetter, isTrue);
      expect(input.setter.displayName, 'someSetter');
      expect(input.setterType.toString(), equals("String"));
    }

    // assert no syntax errors, etc
    errorListener.assertNoErrors();
  }

  Future test_inputs_deprecatedProperties() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(
    selector: 'my-component',
    template: '<p></p>',
    properties: const ['leadingText', 'trailingText: tailText'])
class MyComponent {
  String leadingText;
  String trailingText;
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    Component component = directives.single;
    List<InputElement> inputs = component.inputs;
    expect(inputs, hasLength(2));
    {
      InputElement input = inputs[0];
      expect(input.name, 'leadingText');
      expect(input.nameOffset, code.indexOf("leadingText',"));
      expect(input.setterRange.offset, input.nameOffset);
      expect(input.setterRange.length, 'leadingText'.length);
      expect(input.setter, isNotNull);
      expect(input.setter.isSetter, isTrue);
      expect(input.setter.displayName, 'leadingText');
    }
    {
      InputElement input = inputs[1];
      expect(input.name, 'tailText');
      expect(input.nameOffset, code.indexOf("tailText']"));
      expect(input.setterRange.offset, code.indexOf("trailingText: "));
      expect(input.setterRange.length, 'trailingText'.length);
      expect(input.setter, isNotNull);
      expect(input.setter.isSetter, isTrue);
      expect(input.setter.displayName, 'trailingText');
    }
  }

  Future test_outputs() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(
    selector: 'my-component',
    template: '<p></p>',
    outputs: const ['outputOne', 'secondOutput: outputTwo'])
class MyComponent {
  EventEmitter<MyComponent> outputOne;
  EventEmitter<String> secondOutput;
  @Output()
  EventEmitter<int> outputThree;
  @Output('outputFour')
  EventEmitter fourthOutput;
  @Output()
  EventEmitter get someGetter => null;
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    Component component = directives.single;
    List<OutputElement> compOutputs = component.outputs;
    expect(compOutputs, hasLength(5));
    {
      OutputElement output = compOutputs[0];
      expect(output.name, 'outputOne');
      expect(output.nameOffset, code.indexOf("outputOne"));
      expect(output.getterRange.offset, output.nameOffset);
      expect(output.getterRange.length, 'outputOne'.length);
      expect(output.getter, isNotNull);
      expect(output.getter.isGetter, isTrue);
      expect(output.getter.displayName, 'outputOne');
      expect(output.eventType, isNotNull);
      expect(output.eventType.toString(), equals("MyComponent"));
    }
    {
      OutputElement output = compOutputs[1];
      expect(output.name, 'outputTwo');
      expect(output.nameOffset, code.indexOf("outputTwo']"));
      expect(output.getterRange.offset, code.indexOf("secondOutput: "));
      expect(output.getterRange.length, 'secondOutput'.length);
      expect(output.getter, isNotNull);
      expect(output.getter.isGetter, isTrue);
      expect(output.getter.displayName, 'secondOutput');
      expect(output.eventType, isNotNull);
      expect(output.eventType.toString(), equals("String"));
    }
    {
      OutputElement output = compOutputs[2];
      expect(output.name, 'outputThree');
      expect(output.nameOffset, code.indexOf('outputThree'));
      expect(output.nameLength, 'outputThree'.length);
      expect(output.getterRange.offset, output.nameOffset);
      expect(output.getterRange.length, output.nameLength);
      expect(output.getter, isNotNull);
      expect(output.getter.isGetter, isTrue);
      expect(output.getter.displayName, 'outputThree');
      expect(output.eventType, isNotNull);
      expect(output.eventType.toString(), equals("int"));
    }
    {
      OutputElement output = compOutputs[3];
      expect(output.name, 'outputFour');
      expect(output.nameOffset, code.indexOf('outputFour'));
      expect(output.getterRange.offset, code.indexOf('fourthOutput'));
      expect(output.getterRange.length, 'fourthOutput'.length);
      expect(output.getter, isNotNull);
      expect(output.getter.isGetter, isTrue);
      expect(output.getter.displayName, 'fourthOutput');
      expect(output.eventType, isNotNull);
      expect(output.eventType.isDynamic, isTrue);
    }
    {
      OutputElement output = compOutputs[4];
      expect(output.name, 'someGetter');
      expect(output.nameOffset, code.indexOf('someGetter'));
      expect(output.getterRange.offset, output.nameOffset);
      expect(output.getterRange.length, output.name.length);
      expect(output.getter, isNotNull);
      expect(output.getter.isGetter, isTrue);
      expect(output.getter.displayName, 'someGetter');
      expect(output.eventType, isNotNull);
      expect(output.eventType.isDynamic, isTrue);
    }

    // assert no syntax errors, etc
    errorListener.assertNoErrors();
  }

  Future test_outputs_streamIsOk() async {
    String code = r'''
import '/angular2/angular2.dart';
import 'dart:async';

@Component(
    selector: 'my-component',
    template: '<p></p>')
class MyComponent {
  @Output()
  Stream<int> myOutput;
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    Component component = directives.single;
    List<OutputElement> compOutputs = component.outputs;
    expect(compOutputs, hasLength(1));
    {
      OutputElement output = compOutputs[0];
      expect(output.eventType, isNotNull);
      expect(output.eventType.toString(), equals("int"));
    }
  }

  Future test_outputs_extendStreamIsOk() async {
    String code = r'''
import '/angular2/angular2.dart';
import 'dart:async';

abstract class MyStream<T> implements Stream<T> { }

@Component(
    selector: 'my-component',
    template: '<p></p>')
class MyComponent {
  @Output()
  MyStream<int> myOutput;
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    Component component = directives.single;
    List<OutputElement> compOutputs = component.outputs;
    expect(compOutputs, hasLength(1));
    {
      OutputElement output = compOutputs[0];
      expect(output.eventType, isNotNull);
      expect(output.eventType.toString(), equals("int"));
    }
  }

  Future test_outputs_extendStreamSpecializedIsOk() async {
    String code = r'''
import '/angular2/angular2.dart';
import 'dart:async';

class MyStream extends Stream<int> { }

@Component(
    selector: 'my-component',
    template: '<p></p>')
class MyComponent {
  @Output()
  MyStream myOutput;
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    Component component = directives.single;
    List<OutputElement> compOutputs = component.outputs;
    expect(compOutputs, hasLength(1));
    {
      OutputElement output = compOutputs[0];
      expect(output.eventType, isNotNull);
      expect(output.eventType.toString(), equals("int"));
    }
  }

  Future test_outputs_extendStreamUntypedIsOk() async {
    String code = r'''
import '/angular2/angular2.dart';
import 'dart:async';

class MyStream extends Stream { }

@Component(
    selector: 'my-component',
    template: '<p></p>')
class MyComponent {
  @Output()
  MyStream myOutput;
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    Component component = directives.single;
    List<OutputElement> compOutputs = component.outputs;
    expect(compOutputs, hasLength(1));
    {
      OutputElement output = compOutputs[0];
      expect(output.eventType, isNotNull);
      expect(output.eventType.toString(), equals("dynamic"));
    }
  }

  Future test_outputs_notEventEmitterTypeError() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(
    selector: 'my-component',
    template: '<p></p>')
class MyComponent {
  @Output()
  int badOutput;
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    assertErrorInCodeAtPosition(
        AngularWarningCode.OUTPUT_MUST_BE_EVENTEMITTER, code, "badOutput");
  }

  Future test_outputs_extendStreamNotStreamHasDynamicEventType() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(
    selector: 'my-component',
    template: '<p></p>')
class MyComponent {
  @Output()
  int badOutput;
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    // validate
    Component component = directives.single;
    List<OutputElement> compOutputs = component.outputs;
    expect(compOutputs, hasLength(1));
    {
      OutputElement output = compOutputs[0];
      expect(output.eventType, isNotNull);
      expect(output.eventType.toString(), equals("dynamic"));
    }
  }

  Future test_parameterizedInputsOutputs() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(
    selector: 'my-component',
    template: '<p></p>')
class MyComponent<T, A extends String, B extends A> {
  @Output() EventEmitter<T> dynamicOutput;
  @Input() T dynamicInput;
  @Output() EventEmitter<A> stringOutput;
  @Input() A stringInput;
  @Output() EventEmitter<B> stringOutput2;
  @Input() B stringInput2;
  @Output() EventEmitter<List<B>> listOutput;
  @Input() List<B> listInput;
}

''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    // validate
    Component component = directives.single;
    List<InputElement> compInputs = component.inputs;
    expect(compInputs, hasLength(4));
    {
      InputElement input = compInputs[0];
      expect(input.name, 'dynamicInput');
      expect(input.setterType, isNotNull);
      expect(input.setterType.toString(), equals("dynamic"));
    }
    {
      InputElement input = compInputs[1];
      expect(input.name, 'stringInput');
      expect(input.setterType, isNotNull);
      expect(input.setterType.toString(), equals("String"));
    }
    {
      InputElement input = compInputs[2];
      expect(input.name, 'stringInput2');
      expect(input.setterType, isNotNull);
      expect(input.setterType.toString(), equals("String"));
    }
    {
      InputElement input = compInputs[3];
      expect(input.name, 'listInput');
      expect(input.setterType, isNotNull);
      expect(input.setterType.toString(), equals("List<String>"));
    }

    List<OutputElement> compOutputs = component.outputs;
    expect(compOutputs, hasLength(4));
    {
      OutputElement output = compOutputs[0];
      expect(output.name, 'dynamicOutput');
      expect(output.eventType, isNotNull);
      expect(output.eventType.toString(), equals("dynamic"));
    }
    {
      OutputElement output = compOutputs[1];
      expect(output.name, 'stringOutput');
      expect(output.eventType, isNotNull);
      expect(output.eventType.toString(), equals("String"));
    }
    {
      OutputElement output = compOutputs[2];
      expect(output.name, 'stringOutput2');
      expect(output.eventType, isNotNull);
      expect(output.eventType.toString(), equals("String"));
    }
    {
      OutputElement output = compOutputs[3];
      expect(output.name, 'listOutput');
      expect(output.eventType, isNotNull);
      expect(output.eventType.toString(), equals("List<String>"));
    }

    // assert no syntax errors, etc
    errorListener.assertNoErrors();
  }

  Future test_parameterizedInheritedInputsOutputs() async {
    String code = r'''
import '/angular2/angular2.dart';

class Generic<T> {
  T input;
  EventEmitter<T> output;
}

@Component(
    selector: 'my-component',
    template: '<p></p>',
    inputs: const ['input'],
    outputs: const ['output'])
class MyComponent extends Generic {
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    Component component = directives.single;
    List<InputElement> compInputs = component.inputs;
    expect(compInputs, hasLength(1));
    {
      InputElement input = compInputs[0];
      expect(input.name, 'input');
      expect(input.setterType, isNotNull);
      expect(input.setterType.toString(), equals("dynamic"));
    }

    List<OutputElement> compOutputs = component.outputs;
    expect(compOutputs, hasLength(1));
    {
      OutputElement output = compOutputs[0];
      expect(output.name, 'output');
      expect(output.eventType, isNotNull);
      expect(output.eventType.toString(), equals("dynamic"));
    }
  }

  Future test_parameterizedInheritedInputsOutputsSpecified() async {
    String code = r'''
import '/angular2/angular2.dart';

class Generic<T> {
  T input;
  EventEmitter<T> output;
}

@Component(
    selector: 'my-component',
    template: '<p></p>',
    inputs: const ['input'],
    outputs: const ['output'])
class MyComponent extends Generic<String> {
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    Component component = directives.single;
    List<InputElement> compInputs = component.inputs;
    expect(compInputs, hasLength(1));
    {
      InputElement input = compInputs[0];
      expect(input.name, 'input');
      expect(input.setterType, isNotNull);
      expect(input.setterType.toString(), equals("String"));
    }

    List<OutputElement> compOutputs = component.outputs;
    expect(compOutputs, hasLength(1));
    {
      OutputElement output = compOutputs[0];
      expect(output.name, 'output');
      expect(output.eventType, isNotNull);
      expect(output.eventType.toString(), equals("String"));
    }
  }

  Future test_finalPropertyInputError() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-component', template: '<p></p>')
class MyComponent {
  @Input() final int immutable = 1;
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    // validate
    assertErrorInCodeAtPosition(
        AngularWarningCode.INPUT_ANNOTATION_PLACEMENT_INVALID,
        code,
        "@Input()");
  }

  Future test_finalPropertyInputStringError() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-component', template: '<p></p>', inputs: const ['immutable'])
class MyComponent {
  final int immutable = 1;
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    // validate. Can't easily assert position though because its all 'immutable'
    errorListener
        .assertErrorsWithCodes([StaticTypeWarningCode.UNDEFINED_SETTER]);
  }

  Future test_noDirectives() async {
    Source source = newSource(
        '/test.dart',
        r'''
class A {}
class B {}
''');
    await getDirectives(source);
    expect(directives, isEmpty);
  }

  Future test_inputOnGetterIsError() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-component', template: '')
class MyComponent {
  @Input()
  String get someGetter => null;
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    assertErrorInCodeAtPosition(
        AngularWarningCode.INPUT_ANNOTATION_PLACEMENT_INVALID,
        code,
        "@Input()");
  }

  Future test_outputOnSetterIsError() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-component', template: '')
class MyComponent {
  @Output()
  set someSetter(x) { }
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    assertErrorInCodeAtPosition(
        AngularWarningCode.OUTPUT_ANNOTATION_PLACEMENT_INVALID,
        code,
        "@Output()");
  }
}

@reflectiveTest
class BuildUnitViewsTest extends AbstractAngularTest {
  List<AbstractDirective> directives;
  List<View> views;
  List<AnalysisError> errors;

  Future getViews(Source source) async {
    final dartResult = await dartDriver.getResult(source.fullName);
    fillErrorListener(dartResult.errors);
    final result = await angularDriver.getDirectives(source.fullName);
    directives = result.directives;

    final linker = new ChildDirectiveLinker(
        angularDriver, new ErrorReporter(errorListener, source));
    await linker.linkDirectives(directives, dartResult.unit.element.library);
    views = directives
        .map((d) => d is Component ? d.view : null)
        .where((d) => d != null)
        .toList();
    errors = result.errors;
    fillErrorListener(errors);
  }

  Future test_buildViewsDoesntGetDependentDirectives() async {
    String code = r'''
import '/angular2/angular2.dart';
import 'other_file.dart';

@Component(selector: 'my-component', template: 'My template',
    directives: const [OtherComponent])
class MyComponent {}
''';
    String otherCode = r'''
import '/angular2/angular2.dart';
@Component(selector: 'other-component', template: 'My template',
    directives: const [NgFor])
class OtherComponent {}
''';
    Source source = newSource('/test.dart', code);
    newSource('/other_file.dart', otherCode);
    await getViews(source);
    {
      View view = getViewByClassName(views, 'MyComponent');
      {
        expect(view.directives, hasLength(1));
      }

      // shouldn't be run yet
      for (AbstractDirective directive in view.directives) {
        if (directive is Component) {
          expect(directive.view.directives, hasLength(0));
        }
      }
    }
    // no errors
    errorListener.assertNoErrors();
  }

  Future test_directives() async {
    String code = r'''
import '/angular2/angular2.dart';

@Directive(selector: '[aaa]')
class DirectiveA {}

@Directive(selector: '[bbb]')
class DirectiveB {}

@Directive(selector: '[ccc]')
class DirectiveC {}

const DIR_AB = const [DirectiveA, DirectiveB];

@Component(selector: 'my-component', template: 'My template',
    directives: const [DIR_AB, DirectiveC])
class MyComponent {}
''';
    Source source = newSource('/test.dart', code);
    await getViews(source);
    {
      View view = getViewByClassName(views, 'MyComponent');
      {
        expect(view.directives, hasLength(3));
        List<String> directiveClassNames = view.directives
            .map((directive) => directive.classElement.name)
            .toList();
        expect(directiveClassNames,
            unorderedEquals(['DirectiveA', 'DirectiveB', 'DirectiveC']));
      }
    }
    // no errors
    errorListener.assertNoErrors();
  }

  Future test_prefixedDirectives() async {
    String otherCode = r'''
import '/angular2/angular2.dart';

@Directive(selector: '[aaa]')
class DirectiveA {}

@Directive(selector: '[bbb]')
class DirectiveB {}

@Directive(selector: '[ccc]')
class DirectiveC {}

const DIR_AB = const [DirectiveA, DirectiveB];
''';

    String code = r'''
import '/angular2/angular2.dart';
import 'other.dart' as other;

@Component(selector: 'my-component', template: 'My template',
    directives: const [other.DIR_AB, other.DirectiveC])
class MyComponent {}
''';
    Source source = newSource('/test.dart', code);
    newSource('/other.dart', otherCode);
    await getViews(source);
    {
      View view = getViewByClassName(views, 'MyComponent');
      {
        expect(view.directives, hasLength(3));
        List<String> directiveClassNames = view.directives
            .map((directive) => directive.classElement.name)
            .toList();
        expect(directiveClassNames,
            unorderedEquals(['DirectiveA', 'DirectiveB', 'DirectiveC']));
      }
    }
    // no errors
    errorListener.assertNoErrors();
  }

  Future test_directives_hasError_notListVariable() async {
    String code = r'''
import '/angular2/angular2.dart';

const NOT_DIRECTIVE_LIST = 42;

@Component(selector: 'my-component', template: 'My template',
   directives: const [NOT_DIRECTIVE_LIST])
class MyComponent {}
''';
    Source source = newSource('/test.dart', code);
    await getViews(source);
    errorListener.assertErrorsWithCodes(
        <ErrorCode>[AngularWarningCode.TYPE_IS_NOT_A_DIRECTIVE]);
  }

  Future test_hasError_ComponentAnnotationMissing() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@View(template: 'AAA')
class ComponentA {
}
''');
    await getViews(source);
    errorListener.assertErrorsWithCodes(
        <ErrorCode>[AngularWarningCode.COMPONENT_ANNOTATION_MISSING]);
  }

  Future test_hasError_StringValueExpected() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Component(selector: 'aaa', template: 55)
class ComponentA {
}
''');
    await getViews(source);
    errorListener.assertErrorsWithCodes(<ErrorCode>[
      AngularWarningCode.STRING_VALUE_EXPECTED,
      StaticWarningCode.ARGUMENT_TYPE_NOT_ASSIGNABLE
    ]);
  }

  Future test_constantExpressionTemplateOk() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Component(selector: 'aaa', template: 'abc' + 'bcd')
class ComponentA {
}
''');
    await getViews(source);
    errorListener.assertNoErrors();
  }

  Future test_constantExpressionTemplateComplexIsOnlyError() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

const String tooComplex = 'bcd';

@Component(selector: 'aaa', template: 'abc' + tooComplex + "{{invalid {{stuff")
class ComponentA {
}
''');
    await getViews(source);
    errorListener.assertErrorsWithCodes(
        <ErrorCode>[AngularWarningCode.STRING_VALUE_EXPECTED]);
  }

  Future test_hasError_TypeLiteralExpected() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Component(selector: 'aaa', template: 'AAA', directives: const [42])
class ComponentA {
}
''');
    await getViews(source);
    errorListener.assertErrorsWithCodes(
        <ErrorCode>[AngularWarningCode.TYPE_LITERAL_EXPECTED]);
  }

  Future test_hasError_TemplateAndTemplateUrlDefined() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Component(selector: 'aaa', template: 'AAA', templateUrl: 'a.html')
class ComponentA {
}
''');
    newSource('/a.html', '');
    await getViews(source);
    errorListener.assertErrorsWithCodes(
        <ErrorCode>[AngularWarningCode.TEMPLATE_URL_AND_TEMPLATE_DEFINED]);
  }

  Future test_hasError_NeitherTemplateNorTemplateUrlDefined() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Component(selector: 'aaa')
class ComponentA {
}
''');
    await getViews(source);
    errorListener.assertErrorsWithCodes(
        <ErrorCode>[AngularWarningCode.NO_TEMPLATE_URL_OR_TEMPLATE_DEFINED]);
  }

  Future test_hasError_missingHtmlFile() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-component', templateUrl: 'missing-template.html')
class MyComponent {}
''';
    Source dartSource = newSource('/test.dart', code);
    await getViews(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.REFERENCED_HTML_FILE_DOESNT_EXIST,
        code,
        "'missing-template.html'");
  }

  Future test_templateExternal() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-component', templateUrl: 'my-template.html')
class MyComponent {}
''';
    Source dartSource = newSource('/test.dart', code);
    Source htmlSource = newSource('/my-template.html', '');
    await getViews(dartSource);
    expect(views, hasLength(1));
    // MyComponent
    View view = getViewByClassName(views, 'MyComponent');
    expect(view.component, getComponentByClassName(directives, 'MyComponent'));
    expect(view.templateText, isNull);
    expect(view.templateUriSource, isNotNull);
    expect(view.templateUriSource, htmlSource);
    expect(view.templateSource, htmlSource);
    {
      String url = "'my-template.html'";
      expect(view.templateUrlRange,
          new SourceRange(code.indexOf(url), url.length));
    }
  }

  Future test_templateExternalUsingViewAnnotation() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-component')
@View(templateUrl: 'my-template.html')
class MyComponent {}
''';
    Source dartSource = newSource('/test.dart', code);
    Source htmlSource = newSource('/my-template.html', '');
    await getViews(dartSource);
    expect(views, hasLength(1));
    // MyComponent
    View view = getViewByClassName(views, 'MyComponent');
    expect(view.component, getComponentByClassName(directives, 'MyComponent'));
    expect(view.templateText, isNull);
    expect(view.templateUriSource, isNotNull);
    expect(view.templateUriSource, htmlSource);
    expect(view.templateSource, htmlSource);
    {
      String url = "'my-template.html'";
      expect(view.templateUrlRange,
          new SourceRange(code.indexOf(url), url.length));
    }
  }

  Future test_templateInline() async {
    String code = r'''
import '/angular2/angular2.dart';

@Directive(selector: 'my-directive')
class MyDirective {}

@Component(selector: 'other-component', template: 'Other template')
class OtherComponent {}

@Component(selector: 'my-component', template: 'My template',
    directives: const [MyDirective, OtherComponent])
class MyComponent {}
''';
    Source source = newSource('/test.dart', code);
    await getViews(source);
    expect(views, hasLength(2));
    {
      View view = getViewByClassName(views, 'MyComponent');
      expect(
          view.component, getComponentByClassName(directives, 'MyComponent'));
      expect(view.templateText, ' My template '); // spaces preserve offsets
      expect(view.templateOffset, code.indexOf('My template') - 1);
      expect(view.templateUriSource, isNull);
      expect(view.templateSource, source);
      {
        expect(view.directives, hasLength(2));
        List<String> directiveClassNames = view.directives
            .map((directive) => directive.classElement.name)
            .toList();
        expect(directiveClassNames,
            unorderedEquals(['OtherComponent', 'MyDirective']));
      }
    }
  }

  Future test_templateInlineUsingViewAnnotation() async {
    String code = r'''
import '/angular2/angular2.dart';

@Directive(selector: 'my-directive')
class MyDirective {}

@Component(selector: 'other-component')
@View(template: 'Other template')
class OtherComponent {}

@Component(selector: 'my-component')
@View(template: 'My template', directives: const [MyDirective, OtherComponent])
class MyComponent {}
''';
    Source source = newSource('/test.dart', code);
    await getViews(source);
    expect(views, hasLength(2));
    {
      View view = getViewByClassName(views, 'MyComponent');
      expect(
          view.component, getComponentByClassName(directives, 'MyComponent'));
      expect(view.templateText, ' My template '); // spaces preserve offsets
      expect(view.templateOffset, code.indexOf('My template') - 1);
      expect(view.templateUriSource, isNull);
      expect(view.templateSource, source);
      {
        expect(view.directives, hasLength(2));
        List<String> directiveClassNames = view.directives
            .map((directive) => directive.classElement.name)
            .toList();
        expect(directiveClassNames,
            unorderedEquals(['OtherComponent', 'MyDirective']));
      }
    }
  }
}

@reflectiveTest
class ResolveDartTemplatesTest extends AbstractAngularTest {
  List<AbstractDirective> directives;
  List<Template> templates;
  List<AnalysisError> errors;

  Future getDirectives(Source source) async {
    final dartResult = await dartDriver.getResult(source.fullName);
    fillErrorListener(dartResult.errors);
    final ngResult = await angularDriver.resolveDart(source.fullName);
    directives = ngResult.directives;
    errors = ngResult.errors;
    fillErrorListener(errors);
    templates = directives
        .map((d) => d is Component ? d.view?.template : null)
        .where((d) => d != null)
        .toList();
  }

  Future test_hasError_DirectiveTypeLiteralExpected() async {
    Source source = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Component(selector: 'aaa', template: 'AAA', directives: const [int])
class ComponentA {
}
''');
    await getDirectives(source);
    errorListener.assertErrorsWithCodes(
        <ErrorCode>[AngularWarningCode.TYPE_IS_NOT_A_DIRECTIVE]);
  }

  Future test_componentReference() async {
    var code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-aaa', template: '<div>AAA</div>')
class ComponentA {
}

@Component(selector: 'my-bbb', template: '<div>BBB</div>')
class ComponentB {
}

@Component(selector: 'my-ccc', template: r"""
<div>
  <my-aaa></my-aaa>1
  <my-bbb></my-bbb>2
</div>
""", directives: const [ComponentA, ComponentB])
class ComponentC {
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    Component componentA = getComponentByClassName(directives, 'ComponentA');
    Component componentB = getComponentByClassName(directives, 'ComponentB');
    // validate
    expect(templates, hasLength(3));
    {
      Template template = _getDartTemplateByClassName(templates, 'ComponentA');
      expect(template.ranges, isEmpty);
    }
    {
      Template template = _getDartTemplateByClassName(templates, 'ComponentB');
      expect(template.ranges, isEmpty);
    }
    {
      Template template = _getDartTemplateByClassName(templates, 'ComponentC');
      List<ResolvedRange> ranges = template.ranges;
      expect(ranges, hasLength(4));
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(code, ranges, 'my-aaa></');
        assertComponentReference(resolvedRange, componentA);
      }
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(code, ranges, 'my-aaa>1');
        assertComponentReference(resolvedRange, componentA);
      }
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(code, ranges, 'my-bbb></');
        assertComponentReference(resolvedRange, componentB);
      }
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(code, ranges, 'my-bbb>2');
        assertComponentReference(resolvedRange, componentB);
      }
    }
    // no errors
    errorListener.assertNoErrors();
  }

  Future test_hasError_expression_ArgumentTypeNotAssignable() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'text-panel',
    template: r"<div> {{text.length + text}} </div>")
class TextPanel {
  String text;
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    errorListener.assertErrorsWithCodes(
        [StaticWarningCode.ARGUMENT_TYPE_NOT_ASSIGNABLE]);
  }

  Future test_hasError_expression_UndefinedIdentifier() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'text-panel', inputs: const ['text'],
    template: r"<div>some text</div>")
class TextPanel {
  String text;
}

@Component(selector: 'UserPanel', template: r"""
<div>
  <text-panel [text]='noSuchName'></text-panel>
</div>
""", directives: const [TextPanel])
class UserPanel {
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    errorListener
        .assertErrorsWithCodes([StaticWarningCode.UNDEFINED_IDENTIFIER]);
  }

  Future
      test_hasError_expression_UndefinedIdentifier_OutsideFirstHtmlTag() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-component', template: '<h1></h1>{{noSuchName}}')
class MyComponent {
}
''';

    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    assertErrorInCodeAtPosition(
        StaticWarningCode.UNDEFINED_IDENTIFIER, code, 'noSuchName');
  }

  Future test_hasError_UnresolvedTag() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-aaa',
    template: "<unresolved-tag attr='value'></unresolved-tag>")
class ComponentA {
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    assertErrorInCodeAtPosition(
        AngularWarningCode.UNRESOLVED_TAG, code, 'unresolved-tag');
  }

  Future test_suppressError_UnresolvedTag() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-aaa',
    template: """
<!-- @ngIgnoreErrors: UNRESOLVED_TAG -->
<unresolved-tag attr='value'></unresolved-tag>""")
class ComponentA {
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    errorListener.assertNoErrors();
  }

  Future test_suppressError_NotCaseSensitive() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-aaa',
    template: """
<!-- @ngIgnoreErrors: UnReSoLvEd_tAg -->
<unresolved-tag attr='value'></unresolved-tag>""")
class ComponentA {
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    errorListener.assertNoErrors();
  }

  Future test_suppressError_UnresolvedTagAndInput() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-aaa',
    template: """
<!-- @ngIgnoreErrors: UNRESOLVED_TAG, NONEXIST_INPUT_BOUND -->
<unresolved-tag [attr]='value'></unresolved-tag>""")
class ComponentA {
  Object value;
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    errorListener.assertNoErrors();
  }

  Future test_htmlParsing_hasError() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'text-panel',
    template: r"<div> <h2> Expected closing H2 </h3> </div>")
class TextPanel {
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    // has errors
    errorListener.assertErrorsWithCodes([
      NgParserWarningCode.DANGLING_CLOSE_ELEMENT,
      NgParserWarningCode.CANNOT_FIND_MATCHING_CLOSE,
    ]);
  }

  Future test_input_OK_event() async {
    String code = r'''
import 'dart:html';
import '/angular2/angular2.dart';

@Component(selector: 'UserPanel', template: r"""
<div>
  <input (click)='gotClicked($event)'>
</div>
""")
class TodoList {
  gotClicked(MouseEvent event) {}
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    expect(templates, hasLength(1));
    {
      Template template = _getDartTemplateByClassName(templates, 'TodoList');
      List<ResolvedRange> ranges = template.ranges;
      expect(ranges, hasLength(4));
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(code, ranges, r'gotClicked($');
        expect(resolvedRange.range.length, 'gotClicked'.length);
        Element element = (resolvedRange.element as DartElement).element;
        expect(element, new isInstanceOf<MethodElement>());
        expect(element.name, 'gotClicked');
        expect(
            element.nameOffset, code.indexOf('gotClicked(MouseEvent event)'));
      }
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(code, ranges, r"$event)'>");
        expect(resolvedRange.range.length, r'$event'.length);
        Element element = (resolvedRange.element as LocalVariable).dartVariable;
        expect(element, new isInstanceOf<LocalVariableElement>());
        expect(element.name, r'$event');
        expect(element.nameOffset, -1);
      }
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(code, ranges, 'click');
        expect(resolvedRange.range.length, 'click'.length);
      }
    }
    // no errors
    errorListener.assertNoErrors();
  }

  Future test_input_OK_reference_expression() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'text-panel', inputs: const ['text'],
    template: r"<div>some text</div>")
class TextPanel {
  String text;
}

@Component(selector: 'UserPanel', template: r"""
<div>
  <text-panel [text]='user.name'></text-panel>
</div>
""", directives: const [TextPanel])
class UserPanel {
  User user; // 1
}

class User {
  String name; // 2
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    Component textPanel = getComponentByClassName(directives, 'TextPanel');
    // validate
    expect(templates, hasLength(2));
    {
      Template template = _getDartTemplateByClassName(templates, 'UserPanel');
      List<ResolvedRange> ranges = template.ranges;
      expect(ranges, hasLength(5));
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(code, ranges, 'text]=');
        expect(resolvedRange.range.length, 'text'.length);
        assertPropertyReference(resolvedRange, textPanel, 'text');
      }
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(code, ranges, 'user.');
        expect(resolvedRange.range.length, 'user'.length);
        Element element = (resolvedRange.element as DartElement).element;
        expect(element, new isInstanceOf<PropertyAccessorElement>());
        expect(element.name, 'user');
        expect(element.nameOffset, code.indexOf('user; // 1'));
      }
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(code, ranges, "name'>");
        expect(resolvedRange.range.length, 'name'.length);
        Element element = (resolvedRange.element as DartElement).element;
        expect(element, new isInstanceOf<PropertyAccessorElement>());
        expect(element.name, 'name');
        expect(element.nameOffset, code.indexOf('name; // 2'));
      }
    }
    // no errors
    errorListener.assertNoErrors();
  }

  Future test_input_OK_reference_text() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(
    selector: 'comp-a',
    inputs: const ['firstValue', 'vtoroy: second'],
    template: r"<div>AAA</div>")
class ComponentA {
  int firstValue;
  int vtoroy;
}

@Component(selector: 'comp-b', template: r"""
<div>
  <comp-a [firstValue]='1' [second]='2'></comp-a>
</div>
""", directives: const [ComponentA])
class ComponentB {
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    Component componentA = getComponentByClassName(directives, 'ComponentA');
    // validate
    expect(templates, hasLength(2));
    {
      Template template = _getDartTemplateByClassName(templates, 'ComponentB');
      List<ResolvedRange> ranges = template.ranges;
      expect(ranges, hasLength(4));
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(code, ranges, 'firstValue]=');
        expect(resolvedRange.range.length, 'firstValue'.length);
        assertPropertyReference(resolvedRange, componentA, 'firstValue');
      }
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(code, ranges, 'second]=');
        expect(resolvedRange.range.length, 'second'.length);
        assertPropertyReference(resolvedRange, componentA, 'second');
      }
    }
    // no errors
    errorListener.assertNoErrors();
  }

  Future test_noRootElement() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'text-panel',
    template: r'Often used without an element in tests.')
class TextPanel {
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    expect(templates, hasLength(1));
    // has errors
    errorListener.assertNoErrors();
  }

  Future test_noTemplateContents() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'text-panel',
    template: '')
class TextPanel {
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    expect(templates, hasLength(1));
    // has errors
    errorListener.assertNoErrors();
  }

  Future test_textExpression_hasError_UnterminatedMustache() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'text-panel', template: r"{{text")
class TextPanel {
  String text = "text";
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    // has errors
    errorListener
        .assertErrorsWithCodes([AngularWarningCode.UNTERMINATED_MUSTACHE]);
  }

  Future test_textExpression_hasError_UnopenedMustache() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'text-panel', template: r"<div> text}} </div>")
class TextPanel {
  String text;
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    // has errors
    errorListener.assertErrorsWithCodes([AngularWarningCode.UNOPENED_MUSTACHE]);
  }

  Future test_textExpression_hasError_DoubleOpenedMustache() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'text-panel', template: r"<div> {{text {{ error}} </div>")
class TextPanel {
  String text;
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    errorListener.assertErrorsWithCodes([
      AngularWarningCode.UNTERMINATED_MUSTACHE,
      StaticWarningCode.UNDEFINED_IDENTIFIER
    ]);
  }

  Future test_textExpression_hasError_MultipleUnclosedMustaches() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'text-panel', template: r"<div> {{open {{error {{text}} close}} close}} </div>")
class TextPanel {
  String text, open, close;
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    errorListener.assertErrorsWithCodes([
      AngularWarningCode.UNTERMINATED_MUSTACHE,
      AngularWarningCode.UNTERMINATED_MUSTACHE,
      StaticWarningCode.UNDEFINED_IDENTIFIER,
      AngularWarningCode.UNOPENED_MUSTACHE,
      AngularWarningCode.UNOPENED_MUSTACHE,
    ]);
  }

  Future test_textExpression_OK() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'text-panel', inputs: const ['text'],
    template: r"<div> <h2> {{text}}  </h2> and {{text.length}} </div>")
class TextPanel {
  String text; // 1
}
''';
    Source source = newSource('/test.dart', code);
    await getDirectives(source);
    expect(templates, hasLength(1));
    {
      Template template = _getDartTemplateByClassName(templates, 'TextPanel');
      List<ResolvedRange> ranges = template.ranges;
      expect(ranges, hasLength(5));
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(code, ranges, 'text}}');
        expect(resolvedRange.range.length, 'text'.length);
        PropertyAccessorElement element = assertGetter(resolvedRange);
        expect(element.name, 'text');
        expect(element.nameOffset, code.indexOf('text; // 1'));
      }
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(code, ranges, 'text.length');
        expect(resolvedRange.range.length, 'text'.length);
        PropertyAccessorElement element = assertGetter(resolvedRange);
        expect(element.name, 'text');
        expect(element.nameOffset, code.indexOf('text; // 1'));
      }
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(code, ranges, 'length}}');
        expect(resolvedRange.range.length, 'length'.length);
        PropertyAccessorElement element = assertGetter(resolvedRange);
        expect(element.name, 'length');
        expect(element.enclosingElement.name, 'String');
      }
    }
    // no errors
    errorListener.assertNoErrors();
  }

  Future test_resolveGetChildDirectivesNgContentSelectors_in_template() async {
    String code = r'''
import '/angular2/angular2.dart';
import 'child_file.dart';

@Component(selector: 'my-component', template: 'My template',
    directives: const [ChildComponent])
class MyComponent {}
''';
    String childCode = r'''
import '/angular2/angular2.dart';
@Component(selector: 'child-component',
    template: 'My template <ng-content></ng-content>',
    directives: const [])
class ChildComponent {}
''';
    Source source = newSource('/test.dart', code);
    newSource('/child_file.dart', childCode);
    await getDirectives(source);
    expect(templates, hasLength(1));
    // no errors
    errorListener.assertNoErrors();

    List<AbstractDirective> childDirectives = templates.first.view.directives;
    expect(childDirectives, hasLength(1));

    List<View> childViews = childDirectives
        .map((d) => d is Component ? d.view : null)
        .where((v) => v != null)
        .toList();
    expect(childViews, hasLength(1));
    View childView = childViews.first;
    expect(childView.component, isNotNull);
    expect(childView.component.ngContents, hasLength(1));
  }

  static Template _getDartTemplateByClassName(
      List<Template> templates, String className) {
    return templates.firstWhere(
        (template) => template.view.classElement.name == className, orElse: () {
      fail('Template with the class "$className" was not found.');
      return null;
    });
  }
}

@reflectiveTest
class ResolveHtmlTemplatesTest extends AbstractAngularTest {
  List<Template> templates;
  Future getDirectives(Source dartSource) async {
    final result = await angularDriver.resolveDart(dartSource.fullName);
    final finder = (AbstractDirective d) =>
        d is Component && d.view.templateUriSource != null;
    fillErrorListener(result.errors);
    final directives = result.directives.where(finder);
    final htmlPath =
        (directives.first as Component).view.templateUriSource.fullName;
    final result2 =
        await angularDriver.resolveHtml(htmlPath, dartSource.fullName);
    fillErrorListener(result2.errors);
    templates = result2.directives
        .where(finder)
        .map((d) => d is Component ? d.view?.template : null)
        .where((d) => d != null);
  }

  Future test_multipleViewsWithTemplate() async {
    String dartCode = r'''
import '/angular2/angular2.dart';

@Component(selector: 'text-panelA', templateUrl: 'text_panel.html')
class TextPanelA {
  String text; // A
}

@Component(selector: 'text-panelB', templateUrl: 'text_panel.html')
class TextPanelB {
  String text; // B
}
''';
    String htmlCode = r"""
<div>
  {{text}}
</div>
""";
    Source dartSource = newSource('/test.dart', dartCode);
    newSource('/text_panel.html', htmlCode);
    await getDirectives(dartSource);
    expect(templates, hasLength(2));
    // validate templates
    bool hasTextPanelA = false;
    bool hasTextPanelB = false;
    for (HtmlTemplate template in templates) {
      String viewClassName = template.view.classElement.name;
      String textTargetPattern;
      if (viewClassName == 'TextPanelA') {
        hasTextPanelA = true;
        textTargetPattern = 'text; // A';
      }
      if (viewClassName == 'TextPanelB') {
        hasTextPanelB = true;
        textTargetPattern = 'text; // B';
      }
      expect(template.ranges, hasLength(1));
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(htmlCode, template.ranges, 'text}}');
        PropertyAccessorElement element = assertGetter(resolvedRange);
        expect(element.name, 'text');
        expect(element.nameOffset, dartCode.indexOf(textTargetPattern));
      }
    }
    expect(hasTextPanelA, isTrue);
    expect(hasTextPanelB, isTrue);
  }
}

@reflectiveTest
class ResolveHtmlTemplateTest extends AbstractAngularTest {
  List<View> views;
  Future getDirectives(Source dartSource) async {
    final result = await angularDriver.resolveDart(dartSource.fullName);
    final finder = (AbstractDirective d) =>
        d is Component && d.view.templateUriSource != null;
    fillErrorListener(result.errors);
    final directive = result.directives.singleWhere(finder);
    final htmlPath = (directive as Component).view.templateUriSource.fullName;
    final ngResult =
        await angularDriver.resolveHtml(htmlPath, dartSource.fullName);
    fillErrorListener(ngResult.errors);
    views = ngResult.directives
        .where(finder)
        .map((d) => d is Component ? d.view : null)
        .where((d) => d != null);
  }

  Future test_suppressError_UnresolvedTagHtmlTemplate() async {
    Source dartSource = newSource(
        '/test.dart',
        r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-aaa', templateUrl: 'test.html')
class ComponentA {
}
''');
    newSource(
        '/test.html',
        '''
<!-- @ngIgnoreErrors: UNRESOLVED_TAG -->
<unresolved-tag attr='value'></unresolved-tag>""")
''');
    await getDirectives(dartSource);
    errorListener.assertNoErrors();
  }

  Future test_errorFromWeirdInclude_includesFromPath() async {
    String code = r'''
import '/angular2/angular2.dart';

@Component(selector: 'my-aaa', templateUrl: "test.html")
class ComponentA {
}
''';
    Source dartSource = newSource('/weird.dart', code);
    newSource('/test.html', "<unresolved-tag></unresolved-tag>");
    await getDirectives(dartSource);
    final errors = errorListener.errors;
    expect(errors, hasLength(1));
    expect(errors.first, new isInstanceOf<FromFilePrefixedError>());
    expect(errors.first.message,
        equals('Unresolved tag "unresolved-tag" (from /weird.dart)'));
  }

  Future test_hasViewWithTemplate() async {
    String dartCode = r'''
import '/angular2/angular2.dart';

@Component(selector: 'text-panel', templateUrl: 'text_panel.html')
class TextPanel {
  String text; // 1
}
''';
    String htmlCode = r"""
<div>
  {{text}}
</div>
""";
    Source dartSource = newSource('/test.dart', dartCode);
    newSource('/text_panel.html', htmlCode);
    // compute
    await getDirectives(dartSource);
    expect(views, hasLength(1));
    {
      View view = getViewByClassName(views, 'TextPanel');
      expect(view.templateUriSource, isNotNull);
      // resolve this View
      Template template = view.template;
      expect(template, isNotNull);
      expect(template.view, view);
      expect(template.ranges, hasLength(1));
      {
        ResolvedRange resolvedRange =
            getResolvedRangeAtString(htmlCode, template.ranges, 'text}}');
        PropertyAccessorElement element = assertGetter(resolvedRange);
        expect(element.name, 'text');
        expect(element.nameOffset, dartCode.indexOf('text; // 1'));
      }
    }
  }

  Future test_resolveGetChildDirectivesNgContentSelectors() async {
    String code = r'''
import '/angular2/angular2.dart';
import 'child_file.dart';

import '/angular2/angular2.dart';
@Component(selector: 'my-component', templateUrl: 'test.html',
    directives: const [ChildComponent])
class MyComponent {}
''';
    String childCode = r'''
import '/angular2/angular2.dart';
@Component(selector: 'child-component',
    template: 'My template <ng-content></ng-content>',
    directives: const [])
class ChildComponent {}
''';
    Source source = newSource('/test.dart', code);
    newSource('/child_file.dart', childCode);
    newSource('/test.html', '');
    await getDirectives(source);

    List<AbstractDirective> childDirectives = views.first.directives;
    expect(childDirectives, hasLength(1));

    View childView = (views.first.directives.first as Component).view;
    expect(childView.component, isNotNull);
    expect(childView.component.ngContents, hasLength(1));
  }
}
