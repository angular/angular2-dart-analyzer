import 'package:analysis_server/src/provisional/completion/completion_core.dart';
import 'package:analysis_server/src/provisional/completion/dart/completion_dart.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/task/dart.dart';
import 'package:angular_analyzer_server_plugin/src/completion.dart';
import 'package:angular_analyzer_plugin/src/tasks.dart';
import 'package:unittest/unittest.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'completion_contributor_test_util.dart';

main() {
  groupSep = ' | ';
  defineReflectiveTests(DartCompletionContributorTest);
  defineReflectiveTests(HtmlCompletionContributorTest);
}

@reflectiveTest
class DartCompletionContributorTest
    extends AbstractDartCompletionContributorTest {
  @override
  setUp() {
    testFile = '/completionTest.dart';
    super.setUp();
  }

  @override
  DartCompletionContributor createContributor() {
    return new AngularDartCompletionContributor();
  }

  test_completeMemberInMustache() async {
    addTestSource('''
import '/angular2/angular2.dart';
@Component(template: '{{^}}', selector: 'a')
class MyComp {
  String text;
}
    ''');

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestGetter('text', 'String');
  }

  test_completeMemberInInputBinding() async {
    addTestSource('''
import '/angular2/angular2.dart';
@Component(template: '<h1 [hidden]="^"></h1>', selector: 'a')
class MyComp {
  String text;
}
    ''');

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestGetter('text', 'String');
  }

  test_completeMemberInClassBinding() async {
    addTestSource('''
import '/angular2/angular2.dart';
@Component(template: '<h1 [class.my-class]="^"></h1>', selector: 'a')
class MyComp {
  String text;
}
    ''');

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestGetter('text', 'String');
  }

  test_completeMemberInStyleBinding() async {
    addTestSource('''
import '/angular2/angular2.dart';
@Component(template: '<h1 [style.background-color]="^"></h1>', selector: 'a')
class MyComp {
  String text;
}
    ''');

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestGetter('text', 'String');
  }

  test_completeMemberInAttrBinding() async {
    addTestSource('''
import '/angular2/angular2.dart';
@Component(template: '<h1 [attr.on-click]="^"></h1>', selector: 'a')
class MyComp {
  String text;
}
    ''');

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestGetter('text', 'String');
  }

  test_completeMemberMustacheAttrBinding() async {
    addTestSource('''
import '/angular2/angular2.dart';
@Component(template: '<h1 title="{{^}}"></h1>', selector: 'a')
class MyComp {
  String text;
}
    ''');

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestGetter('text', 'String');
  }

  test_completeMultipleMembers() async {
    addTestSource('''
import '/angular2/angular2.dart';
@Component(template: '{{d^}}', selector: 'a')
class MyComp {
  String text;
  String description;
}
    ''');

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestGetter('text', 'String');
    assertSuggestGetter('description', 'String');
  }

  test_completeInlineHtmlSelectorTag_at_beginning() async{
    addTestSource('''
import '/angular2/angular2.dart';
@Component(template: '<^<div></div>', selector: 'my-parent', directives: const[MyChildComponent])
class MyParentComponent{}
@Component(template: '', selector: 'my-child')
class MyChildComponent{}
    ''');

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("my-child");
  }

  test_completeInlineHtmlSelectorTag_at_beginning_with_partial() async{
    addTestSource('''
import '/angular2/angular2.dart';
@Component(template: '<my^<div></div>', selector: 'my-parent', directives: const[MyChildComponent])
class MyParentComponent{}
@Component(template: '', selector: 'my-child')
class MyChildComponent{}
    ''');

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("my-child");
  }

  test_completeInlineHtmlExportAsTag_at_beginning() async{
    addTestSource('''
import '/angular2/angular2.dart';
@Component(template: '<^<div></div>', selector: 'my-parent', directives: const[MyChildComponent])
class MyParentComponent{}
@Component(template: '', selector: 'my-child', exportAs: 'myChild')
class MyChildComponent{}
    ''');

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("myChild");
  }

  test_completeInlineHtmlSelectorTag_at_middle() async{
    addTestSource('''
import '/angular2/angular2.dart';
@Component(template: '<div><div><^</div></div>', selector: 'my-parent', directives: const[MyChildComponent])
class MyParentComponent{}
@Component(template: '', selector: 'my-child')
class MyChildComponent{}
    ''');

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("my-child");
  }

  test_completeInlineHtmlSelectorTag_at_middle_with_partial() async{
    addTestSource('''
import '/angular2/angular2.dart';
@Component(template: '<div><div><my^</div></div>', selector: 'my-parent', directives: const[MyChildComponent])
class MyParentComponent{}
@Component(template: '', selector: 'my-child')
class MyChildComponent{}
    ''');

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("my-child");
  }

  test_completeInlineHtmlExportAsTag_at_middle() async{
    addTestSource('''
import '/angular2/angular2.dart';
@Component(template: '<div><div><^</div></div>', selector: 'my-parent', directives: const[MyChildComponent])
class MyParentComponent{}
@Component(template: '', selector: 'my-child', exportAs: 'myChildAlias')
class MyChildComponent{}
    ''');

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("myChildAlias");
  }

  test_completeInlineHtmlSelectorTag_at_end() async{
    addTestSource('''
import '/angular2/angular2.dart';
@Component(template: '<div><div></div></div><^', selector: 'my-parent', directives: const[MyChildComponent])
class MyParentComponent{}
@Component(template: '', selector: 'my-child')
class MyChildComponent{}
    ''');

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("my-child");
  }

  test_completeInlineHtmlSelectorTag_at_end_with_partial() async{
    addTestSource('''
import '/angular2/angular2.dart';
@Component(template: '<div><div></div></div><m^', selector: 'my-parent', directives: const[MyChildComponent])
class MyParentComponent{}
@Component(template: '', selector: 'my-child')
class MyChildComponent{}
    ''');

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("my-child");
  }

  test_completeInlineHtmlExportAsTag_at_end() async{
    addTestSource('''
import '/angular2/angular2.dart';
@Component(template: '<div><div></div></div><^', selector: 'my-parent', directives: const[MyChildComponent])
class MyParentComponent{}
@Component(template: '', selector: 'my-child', exportAs: 'myChildAlias')
class MyChildComponent{}
    ''');

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("myChildAlias");
  }
}

@reflectiveTest
class HtmlCompletionContributorTest extends AbstractCompletionContributorTest {
  @override
  setUp() {
    testFile = '/completionTest.html';
    super.setUp();
  }

  @override
  CompletionContributor createContributor() {
    return new AngularTemplateCompletionContributor();
  }

  test_completeMemberInMustache() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a')
class MyComp {
  String text;
}
    ''');

    addTestSource('html file {{^}} with mustache');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestGetter('text', 'String');
    assertSuggestMethod('toString', 'Object', 'String');
    assertSuggestGetter('hashCode', 'int');
  }

  test_completeDotMemberInMustache() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a')
class MyComp {
  String text;
}
    ''');

    addTestSource('html file {{text.^}} with mustache');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestGetter('length', 'int');
  }

  test_completeDotMemberInNgFor() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a', directives: const [NgFor])
class MyComp {
  String text;
}
    ''');

    addTestSource('<div *ngFor="let item of text.^"></div>');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestGetter('length', 'int');
  }

  test_completeMemberInNgFor() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a', directives: const [NgFor])
class MyComp {
  String text;
}
    ''');

    addTestSource('<div *ngFor="let item of ^"></div>');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestGetter('text', 'String');
    assertSuggestMethod('toString', 'Object', 'String');
    assertSuggestGetter('hashCode', 'int');
  }

  test_completeNgForItem() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a', directives: const [NgFor])
class MyComp {
  List<String> items;
}
    ''');

    addTestSource('<div *ngFor="let item of items">{{^}}</div>');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestLocalVar('item', 'String');
  }

  test_completeHashVar() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a')
class MyComp {
}
    ''');

    addTestSource('<button #buttonEl>button</button> {{^}}');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestLocalVar('buttonEl', 'ButtonElement');
  }

  test_completeNgVars_notAfterDot() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a')
class MyComp {
  List<String> items;
}
    ''');

    addTestSource(
        '<button #buttonEl>button</button><div *ngFor="item of items">{{hashCode.^}}</div>');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertNotSuggested('buttonEl');
    assertNotSuggested('item');
  }

  test_findCompletionTarget_afterUnclosedDom() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a')
class MyComp {
  String text;
}
    ''');

    addTestSource('<input /> {{^}}');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestGetter('text', 'String');
  }

  test_completeStatements() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a')
class MyComp {
  String text;
}
    ''');

    addTestSource('<button (click)="^"></button>');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestLocalVar(r'$event', 'MouseEvent');
    assertSuggestField('text', 'String');
  }

  test_completeUnclosedMustache() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a')
class MyComp {
  String text;
}
    ''');

    addTestSource('some text and {{^   <div>some html</div>');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestGetter('text', 'String');
  }

  test_completeEmptyExpressionDoesntIncludeVoid() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a')
class MyComp {
  void dontCompleteMe() {}
}
    ''');

    addTestSource('{{^}}');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertNotSuggested("dontCompleteMe");
  }

  test_completeInMiddleOfExpressionDoesntIncludeVoid() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a')
class MyComp {
  bool takesArg(dynamic arg) {};
  void dontCompleteMe() {}
}
    ''');

    addTestSource('{{takesArg(^)}}');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertNotSuggested("dontCompleteMe");
  }

  test_completeInputOutput() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a',
    directives: const [OtherComp])
class MyComp {
}
@Component(template: '', selector: 'my-tag')
class OtherComp {
  @Input() String name;
  @Output() EventEmitter<String> nameEvent;
}
    ''');

    addTestSource('<my-tag ^></my-tag>');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestSetter("[name]");
    assertSuggestGetter("(nameEvent)", "String");
  }

  test_completeInputStarted() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a',
    directives: const [OtherComp])
class MyComp {
}
@Component(template: '', selector: 'my-tag')
class OtherComp {
  @Input() String name;
  @Output() EventEmitter<String> nameEvent;
}
    ''');

    addTestSource('<my-tag [^></my-tag>');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestSetter("[name]");
    assertNotSuggested("(nameEvent)");
  }

  test_completeInputReplacing() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a',
    directives: const [OtherComp])
class MyComp {
}
@Component(template: '', selector: 'my-tag')
class OtherComp {
  @Input() String name;
  @Output() EventEmitter<String> nameEvent;
}
    ''');

    addTestSource('<my-tag [^input]="4"></my-tag>');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestSetter("[name]");
    assertNotSuggested("(nameEvent)");
  }

  test_noCompleteInputInCloseTag() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a',
    directives: const [OtherComp])
class MyComp {
}
@Component(template: '', selector: 'my-tag')
class OtherComp {
  @Input() String name;
}
    ''');

    addTestSource('<my-tag></my-tag ^>');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertNotSuggested("[name]");
  }

  test_noCompleteEmptyTagContents() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a',
    directives: const [OtherComp])
class MyComp {
}
@Component(template: '', selector: 'my-tag')
class OtherComp {
  @Input() String name;
}
    ''');

    addTestSource('<my-tag>^</my-tag>');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertNotSuggested("[name]");
  }

  test_noCompleteInputsOnTagNameCompletion() async {
    Source dartSource = newSource(
        '/completionTest.dart',
        '''
import '/angular2/angular2.dart';
@Component(templateUrl: 'completionTest.html', selector: 'a',
    directives: const [OtherComp])
class MyComp {
}
@Component(template: '', selector: 'my-tag')
class OtherComp {
  @Input() String name;
}
    ''');

    addTestSource('<my-tag^></my-tag>');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertNotSuggested("[name]");
  }

  test_completeHtmlSelectorTag_at_beginning() async{
    Source dartSource = newSource('/completionTest.dart',
      '''
      import '/angular2/angular2.dart';
      @Component(templateUrl: 'completionTest.html', selector: 'a',
        directives: const [MyChildComponent])
        class MyComp{}
      @Component(template: '', selector: 'my-child-component')
      class MyChildComponent{}
      '''
    );
    addTestSource('<^<div></div>');
    LibrarySpecificUnit target =
        new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("my-child-component");
  }

  test_completeHtmlSelectorTag_at_beginning_with_partial() async{
    Source dartSource = newSource('/completionTest.dart',
        '''
      import '/angular2/angular2.dart';
      @Component(templateUrl: 'completionTest.html', selector: 'a',
        directives: const [MyChildComponent])
        class MyComp{}
      @Component(template: '', selector: 'my-child-component')
      class MyChildComponent{}
      '''
    );
    addTestSource('<my^<div></div>');
    LibrarySpecificUnit target =
    new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("my-child-component");
  }

  test_completeHtmlExportAsTag_at_beginning() async{
    Source dartSource = newSource('/completionTest.dart',
        '''
      import '/angular2/angular2.dart';
      @Component(templateUrl: 'completionTest.html', selector: 'a',
        directives: const [MyChildComponent])
        class MyComp{}
      @Component(template: '', selector: 'my-child-component', exportAs: 'myChildComponentAlias')
      class MyChildComponent{}
      '''
    );
    addTestSource('<^<div></div>');
    LibrarySpecificUnit target =
    new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("myChildComponentAlias");
  }

  test_completeHtmlSelectorTag_at_middle() async{
    Source dartSource = newSource('/completionTest.dart',
        '''
      import '/angular2/angular2.dart';
      @Component(templateUrl: 'completionTest.html', selector: 'a',
        directives: const [MyChildComponent])
        class MyComp{}
      @Component(template: '', selector: 'my-child-component')
      class MyChildComponent{}
      '''
    );
    addTestSource('''<div><div><^</div></div>''');
    LibrarySpecificUnit target =
    new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("my-child-component");
  }

  test_completeHtmlSelectorTag_at_middle_with_partial() async{
    Source dartSource = newSource('/completionTest.dart',
        '''
      import '/angular2/angular2.dart';
      @Component(templateUrl: 'completionTest.html', selector: 'a',
        directives: const [MyChildComponent])
        class MyComp{}
      @Component(template: '', selector: 'my-child-component')
      class MyChildComponent{}
      '''
    );
    addTestSource('''<div><div><my^</div></div>''');
    LibrarySpecificUnit target =
    new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("my-child-component");
  }

  test_completeHtmlExportAsTag_at_middle() async{
    Source dartSource = newSource('/completionTest.dart',
        '''
      import '/angular2/angular2.dart';
      @Component(templateUrl: 'completionTest.html', selector: 'a',
        directives: const [MyChildComponent])
        class MyComp{}
      @Component(template: '', selector: 'my-child-component', exportAs:'myChildComponentAlias')
      class MyChildComponent{}
      '''
    );
    addTestSource('''<div><div><^</div></div>''');
    LibrarySpecificUnit target =
    new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("myChildComponentAlias");
  }

  test_completeHtmlSelectorTag_at_end() async{
    Source dartSource = newSource('/completionTest.dart',
        '''
      import '/angular2/angular2.dart';
      @Component(templateUrl: 'completionTest.html', selector: 'a',
        directives: const [MyChildComponent])
        class MyComp{}
      @Component(template: '', selector: 'my-child-component')
      class MyChildComponent{}
      '''
    );
    addTestSource('''<div><div></div></div><^''');
    LibrarySpecificUnit target =
    new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("my-child-component");
  }

  test_completeHtmlSelectorTag_at_end_with_partial() async{
    Source dartSource = newSource('/completionTest.dart',
        '''
      import '/angular2/angular2.dart';
      @Component(templateUrl: 'completionTest.html', selector: 'a',
        directives: const [MyChildComponent])
        class MyComp{}
      @Component(template: '', selector: 'my-child-component')
      class MyChildComponent{}
      '''
    );
    addTestSource('''<div><div></div></div>
    <my^''');
    LibrarySpecificUnit target =
    new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("my-child-component");
  }

  test_completeHtmlExportAsTag_at_end() async{
    Source dartSource = newSource('/completionTest.dart',
        '''
      import '/angular2/angular2.dart';
      @Component(templateUrl: 'completionTest.html', selector: 'a',
        directives: const [MyChildComponent])
        class MyComp{}
      @Component(template: '', selector: 'my-child-component', exportAs:'myChildComponentAlias')
      class MyChildComponent{}
      '''
    );
    addTestSource('''<div><div></div></div><^''');
    LibrarySpecificUnit target =
    new LibrarySpecificUnit(dartSource, dartSource);
    computeResult(target, VIEWS_WITH_HTML_TEMPLATES);

    await computeSuggestions();
    expect(replacementOffset, completionOffset);
    expect(replacementLength, 0);
    assertSuggestClassTypeAlias("myChildComponentAlias");
  }
}
