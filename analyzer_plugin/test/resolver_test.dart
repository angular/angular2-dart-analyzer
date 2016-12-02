library angular2.src.analysis.analyzer_plugin.src.resolver_test;

import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:angular_analyzer_plugin/src/model.dart';
import 'package:angular_analyzer_plugin/src/selector.dart';
import 'package:angular_analyzer_plugin/src/tasks.dart';
import 'package:angular_analyzer_plugin/tasks.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:unittest/unittest.dart';

import 'abstract_angular.dart';
import 'element_assert.dart';

main() {
  groupSep = ' | ';
  defineReflectiveTests(TemplateResolverTest);
}

void assertPropertyElement(AngularElement element,
    {nameMatcher, sourceMatcher}) {
  expect(element, new isInstanceOf<InputElement>());
  InputElement inputElement = element;
  if (nameMatcher != null) {
    expect(inputElement.name, nameMatcher);
  }
  if (sourceMatcher != null) {
    expect(inputElement.source.fullName, sourceMatcher);
  }
}

@reflectiveTest
class TemplateResolverTest extends AbstractAngularTest {
  String dartCode;
  String htmlCode;
  Source dartSource;
  Source htmlSource;

  List<AbstractDirective> directives;

  Template template;
  List<ResolvedRange> ranges;

  void test_attribute_mixedCase() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {
}
''');
    _addHtmlSource(r"""
<svg viewBox='0, 0, 24 24'></svg>
""");
    _resolveSingleTemplate(dartSource);
    expect(ranges, hasLength(0));
  }

  void test_attributeInterpolation() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {
  String aaa; // 1
  String bbb; // 2
}
''');
    _addHtmlSource(r"""
<span title='Hello {{aaa}} and {{bbb}}!'></span>
""");
    _resolveSingleTemplate(dartSource);
    expect(ranges, hasLength(2));
    _assertElement('aaa}}').dart.getter.at('aaa; // 1');
    _assertElement('bbb}}').dart.getter.at('bbb; // 2');
  }

  void test_expression_eventBinding() {
    _addDartSource(r'''
import 'dart:html';
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {
  void handleClick(MouseEvent e) {
  }
}
''');
    _addHtmlSource(r"""
<div (click)='handleClick()'></div>
""");
    _resolveSingleTemplate(dartSource);
    expect(ranges, hasLength(2));
    _assertElement('click)').output.inCoreHtml;
    _assertElement('handleClick').dart.method.at('handleClick(MouseEvent');
  }

  void test_expression_nativeEventBindingOnComponent() {
    _addDartSource(r'''
import 'dart:html';
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: [SomeComponent])
class TestPanel {
  void handleClick(MouseEvent e) {
  }
}

@Component(selector: 'some-comp', template: '')
class SomeComponent {
}
''');
    _addHtmlSource(r"""
<some-comp (click)='handleClick($event)'></some-comp>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
    _assertElement('click').output.inCoreHtml;
  }

  void test_expression_eventBinding_on() {
    _addDartSource(r'''
import 'dart:html';
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {
  void handleClick(MouseEvent e) {
  }
}
''');
    _addHtmlSource(r"""
<div on-click='handleClick()'></div>
""");
    _resolveSingleTemplate(dartSource);
    expect(ranges, hasLength(2));
    _assertElement('click=').output.inCoreHtml;
    _assertElement('handleClick()').dart.method.at('handleClick(MouseEvent');
  }

  void test_expression_inputBinding_valid() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [TitleComponent], templateUrl: 'test_panel.html')
class TestPanel {
  String text; // 1
}
@Directive(selector: '[titled]', template: '', inputs: 'title')
class TitleComponent {
  @Input() String title;
}
''');
    _addHtmlSource(r"""
<span titled [title]='text'></span>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
  }

  void test_expression_inputBinding_typeError() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [TitleComponent], templateUrl: 'test_panel.html')
class TestPanel {
  String text; // 1
}
@Component(selector: 'title-comp', template: '', inputs: 'title')
class TitleComponent {
  @Input() int title;
}
''');
    var code = r"""
<title-comp [title]='text'></title-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.INPUT_BINDING_TYPE_ERROR, code, "text");
  }

  void test_expression_inputBinding_boundToNothing() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  String text; // 1
}
''');
    var code = r"""
<span [title]='text'></span>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.NONEXIST_INPUT_BOUND, code, "[title]");
  }

  void test_expression_twoWayBinding_valid() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [TitleComponent], templateUrl: 'test_panel.html')
class TestPanel {
  String text; // 1
}
@Directive(selector: '[titled]', template: '', inputs: 'title')
class TitleComponent {
  @Input() String title;
  @Output() EventEmitter<String> titleChange;
}
''');
    _addHtmlSource(r"""
<span titled [(title)]='text'></span>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
  }

  void test_expression_twoWayBinding_inputTypeError() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [TitleComponent], templateUrl: 'test_panel.html')
class TestPanel {
  String text; // 1
}
@Component(selector: 'title-comp', template: '', inputs: 'title')
class TitleComponent {
  @Input() int title;
  @Output() EventEmitter<String> titleChange;
}
''');
    var code = r"""
<title-comp [(title)]='text'></title-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.INPUT_BINDING_TYPE_ERROR, code, "text");
  }

  void test_expression_twoWayBinding_outputTypeError() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [TitleComponent], templateUrl: 'test_panel.html')
class TestPanel {
  String text; // 1
}
@Component(selector: 'title-comp', template: '', inputs: 'title')
class TitleComponent {
  @Input() String title;
  @Output() EventEmitter<int> titleChange;
}
''');
    var code = r"""
<title-comp [(title)]='text'></title-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.TWO_WAY_BINDING_OUTPUT_TYPE_ERROR, code, "text");
  }

  void test_expression_twoWayBinding_notAssignableError() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [TitleComponent], templateUrl: 'test_panel.html')
class TestPanel {
  String text; // 1
}
@Component(selector: 'title-comp', template: '', inputs: 'title')
class TitleComponent {
  @Input() String title;
  @Output() EventEmitter<String> titleChange;
}
''');
    var code = r"""
<title-comp [(title)]="text.toUpperCase()"></title-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.TWO_WAY_BINDING_NOT_ASSIGNABLE,
        code,
        "text.toUpperCase()");
  }

  void test_expression_twoWayBinding_noInputToBind() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [TitleComponent], templateUrl: 'test_panel.html')
class TestPanel {
  String text; // 1
}
@Component(selector: 'title-comp', template: '', inputs: 'title')
class TitleComponent {
  @Output() EventEmitter<String> titleChange;
}
''');
    var code = r"""
<title-comp [(title)]="text"></title-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.NONEXIST_INPUT_BOUND, code, "[(title)]");
  }

  void test_expression_twoWayBinding_noOutputToBind() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [TitleComponent], templateUrl: 'test_panel.html')
class TestPanel {
  String text; // 1
}
@Component(selector: 'title-comp', template: '', inputs: 'title')
class TitleComponent {
  @Input() String title;
}
''');
    var code = r"""
<title-comp [(title)]="text"></title-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.NONEXIST_TWO_WAY_OUTPUT_BOUND, code, "[(title)]");
  }

  void test_expression_inputBinding_bind() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {
  String text; // 1
}
''');
    _addHtmlSource(r"""
<span bind-title='text'></span>
""");
    _resolveSingleTemplate(dartSource);
    expect(ranges, hasLength(1));
    _assertElement("text'>").dart.getter.at('text; // 1');
  }

  void test_expression_outputBinding_boundToNothing() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  String text; // 1
}
''');
    var code = r"""
<span (title)='text'></span>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.NONEXIST_OUTPUT_BOUND, code, "(title)");
  }

  void test_expression_outputBinding_typeError() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [TitleComponent], templateUrl: 'test_panel.html')
class TestPanel {
  takeString(String arg);
}
@Component(selector: 'title-comp', template: '')
class TitleComponent {
  @Output() EventEmitter<int> output;
}
''');
    var code = r"""
<title-comp (output)='takeString($event)'></title-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        StaticWarningCode.ARGUMENT_TYPE_NOT_ASSIGNABLE, code, r"$event");
  }

  void test_expression_inputBinding_noEvent() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
}
''');
    var code = r"""
<h1 [hidden]="$event">
</h1>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        StaticWarningCode.UNDEFINED_IDENTIFIER, code, r"$event");
  }

  void test_expression_mustache_noEvent() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
}
''');
    var code = r"""
<h1>{{$event}}</h1>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        StaticWarningCode.UNDEFINED_IDENTIFIER, code, r"$event");
  }

  void test_expression_attrBinding_valid() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  String text; // 1
}
''');
    var code = r"""
<span [attr.aria-title]='text'></span>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
  }

  void test_expression_attrBinding_expressionTypeError() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  int pixels;
}
''');
    var code = r"""
<span [attr.aria]='pixels.length'></span>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        StaticTypeWarningCode.UNDEFINED_GETTER, code, "length");
  }

  void test_expression_classBinding_valid() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  String text; // 1
}
''');
    var code = r"""
<span [class.my-class]='text == null'></span>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
  }

  void test_expression_classBinding_invalidClassName() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  String title;
}
''');
    var code = r"""
<span [class.invalid.class]='title == null'></span>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.INVALID_HTML_CLASSNAME, code, "invalid.class");
  }

  void test_expression_classBinding_typeError() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  String notBoolean;
}
''');
    var code = r"""
<span [class.aria]='notBoolean'></span>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.CLASS_BINDING_NOT_BOOLEAN, code, "notBoolean");
  }

  void test_expression_styleBinding_noUnit_valid() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  String text; // 1
}
''');
    var code = r"""
<span [style.background-color]='text'></span>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
  }

  void test_expression_styleBinding_noUnit_invalidCssProperty() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  String text; // 1
}
''');
    var code = r"""
<span [style.invalid*property]='text'></span>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.INVALID_CSS_PROPERTY_NAME, code, "invalid*property");
  }

  void test_expression_styleBinding_noUnit_expressionTypeError() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  int noLength; // 1
}
''');
    var code = r"""
<span [style.background-color]='noLength.length'></span>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        StaticTypeWarningCode.UNDEFINED_GETTER, code, "length");
  }

  void test_expression_styleBinding_withUnit_invalidPropertyName() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  int pixels; // 1
}
''');
    var code = r"""
<span [style.border&radius.px]='pixels'></span>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.INVALID_CSS_PROPERTY_NAME, code, "border&radius");
  }

  void test_expression_styleBinding_withUnit_invalidUnitName() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  double pixels; // 1
}
''');
    var code = r"""
<span [style.border-radius.p|x]='pixels'></span>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.INVALID_CSS_UNIT_NAME, code, "p|x");
  }

  void test_expression_styleBinding_withUnit_typeError() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  String notNumber; // 1
}
''');
    var code = r"""
<span [style.border-radius.px]='notNumber'></span>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.CSS_UNIT_BINDING_NOT_NUMBER, code, "notNumber");
  }

  void test_expression_detect_eof_post_semicolon_in_moustache() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  String name = "TestPanel";
}
''');

    var code = r"""
<p>{{name; bad portion}}</p>
 """;
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.TRAILING_EXPRESSION, code, "; bad portion");
  }

  void test_expression_detect_eof_ellipsis_in_moustache() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  String name = "TestPanel";
}
''');
    var code = r"""
<p>{{name...}}</p>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.TRAILING_EXPRESSION, code, "...");
  }

  void test_expression_detect_eof_post_semicolon_in_property_binding() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  int a = 1;
  int b = 1;
}
''');

    var code = r"""
<div [class.selected]="a == b; bad portion"></div>
 """;
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.TRAILING_EXPRESSION, code, "; bad portion");
  }

  void test_expression_detect_eof_ellipsis_in_property_binding() {
    _addDartSource(r'''
@Component(selector: 'test-panel', templateUrl: 'test_panel.html')
class TestPanel {
  int a = 1;
  int b = 1;
}
''');
    var code = r"""
<div [class.selected]="a==b..."></div>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.TRAILING_EXPRESSION, code, "...");
  }

  void test_expression_inputAndOutputBinding_genericDirective_ok() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [GenericComponent], templateUrl: 'test_panel.html')
class TestPanel {
  String string;
}
@Component(selector: 'generic-comp', template: '')
class GenericComponent<T> {
  @Output() EventEmitter<T> output;
  @Input() T input;

  @Output() EventEmitter<T> twoWayChange;
  @Input() T twoWay;
}
''');
    var code = r"""
<generic-comp (output)='$event.length' [input]="string" [(twoWay)]="string"></generic-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
  }

  void test_expression_inputAndOutputBinding_genericDirectiveChild_ok() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [GenericComponent], templateUrl: 'test_panel.html')
class TestPanel {
  String string;
}
class Generic<T> {
  EventEmitter<T> output;
  T input;

  EventEmitter<T> twoWayChange;
  T twoWay;
}
@Component(selector: 'generic-comp', template: '',
    inputs: ['input', 'twoWay'], outputs: ['output', 'twoWayChange'])
class GenericComponent<T> extends Generic<T> {
}
''');
    var code = r"""
<generic-comp (output)='$event.length' [input]="string" [(twoWay)]="string"></generic-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
  }

  void test_expression_inputAndOutputBinding_extendGenericUnbounded_ok() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [GenericComponent], templateUrl: 'test_panel.html')
class TestPanel {
  String string;
}
class Generic<T> {
  EventEmitter<T> output;
  T input;

  EventEmitter<T> twoWayChange;
  T twoWay;
}
@Component(selector: 'generic-comp', template: '',
    inputs: ['input', 'twoWay'], outputs: ['output', 'twoWayChange'])
class GenericComponent<T> extends Generic {
}
''');
    var code = r"""
<generic-comp (output)='$event.length' [input]="string" [(twoWay)]="string"></generic-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
  }

  void test_expression_inputAndOutputBinding_genericDirective_chain_ok() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [GenericComponent], templateUrl: 'test_panel.html')
class TestPanel {
  String string;
}
@Component(selector: 'generic-comp', template: '')
class GenericComponent<T extends E, E> {
  @Output() EventEmitter<T> output;
  @Input() T input;

  @Output() EventEmitter<T> twoWayChange;
  @Input() T twoWay;
}
''');
    var code = r"""
<generic-comp (output)='$event.length' [input]="string" [(twoWay)]="string"></generic-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
  }

  void test_expression_inputAndOutputBinding_genericDirective_nested_ok() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [GenericComponent], templateUrl: 'test_panel.html')
class TestPanel {
  List<String> stringList;
}
@Component(selector: 'generic-comp', template: '')
class GenericComponent<T> {
  @Output() EventEmitter<List<T>> output;
  @Input() List<T> input;

  @Output() EventEmitter<List<T>> twoWayChange;
  @Input() List<T> twoWay;
}
''');
    var code = r"""
<generic-comp (output)='$event[0].length' [input]="stringList" [(twoWay)]="stringList"></generic-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
  }

  void test_expression_inputBinding_genericDirective_lowerBoundTypeError() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [GenericComponent], templateUrl: 'test_panel.html')
class TestPanel {
  int notString;
}
@Component(selector: 'generic-comp', template: '')
class GenericComponent<T extends String> {
  @Input() T string;
}
''');
    var code = r"""
<generic-comp [string]="notString"></generic-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.INPUT_BINDING_TYPE_ERROR, code, "notString");
  }

  void test_expression_input_genericDirective_lowerBoundChainTypeError() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [GenericComponent], templateUrl: 'test_panel.html')
class TestPanel {
  int notString;
}
@Component(selector: 'generic-comp', template: '')
class GenericComponent<T extends O, O extends String> {
  @Input() T string;
}
''');
    var code = r"""
<generic-comp [string]="notString"></generic-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.INPUT_BINDING_TYPE_ERROR, code, "notString");
  }

  void test_expression_input_genericDirective_lowerBoundNestedTypeError() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [GenericComponent], templateUrl: 'test_panel.html')
class TestPanel {
  List<int> notStringList;
}
@Component(selector: 'generic-comp', template: '')
class GenericComponent<T extends String> {
  @Input() List<T> stringList;
}
''');
    var code = r"""
<generic-comp [stringList]="notStringList"></generic-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.INPUT_BINDING_TYPE_ERROR, code, "notStringList");
  }

  void test_expression_outputBinding_genericDirective_lowerBoundTypeError() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [GenericComponent], templateUrl: 'test_panel.html')
class TestPanel {
  takeInt(int i) {}
}
@Component(selector: 'generic-comp', template: '')
class GenericComponent<T extends String> {
  @Output() EventEmitter<T> string;
}
''');
    var code = r"""
<generic-comp (string)="takeInt($event)"></generic-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        StaticWarningCode.ARGUMENT_TYPE_NOT_ASSIGNABLE, code, r"$event");
  }

  void test_expression_twoWayBinding_genericDirective_lowerBoundTypeError() {
    _addDartSource(r'''
@Component(selector: 'test-panel',
    directives: const [GenericComponent], templateUrl: 'test_panel.html')
class TestPanel {
  int anInt;
}
@Component(selector: 'generic-comp', template: '')
class GenericComponent<T extends String> {
  @Output() EventEmitter<T> stringChange;
  @Input() dynamic string;
}
''');
    var code = r"""
<generic-comp [(string)]="anInt"></generic-comp>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.TWO_WAY_BINDING_OUTPUT_TYPE_ERROR, code, "anInt");
  }

  void test_statement_eventBinding_single_statement_without_semicolon() {
    _addDartSource(r'''
import 'dart:html';
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {
  void handleClick(MouseEvent e) {
  }
}
''');
    _addHtmlSource(r"""
<div (click)='handleClick($event)'></div>
""");
    _resolveSingleTemplate(dartSource);
    _assertElement('handleClick').dart.method.at('handleClick(MouseEvent');
    errorListener.assertNoErrors();
  }

  void test_statement_eventBinding_single_statement_with_semicolon() {
    _addDartSource(r'''
import 'dart:html';
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {
  void handleClick(MouseEvent e) {
  }
}
''');
    _addHtmlSource(r"""
<div (click)='handleClick($event);'></div>
""");
    _resolveSingleTemplate(dartSource);
    _assertElement('handleClick').dart.method.at('handleClick(MouseEvent');
    errorListener.assertNoErrors();
  }

  void test_statement_eventBinding_return_statement() {
    _addDartSource(r'''
import 'dart:html';
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {
  void handleClick(MouseEvent e) {
  }
}
''');
    _addHtmlSource(r"""
<h2 (click)='return 5;'></h2>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
  }

  void test_statement_eventBinding_double_statement() {
    _addDartSource(r'''
import 'dart:html';
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {
  void handleClick(MouseEvent e) {
  }
}
''');
    _addHtmlSource(r"""
<div (click)='handleClick($event); 5+5;'></div>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
    _assertElement('handleClick').dart.method.at('handleClick(MouseEvent');
  }

  void test_statement_eventBinding_error_on_second_statement() {
    _addDartSource(r'''
import 'dart:html';
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {
  void handleClick(MouseEvent e) {
  }
}
''');
    String code = r"""
<div (click)='handleClick($event); unknownFunction()'></div>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        StaticTypeWarningCode.UNDEFINED_METHOD, code, "unknownFunction");
  }

  void test_inheritedFields() {
    _addDartSource(r'''
class BaseComponent {
  String text; // 1
}
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel extends BaseComponent {
  main() {
    text.length;
  }
}
''');
    _addHtmlSource(r"""
<div>
  Hello {{text}}!
</div>
""");
    _resolveSingleTemplate(dartSource);
    expect(ranges, hasLength(1));
    _assertElement("text}}").dart.getter.at('text; // 1');
    errorListener.assertNoErrors();
  }

  void test_inputReference() {
    _addDartSource(r'''
@Component(
    selector: 'name-panel',
    inputs: const ['aaa', 'bbb', 'ccc'])
@View(template: r"<div>AAA</div>")
class NamePanel {
  int aaa;
  int bbb;
  int ccc;
}
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NamePanel])
class TestPanel {}
''');
    _addHtmlSource(r"""
<name-panel aaa='1' [bbb]='2' bind-ccc='3'></name-panel>
""");
    _resolveSingleTemplate(dartSource);
    _assertElement("aaa=").input.at("aaa', ");
    _assertElement("bbb]=").input.at("bbb', ");
    _assertElement("ccc=").input.at("ccc']");
  }

  void test_outputReference() {
    _addDartSource(r'''
@Component(selector: 'name-panel',
    template: r"<div>AAA</div>")
class NamePanel {
  @Output() EventEmitter aaa;
  @Output() EventEmitter bbb;
  @Output() EventEmitter ccc;
}
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NamePanel])
class TestPanel {}
''');
    _addHtmlSource(r"""
<name-panel aaa='1' (bbb)='2' on-ccc='3'></name-panel>
""");
    _resolveSingleTemplate(dartSource);
    _assertElement("aaa=").output.at("aaa;");
    _assertElement("bbb)=").output.at("bbb;");
    _assertElement("ccc=").output.at("ccc;");
  }

  void test_twoWayReference() {
    _addDartSource(r'''
@Component(
    selector: 'name-panel',
@View(template: r"<div>AAA</div>")
class NamePanel {
  @Input() int value;
  @Output() EventEmitter<int> valueChange;
}
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NamePanel])
class TestPanel {
  int value;
}
''');
    _addHtmlSource(r"""
<name-panel [(value)]='value'></name-panel>
""");
    _resolveSingleTemplate(dartSource);
    _assertElement("value)]").input.at("value;");
  }

  void test_localVariable_camelCaseName() {
    _addDartSource(r'''
import 'dart:html';

@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {
  void handleClick(Element e) {}
}
''');
    _addHtmlSource(r"""
<h1 (click)='handleClick(myTargetElement)'>
  <div #myTargetElement></div>
</h1>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
    _assertElement("myTargetElement)").local.at("myTargetElement>");
  }

  void test_localVariable_exportAs() {
    _addDartSource(r'''
@Directive(selector: '[myDirective]', exportAs: 'exportedValue')
class MyDirective {
  String aaa; // 1
}

@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [MyDirective])
class TestPanel {}
''');
    _addHtmlSource(r"""
<div myDirective #value='exportedValue'>
  {{value.aaa}}
</div>
""");
    _resolveSingleTemplate(dartSource);
    _assertElement("myDirective #").selector.at("myDirective]");
    _assertElement("value=").local.declaration.type('MyDirective');
    _assertElement("exportedValue'>").angular.at("exportedValue')");
    _assertElement("value.aaa").local.at("value=");
    _assertElement("aaa}}").dart.getter.at('aaa; // 1');
  }

  void test_localVariable_exportAs_notFound() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {}
''');
    var code = r"""
<div #value='noSuchExportedValue'>
  {{value.aaa}}
  assertErrorInCodeAtPosition fails when it sees multiple errors.
  this shouldn't err because 'value' should be known as uncheckable.
</div>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.NO_DIRECTIVE_EXPORTED_BY_SPECIFIED_NAME,
        code,
        "noSuchExportedValue");
  }

  void test_localVariable_scope_forwardReference() {
    _addDartSource(r'''
import 'dart:html';

@Component(selector: 'aaa', inputs: const ['target'])
@View(template: '')
class ComponentA {
  void set target(ComponentB b) {}
}

@Component(selector: 'bbb')
@View(template: '')
class ComponentB {}

@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: [ComponentA, ComponentB])
class TestPanel {}
''');
    _addHtmlSource(r"""
<div>
  <aaa [target]='handle'></aaa>
  <bbb #handle></bbb>
</div>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
    _assertElement("handle'>").local.at("handle></bbb>").type('ComponentB');
  }

  void test_ngContent() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {}
''');
    _addHtmlSource(r"""
<ng-content></ng-content>>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
  }

  void test_ngFor_iterableElementType() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NgFor])
class TestPanel {
  MyIterable<String> items = new MyIterable<String>();
}
class BaseIterable<T> {
  Iterator<T> get iterator => <T>[].iterator;
}
class MyIterable<T> extends BaseIterable<T> {
}
''');
    _addHtmlSource(r"""
<li template='ngFor let item of items'>
  {{item.length}}
</li>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
    _assertElement("item.").local.at('item of').type('String');
    _assertElement("length}}").dart.getter;
  }

  void test_ngFor_operatorLocalVariable() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NgFor])
class TestPanel {
  List<String> operators = [];
}
''');
    _addHtmlSource(r"""
<li *ngFor='let operator of operators'>
  {{operator.length}}
</li>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
    expect(template.ranges, hasLength(7));
    _assertElement("ngFor=").selector.inFileName('ng_for.dart');
    _assertElement("operator of").local.declaration.type('String');
    _assertElement("length}}").dart.getter;
    errorListener.assertNoErrors();
  }

  void test_ngFor_operatorLocalVariableVarKeyword() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NgFor])
class TestPanel {
  List<String> operators = [];
}
''');
    _addHtmlSource(r"""
<li *ngFor='var operator of operators'>
  {{operator.length}}
</li>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
    expect(template.ranges, hasLength(7));
    _assertElement("ngFor=").selector.inFileName('ng_for.dart');
    _assertElement("operator of").local.declaration.type('String');
    _assertElement("length}}").dart.getter;
    errorListener.assertNoErrors();
  }

  void test_ngFor_star() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NgFor])
class TestPanel {
  List<String> items = [];
}
''');
    _addHtmlSource(r"""
<li *ngFor='let item of items; let i = index'>
  {{i}} {{item.length}}
</li>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
    expect(template.ranges, hasLength(10));
    _assertElement("ngFor=").selector.inFileName('ng_for.dart');
    _assertElement("item of").local.declaration.type('String');
    _assertSelectorElement("of items")
        .selector
        .name('ngForOf')
        .inFileName('ng_for.dart');
    _assertInputElement("of items")
        .input
        .name('ngForOf')
        .inFileName('ng_for.dart');
    _assertElement("items;").dart.getter.at('items = []');
    _assertElement("i = index").local.declaration.type('int');
    _assertElement("i}}").local.at('i = index');
    _assertElement("item.").local.at('item of');
    _assertElement("length}}").dart.getter;
  }

  void test_ngFor_noStarError() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NgFor])
class TestPanel {
  List<String> items = [];
}
''');
    var code = r"""
<li ngFor='let item of items; let i = index'>
</li>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.STRUCTURAL_DIRECTIVES_REQUIRE_TEMPLATE,
        code,
        "ngFor");
  }

  void test_ngFor_star_itemHiddenInElement() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NgFor])
class TestPanel {
  List<String> items = [];
}
''');
    _addHtmlSource(r"""
<h1 *ngFor='let item of items' [hidden]='item == null'>
</h1>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
    _assertElement("item == null").local.at('item of items');
  }

  void test_ngFor_templateAttribute() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NgFor])
class TestPanel {
  List<String> items = [];
}
''');
    _addHtmlSource(r"""
<li template='ngFor let item of items; let i = index'>
  {{i}} {{item.length}}
</li>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
    _assertElement("ngFor let").selector.inFileName('ng_for.dart');
    _assertElement("item of").local.declaration.type('String');
    _assertSelectorElement("of items")
        .selector
        .name('ngForOf')
        .inFileName('ng_for.dart');
    _assertInputElement("of items")
        .input
        .name('ngForOf')
        .inFileName('ng_for.dart');
    _assertElement("items;").dart.getter.at('items = []');
    _assertElement("i = index").local.declaration.type('int');
    _assertElement("i}}").local.at('i = index');
    _assertElement("item.").local.at('item of');
    _assertElement("length}}").dart.getter;
  }

  void test_ngFor_templateAttribute2() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NgFor])
class TestPanel {
  List<String> items = [];
}
''');
    _addHtmlSource(r"""
<li template='ngFor: let item, of = items, let i=index'>
  {{i}} {{item.length}}
</li>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
    _assertElement("ngFor:").selector.inFileName('ng_for.dart');
    _assertElement("item, of").local.declaration.type('String');
    _assertSelectorElement("of = items,")
        .selector
        .name('ngForOf')
        .inFileName('ng_for.dart');
    _assertInputElement("of = items,")
        .input
        .name('ngForOf')
        .inFileName('ng_for.dart');
    _assertElement("items,").dart.getter.at('items = []');
    _assertElement("i=index").local.declaration.type('int');
    _assertElement("i}}").local.at('i=index');
    _assertElement("item.").local.at('item, of');
    _assertElement("length}}").dart.getter;
  }

  void test_ngFor_templateElement() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NgFor])
class TestPanel {
  List<String> items = [];
}
''');
    _addHtmlSource(r"""
<template ngFor let-item [ngForOf]='items' let-i='index'>
  <li>{{i}} {{item.length}}</li>
</template>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
    _assertElement("ngFor let").selector.inFileName('ng_for.dart');
    _assertElement("item [").local.declaration.type('String');
    _assertSelectorElement("ngForOf]")
        .selector
        .name('ngForOf')
        .inFileName('ng_for.dart');
    _assertInputElement("ngForOf]")
        .input
        .name('ngForOf')
        .inFileName('ng_for.dart');
    _assertElement("items'").dart.getter.at('items = []');
    _assertElement("i='index").local.declaration.type('int');
    _assertElement("i}}").local.at("i='index");
    _assertElement("item.").local.at('item [');
    _assertElement("length}}").dart.getter;
  }

  void test_ngFor_templateElementVar() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NgFor])
class TestPanel {
  List<String> items = [];
}
''');
    _addHtmlSource(r"""
<template ngFor var-item [ngForOf]='items' var-i='index'>
  <li>{{i}} {{item.length}}</li>
</template>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
    _assertElement("item [").local.declaration.type('String');
    _assertElement("i='index").local.declaration.type('int');
    _assertElement("i}}").local.at("i='index");
    _assertElement("item.").local.at('item [');
  }

  void test_ngFor_variousKinds_useLowerIdentifier() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NgFor])
class TestPanel {
  List<String> items = [];
}
''');
    _addHtmlSource(r"""
<template ngFor let-item1 [ngForOf]='items' let-i='index' {{lowerEl}}>
  {{item1.length}}
</template>
<li template="ngFor let item2 of items; let i=index" {{lowerEl}}>
  {{item2.length}}
</li>
<li *ngFor="let item3 of items; let i=index" {{lowerEl}}>
  {{item3.length}}
</li>
<div #lowerEl></div>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
  }

  void test_ngForSugar_dartExpression() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NgFor])
class TestPanel {
  List<String> getItems(int unused) => [];
  int unused;
}
''');
    _addHtmlSource(r"""
<li template="ngFor let item1 of getItems(unused + 5); let i=index">
  {{item1.length}}
</li>
<li *ngFor="let item2 of getItems(unused + 5); let i=index">
  {{item2.length}}
</li>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
  }

  void test_ngIf_star() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NgIf])
class TestPanel {
  String text; // 1
}
''');
    _addHtmlSource(r"""
<span *ngIf='text.length != 0'>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
    _assertSelectorElement("ngIf=").selector.inFileName('ng_if.dart');
    _assertInputElement("ngIf=").input.inFileName('ng_if.dart');
    _assertElement("text.").dart.getter.at('text; // 1');
    _assertElement("length != 0").dart.getter;
  }

  void test_ngIf_noStarError() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NgIf])
class TestPanel {
  String text; // 1
}
''');
    var code = r"""
<span ngIf='text.length != 0'>
""";
    _addHtmlSource(code);
    _resolveSingleTemplate(dartSource);
    assertErrorInCodeAtPosition(
        AngularWarningCode.STRUCTURAL_DIRECTIVES_REQUIRE_TEMPLATE,
        code,
        "ngIf");
  }

  void test_ngIf_templateAttribute() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NgIf])
class TestPanel {
  String text; // 1
}
''');
    _addHtmlSource(r"""
<span template='ngIf text.length != 0'>
""");
    _resolveSingleTemplate(dartSource);
    errorListener.assertNoErrors();
    _assertSelectorElement("ngIf text").selector.inFileName('ng_if.dart');
    _assertInputElement("ngIf text").input.inFileName('ng_if.dart');
    _assertElement("text.").dart.getter.at('text; // 1');
    _assertElement("length != 0").dart.getter;
  }

  void test_ngIf_templateElement() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html', directives: const [NgIf])
class TestPanel {
  String text; // 1
}
''');
    _addHtmlSource(r"""
<template [ngIf]='text.length != 0'></template>
""");
    _resolveSingleTemplate(dartSource);
    _assertSelectorElement("ngIf]").selector.inFileName('ng_if.dart');
    _assertInputElement("ngIf]").input.inFileName('ng_if.dart');
    _assertElement("text.").dart.getter.at('text; // 1');
    _assertElement("length != 0").dart.getter;
  }

  void test_standardHtmlComponent() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {
  void inputChange(String value, String validationMessage) {}
}
''');
    _addHtmlSource(r"""
<input #inputEl M
       (change)='inputChange(inputEl.value, inputEl.validationMessage)'>
""");
    _resolveSingleTemplate(dartSource);
    _assertElement('input #').selector.inCoreHtml.at('input");');
    _assertElement('inputEl M').local.at('inputEl M');
    _assertElement('inputChange(inputEl').dart.method.at('inputChange(Str');
    _assertElement('inputEl.value').local.at('inputEl M');
    _assertElement('value, ').dart.getter.inCoreHtml;
    _assertElement('inputEl.validationMessage').local.at('inputEl M');
    _assertElement('validationMessage)').dart.getter.inCoreHtml;
    _assertElement('change)').output.inCoreHtml;
    errorListener.assertNoErrors();
    expect(ranges, hasLength(8));
  }

  void test_standardHtmlComponentUsingRef() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {
  void inputChange(String value, String validationMessage) {}
}
''');
    _addHtmlSource(r"""
<input ref-inputEl M
       (change)='inputChange(inputEl.value, inputEl.validationMessage)'>
""");
    _resolveSingleTemplate(dartSource);
    _assertElement('input ref').selector.inCoreHtml.at('input");');
    _assertElement('inputEl M').local.at('inputEl M');
    _assertElement('inputChange(inputEl').dart.method.at('inputChange(Str');
    _assertElement('inputEl.value').local.at('inputEl M');
    _assertElement('value, ').dart.getter.inCoreHtml;
    _assertElement('inputEl.validationMessage').local.at('inputEl M');
    _assertElement('validationMessage)').dart.getter.inCoreHtml;
    _assertElement('change)').output.inCoreHtml;
    errorListener.assertNoErrors();
    expect(ranges, hasLength(8));
  }

  void test_template_attribute_withoutValue() {
    _addDartSource(r'''
@Directive(selector: '[deferred-content]')
class DeferredContentDirective {}

@Component(selector: 'test-panel')
@View(
    templateUrl: 'test_panel.html',
    directives: const [DeferredContentDirective])
class TestPanel {}
''');
    _addHtmlSource(r"""
<div *deferred-content>Deferred content</div>
""");
    _resolveSingleTemplate(dartSource);
    _assertElement('deferred-content>').selector.at("deferred-content]')");
  }

  void test_textInterpolation() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {
  String aaa; // 1
  String bbb; // 2
}
''');
    _addHtmlSource(r"""
<div>
  Hello {{aaa}} and {{bbb}}!
</div>
""");
    _resolveSingleTemplate(dartSource);
    expect(ranges, hasLength(2));
    _assertElement('aaa}}').dart.getter.at('aaa; // 1');
    _assertElement('bbb}}').dart.getter.at('bbb; // 2');
  }

  // see https://github.com/dart-lang/html/issues/44
  void test_catchPkgHtmlGithubBug44() {
    _addDartSource(r'''
@Component(selector: 'test-panel')
@View(templateUrl: 'test_panel.html')
class TestPanel {
  String aaa; // 1
  String bbb; // 2
}
''');
    _addHtmlSource(r"""<button attr<="value"></button>""");
    _resolveSingleTemplate(dartSource);

    // no assertion...this throws in the github bug
  }

  void _addDartSource(String code) {
    dartCode = '''
import '/angular2/angular2.dart';
$code
''';
    dartSource = newSource('/test_panel.dart', dartCode);
  }

  void _addHtmlSource(String code) {
    htmlCode = code;
    htmlSource = newSource('/test_panel.html', htmlCode);
  }

  ElementAssert _assertElement(String atString,
      [ResolvedRangeCondition condition]) {
    ResolvedRange resolvedRange = _findResolvedRange(atString, condition);
    return new ElementAssert(context, dartCode, dartSource, htmlCode,
        htmlSource, resolvedRange.element, resolvedRange.range.offset);
  }

  ElementAssert _assertInputElement(String atString) {
    return _assertElement(atString, _isInputElement);
  }

  ElementAssert _assertSelectorElement(String atString) {
    return _assertElement(atString, _isSelectorName);
  }

  /**
   * Return the [ResolvedRange] that starts at the position of the give
   * [search] and, if specified satisfies the given [condition].
   */
  ResolvedRange _findResolvedRange(String search,
      [ResolvedRangeCondition condition]) {
    return getResolvedRangeAtString(htmlCode, ranges, search, condition);
  }

  /**
   * Compute all the views declared in the given [dartSource], and resolve the
   * external template of the last one.
   */
  void _resolveSingleTemplate(Source dartSource) {
    directives = computeLibraryDirectives(dartSource);
    List<View> views = computeLibraryViews(dartSource);
    View view = views.last;
    // resolve this View
    computeResult(view, HTML_TEMPLATE);
    template = outputs[HTML_TEMPLATE];
    ranges = template.ranges;
    fillErrorListener(HTML_TEMPLATE_ERRORS);
  }

  static bool _isInputElement(ResolvedRange region) {
    return region.element is InputElement;
  }

  static bool _isSelectorName(ResolvedRange region) {
    return region.element is SelectorName;
  }
}
