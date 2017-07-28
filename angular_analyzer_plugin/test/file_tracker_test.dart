import 'package:angular_analyzer_plugin/src/file_tracker.dart';
import 'package:front_end/src/base/api_signature.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:test/test.dart';
import 'package:mockito/mockito.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(FileTrackerTest);
  });
}

@reflectiveTest
class FileTrackerTest {
  FileTracker _fileTracker;
  _FileHasherMock _fileHasher;

  void setUp() {
    _fileHasher = new _FileHasherMock();
    _fileTracker = new FileTracker(_fileHasher);
  }

  // ignore: non_constant_identifier_names
  void test_dartHasTemplate() {
    _fileTracker.setDartHtmlTemplates("foo.dart", ["foo.html"]);
    expect(_fileTracker.getHtmlPathsReferencedByDart("foo.dart"),
        equals(["foo.html"]));
  }

  // ignore: non_constant_identifier_names
  void test_dartHasTemplates() {
    _fileTracker.setDartHtmlTemplates("foo.dart", ["foo.html", "foo_bar.html"]);
    expect(_fileTracker.getHtmlPathsReferencedByDart("foo.dart"),
        equals(["foo.html", "foo_bar.html"]));
  }

  // ignore: non_constant_identifier_names
  void test_templateHasDart() {
    _fileTracker.setDartHtmlTemplates("foo.dart", ["foo.html"]);
    expect(_fileTracker.getDartPathsReferencingHtml("foo.html"),
        equals(["foo.dart"]));
  }

  // ignore: non_constant_identifier_names
  void test_notReferencedDart() {
    expect(_fileTracker.getDartPathsReferencingHtml("foo.html"), equals([]));
  }

  // ignore: non_constant_identifier_names
  void test_notReferencedHtml() {
    expect(_fileTracker.getDartPathsReferencingHtml("foo.dart"), equals([]));
  }

  // ignore: non_constant_identifier_names
  void test_templatesHaveDart() {
    _fileTracker
      ..setDartHtmlTemplates("foo.dart", ["foo.html"])
      ..setDartHtmlTemplates("foo_test.dart", ["foo.html"]);
    expect(_fileTracker.getDartPathsReferencingHtml("foo.html"),
        equals(["foo.dart", "foo_test.dart"]));
  }

  // ignore: non_constant_identifier_names
  void test_templatesHaveDartRepeated() {
    _fileTracker
      ..setDartHtmlTemplates("foo.dart", ["foo.html"])
      ..setDartHtmlTemplates("foo_test.dart", ["foo.html"])
      ..setDartHtmlTemplates("foo.dart", ["foo.html"]);
    expect(_fileTracker.getDartPathsReferencingHtml("foo.html"),
        equals(["foo.dart", "foo_test.dart"]));
  }

  // ignore: non_constant_identifier_names
  void test_templatesHaveDartRemove() {
    _fileTracker
      ..setDartHtmlTemplates("foo_test.dart", ["foo.html"])
      ..setDartHtmlTemplates("foo.dart", ["foo.html"])
      ..setDartHtmlTemplates("foo_test.dart", []);
    expect(_fileTracker.getDartPathsReferencingHtml("foo.html"),
        equals(["foo.dart"]));
  }

  // ignore: non_constant_identifier_names
  void test_templatesHaveDartComplex() {
    _fileTracker
      ..setDartHtmlTemplates("foo.dart", ["foo.html", "foo_b.html"])
      ..setDartHtmlTemplates("foo_test.dart", ["foo.html", "foo_b.html"])
      ..setDartHtmlTemplates("unrelated.dart", ["unrelated.html"]);
    expect(_fileTracker.getDartPathsReferencingHtml("foo.html"),
        equals(["foo.dart", "foo_test.dart"]));
    expect(_fileTracker.getDartPathsReferencingHtml("foo_b.html"),
        equals(["foo.dart", "foo_test.dart"]));

    _fileTracker.setDartHtmlTemplates("foo_test.dart", ["foo_b.html"]);
    expect(_fileTracker.getDartPathsReferencingHtml("foo.html"),
        equals(["foo.dart"]));
    expect(_fileTracker.getDartPathsReferencingHtml("foo_b.html"),
        equals(["foo.dart", "foo_test.dart"]));

    _fileTracker.setDartHtmlTemplates("foo_test.dart", ["foo.html"]);
    expect(_fileTracker.getDartPathsReferencingHtml("foo.html"),
        equals(["foo.dart", "foo_test.dart"]));
    expect(_fileTracker.getDartPathsReferencingHtml("foo_b.html"),
        equals(["foo.dart"]));

    _fileTracker
        .setDartHtmlTemplates("foo_test.dart", ["foo.html", "foo_test.html"]);
    expect(_fileTracker.getDartPathsReferencingHtml("foo.html"),
        equals(["foo.dart", "foo_test.dart"]));
    expect(_fileTracker.getDartPathsReferencingHtml("foo_b.html"),
        equals(["foo.dart"]));
    expect(_fileTracker.getDartPathsReferencingHtml("foo_test.html"),
        equals(["foo_test.dart"]));

    _fileTracker
      ..setDartHtmlTemplates("foo.dart", ["foo.html"])
      ..setDartHtmlTemplates("foo_b.dart", ["foo_b.html"]);
    expect(_fileTracker.getDartPathsReferencingHtml("foo.html"),
        equals(["foo.dart", "foo_test.dart"]));
    expect(_fileTracker.getDartPathsReferencingHtml("foo_b.html"),
        equals(["foo_b.dart"]));
    expect(_fileTracker.getDartPathsReferencingHtml("foo_test.html"),
        equals(["foo_test.dart"]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlHasHtmlEmpty() {
    expect(_fileTracker.getHtmlPathsReferencingHtml("foo.html"), equals([]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlHasHtmlEmptyNoImportedDart() {
    _fileTracker.setDartHtmlTemplates("foo.dart", ["foo.html"]);
    expect(_fileTracker.getHtmlPathsReferencingHtml("foo.html"), equals([]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlHasHtmlEmptyNoHtml() {
    _fileTracker
      ..setDartHtmlTemplates("foo.dart", [])
      ..setDartImports("foo.dart", ["bar.dart"])
      ..setDartHtmlTemplates("bar.dart", ["bar.html"]);
    expect(_fileTracker.getHtmlPathsReferencingHtml("bar.html"), equals([]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlHasHtml() {
    _fileTracker
      ..setDartHtmlTemplates("foo.dart", ["foo.html"])
      ..setDartImports("foo.dart", ["bar.dart"])
      ..setDartHtmlTemplates("bar.dart", ["bar.html"]);
    expect(_fileTracker.getHtmlPathsReferencingHtml("bar.html"),
        equals(["foo.html"]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlHasHtmlMultipleResults() {
    _fileTracker
      ..setDartHtmlTemplates("foo.dart", ["foo.html", "foo_b.html"])
      ..setDartImports("foo.dart", ["bar.dart", "baz.dart"])
      ..setDartHtmlTemplates("bar.dart", ["bar.html"])
      ..setDartHtmlTemplates("baz.dart", ["baz.html", "baz_b.html"]);
    expect(_fileTracker.getHtmlPathsReferencingHtml("bar.html"),
        equals(["foo.html", "foo_b.html"]));
    expect(_fileTracker.getHtmlPathsReferencingHtml("baz.html"),
        equals(["foo.html", "foo_b.html"]));
    expect(_fileTracker.getHtmlPathsReferencingHtml("baz_b.html"),
        equals(["foo.html", "foo_b.html"]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlHasHtmlButNotGrandchildren() {
    _fileTracker
      ..setDartHtmlTemplates("foo.dart", ["foo.html"])
      ..setDartImports("foo.dart", ["child.dart"])
      ..setDartHtmlTemplates("child.dart", ["child.html"])
      ..setDartImports("child.dart", ["grandchild.dart"])
      ..setDartHtmlTemplates("grandchild.dart", ["grandchild.html"]);
    expect(_fileTracker.getHtmlPathsReferencingHtml("child.html"),
        equals(["foo.html"]));
    expect(_fileTracker.getHtmlPathsReferencingHtml("grandchild.html"),
        equals(["child.html"]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlHasDartEmpty() {
    expect(_fileTracker.getDartPathsAffectedByHtml("foo.html"), equals([]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlHasDartEmptyNoImportedDart() {
    _fileTracker.setDartHtmlTemplates("foo.dart", ["foo.html"]);
    expect(_fileTracker.getDartPathsAffectedByHtml("foo.html"), equals([]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlHasDartEmptyNotDartTemplate() {
    _fileTracker
      ..setDartImports("foo.dart", ["bar.dart"])
      ..setDartHtmlTemplates("bar.dart", ["bar.html"]);
    expect(_fileTracker.getDartPathsAffectedByHtml("bar.html"), equals([]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlHasDart() {
    _fileTracker
      ..setDartHasTemplate("foo.dart", true)
      ..setDartImports("foo.dart", ["bar.dart"])
      ..setDartHtmlTemplates("bar.dart", ["bar.html"]);
    expect(_fileTracker.getDartPathsAffectedByHtml("bar.html"),
        equals(["foo.dart"]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlAffectingDartEmpty() {
    expect(_fileTracker.getHtmlPathsAffectingDart("foo.dart"), equals([]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlAffectingDartEmptyNoImportedDart() {
    _fileTracker.setDartHtmlTemplates("foo.dart", ["foo.html"]);
    expect(_fileTracker.getHtmlPathsAffectingDart("foo.dart"), equals([]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlAffectingDartEmptyNotDartTemplate() {
    _fileTracker
      ..setDartImports("foo.dart", ["bar.dart"])
      ..setDartHtmlTemplates("bar.dart", ["bar.html"]);
    expect(_fileTracker.getHtmlPathsAffectingDart("foo.dart"), equals([]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlAffectingDart() {
    _fileTracker
      ..setDartHasTemplate("foo.dart", true)
      ..setDartImports("foo.dart", ["bar.dart"])
      ..setDartHtmlTemplates("bar.dart", ["bar.html"]);
    expect(_fileTracker.getHtmlPathsAffectingDart("foo.dart"),
        equals(["bar.html"]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlHasDartNotGrandchildren() {
    _fileTracker
      ..setDartHasTemplate("foo.dart", true)
      ..setDartImports("foo.dart", ["child.dart"])
      ..setDartHtmlTemplates("child.dart", ["child.html"])
      ..setDartImports("child.dart", ["grandchild.dart"])
      ..setDartHtmlTemplates("grandchild.dart", ["grandchild.html"]);
    expect(_fileTracker.getDartPathsAffectedByHtml("child.html"),
        equals(["foo.dart"]));
    expect(
        _fileTracker.getDartPathsAffectedByHtml("grandchild.html"), equals([]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlHasDartMultiple() {
    _fileTracker
      ..setDartHasTemplate("foo.dart", true)
      ..setDartImports("foo.dart", ["bar.dart", "baz.dart"])
      ..setDartHtmlTemplates("bar.dart", ["bar.html", "bar_b.html"])
      ..setDartHtmlTemplates("baz.dart", ["baz.html", "baz_b.html"]);
    expect(_fileTracker.getDartPathsAffectedByHtml("bar.html"),
        equals(["foo.dart"]));
    expect(_fileTracker.getDartPathsAffectedByHtml("bar_b.html"),
        equals(["foo.dart"]));
    expect(_fileTracker.getDartPathsAffectedByHtml("baz.html"),
        equals(["foo.dart"]));
    expect(_fileTracker.getDartPathsAffectedByHtml("baz_b.html"),
        equals(["foo.dart"]));
  }

  // ignore: non_constant_identifier_names
  void test_htmlHasDartGetSignature() {
    _fileTracker
      ..setDartHasTemplate("foo.dart", true)
      ..setDartImports("foo.dart", ["bar.dart"])
      ..setDartHtmlTemplates("bar.dart", ["bar.html"]);

    final fooDartElementSignature = new ApiSignature()..addInt(1);
    final barHtmlSignature = new ApiSignature()..addInt(2);

    when(_fileHasher.getContentHash("bar.html")).thenReturn(barHtmlSignature);
    when(_fileHasher.getUnitElementHash("foo.dart"))
        .thenReturn(fooDartElementSignature);

    final expectedSignature = new ApiSignature()
      ..addInt(FileTracker.salt)
      ..addBytes(fooDartElementSignature.toByteList())
      ..addBytes(barHtmlSignature.toByteList());

    expect(_fileTracker.getDartSignature("foo.dart").toHex(),
        equals(expectedSignature.toHex()));
  }

  // ignore: non_constant_identifier_names
  void test_htmlHasHtmlGetSignature() {
    _fileTracker
      ..setDartHtmlTemplates("foo.dart", ["foo.html"])
      ..setDartHtmlTemplates("foo_test.dart", ["foo.html"])
      ..setDartImports("foo.dart", ["bar.dart"])
      ..setDartHtmlTemplates("bar.dart", ["bar.html"]);

    final fooHtmlSignature = new ApiSignature()..addInt(1);
    final fooDartElementSignature = new ApiSignature()..addInt(2);
    final fooTestDartElementSignature = new ApiSignature()..addInt(3);
    final barHtmlSignature = new ApiSignature()..addInt(4);

    when(_fileHasher.getContentHash("foo.html")).thenReturn(fooHtmlSignature);
    when(_fileHasher.getContentHash("bar.html")).thenReturn(barHtmlSignature);
    when(_fileHasher.getUnitElementHash("foo.dart"))
        .thenReturn(fooDartElementSignature);
    when(_fileHasher.getUnitElementHash("foo_test.dart"))
        .thenReturn(fooTestDartElementSignature);

    final expectedSignature = new ApiSignature()
      ..addInt(FileTracker.salt)
      ..addBytes(fooHtmlSignature.toByteList())
      ..addBytes(fooDartElementSignature.toByteList())
      ..addBytes(barHtmlSignature.toByteList())
      ..addBytes(fooTestDartElementSignature.toByteList());

    expect(_fileTracker.getHtmlSignature("foo.html").toHex(),
        equals(expectedSignature.toHex()));
  }

  // ignore: non_constant_identifier_names
  void test_minimallyRehashesHtml() {
    final fooHtmlSignature = new ApiSignature()..addInt(1);
    when(_fileHasher.getContentHash("foo.html")).thenReturn(fooHtmlSignature);

    for (var i = 0; i < 3; ++i) {
      _fileTracker.getContentSignature("foo.html");
      verify(_fileHasher.getContentHash("foo.html")).called(0);
    }

    _fileTracker.rehashContents("foo.html");

    for (var i = 0; i < 3; ++i) {
      _fileTracker.getContentSignature("foo.html");
      verify(_fileHasher.getContentHash("foo.html")).called(2);
    }
  }

  // ignore: non_constant_identifier_names
  void test_getContentHashIsSalted() {
    final fooHtmlSignature = new ApiSignature()..addInt(1);
    final expectedSignature = new ApiSignature()
      ..addInt(FileTracker.salt)
      ..addBytes(fooHtmlSignature.toByteList());
    when(_fileHasher.getContentHash("foo.html")).thenReturn(fooHtmlSignature);
    expect(_fileTracker.getContentSignature("foo.html").toHex(),
        equals(expectedSignature.toHex()));
  }

  // ignore: non_constant_identifier_names
  void test_getUnitElementSignatureIsSalted() {
    final fooDartElementSignature = new ApiSignature()..addInt(1);
    final expectedSignature = new ApiSignature()
      ..addInt(FileTracker.salt)
      ..addBytes(fooDartElementSignature.toByteList());
    when(_fileHasher.getUnitElementHash("foo.dart"))
        .thenReturn(fooDartElementSignature);
    expect(_fileTracker.getUnitElementSignature("foo.dart").toHex(),
        equals(expectedSignature.toHex()));
  }
}

class _FileHasherMock extends Mock implements FileHasher {}
