import 'package:analyzer/src/summary/base.dart' as base;
import 'package:analyzer/src/summary/base.dart' show Id, TopLevel;

import 'format.dart' as generated;

@TopLevel('APdl')
abstract class PackageBundle extends base.SummaryClass {
  factory PackageBundle.fromBuffer(List<int> buffer) =>
      generated.readPackageBundle(buffer);

  @Id(0)
  List<UnlinkedDartSummary> get unlinkedDartSummary;
}

@TopLevel('APLH')
abstract class LinkedHtmlSummary extends base.SummaryClass {
  factory LinkedHtmlSummary.fromBuffer(List<int> buffer) =>
      generated.readLinkedHtmlSummary(buffer);

  @Id(0)
  List<SummarizedAnalysisError> get errors;
  @Id(1)
  List<SummarizedAnalysisErrorFromPath> get errorsFromPath;
}

@TopLevel('APUH')
abstract class UnlinkedHtmlSummary extends base.SummaryClass {
  factory UnlinkedHtmlSummary.fromBuffer(List<int> buffer) =>
      generated.readUnlinkedHtmlSummary(buffer);

  @Id(0)
  List<SummarizedNgContent> get ngContents;
}

@TopLevel('APLD')
abstract class LinkedDartSummary extends base.SummaryClass {
  factory LinkedDartSummary.fromBuffer(List<int> buffer) =>
      generated.readLinkedDartSummary(buffer);

  @Id(0)
  List<SummarizedAnalysisError> get errors;

  @Id(1)
  List<String> get referencedHtmlFiles;

  @Id(2)
  List<String> get referencedDartFiles;

  @Id(3)
  bool get hasDartTemplates;
}

@TopLevel('APUD')
abstract class UnlinkedDartSummary extends base.SummaryClass {
  factory UnlinkedDartSummary.fromBuffer(List<int> buffer) =>
      generated.readUnlinkedDartSummary(buffer);

  @Id(0)
  List<SummarizedDirective> get directiveSummaries;

  @Id(1)
  List<SummarizedAnalysisError> get errors;

  @Id(2)
  List<SummarizedPipe> get pipeSummaries;
}

abstract class SummarizedDirective extends base.SummaryClass {
  @Id(0)
  bool get isComponent;
  @Id(1)
  String get selectorStr;
  @Id(2)
  int get selectorOffset;
  @Id(3)
  String get decoratedClassName;
  @Id(4)
  String get exportAs;
  @Id(5)
  int get exportAsOffset;
  @Id(6)
  String get templateUrl;
  @Id(7)
  int get templateUrlOffset;
  @Id(8)
  int get templateUrlLength;
  @Id(9)
  String get templateText;
  @Id(10)
  int get templateOffset;
  @Id(11)
  List<SummarizedNgContent> get ngContents;
  @Id(12)
  List<SummarizedBindable> get inputs;
  @Id(13)
  List<SummarizedBindable> get outputs;
  @Id(14)
  List<SummarizedDirectiveUse> get subdirectives;
  @Id(15)
  List<SummarizedContentChildField> get contentChildFields;
  @Id(16)
  List<SummarizedContentChildField> get contentChildrenFields;
  @Id(17)
  List<SummarizedExportedIdentifier> get exports;
  @Id(18)
  List<SummarizedPipesUse> get pipesUse;
}

abstract class SummarizedPipe extends base.SummaryClass {
  @Id(0)
  String get pipeName;
  @Id(1)
  int get pipeNameOffset;
  @Id(2)
  bool get isPure;
  @Id(3)
  String get decoratedClassName;
}

abstract class SummarizedAnalysisError extends base.SummaryClass {
  @Id(0)
  String get errorCode;
  @Id(1)
  String get message;
  @Id(2)
  String get correction;
  @Id(3)
  int get offset;
  @Id(4)
  int get length;
}

abstract class SummarizedAnalysisErrorFromPath extends base.SummaryClass {
  @Id(0)
  String get path;
  @Id(1)
  SummarizedAnalysisError get originalError;
}

abstract class SummarizedBindable extends base.SummaryClass {
  @Id(0)
  String get name;
  @Id(1)
  int get nameOffset;
  @Id(2)
  String get propName;
  @Id(3)
  int get propNameOffset;
}

abstract class SummarizedDirectiveUse extends base.SummaryClass {
  @Id(0)
  String get name;
  @Id(1)
  String get prefix;
  @Id(2)
  int get offset;
  @Id(3)
  int get length;
}

abstract class SummarizedNgContent extends base.SummaryClass {
  @Id(0)
  int get offset;
  @Id(1)
  int get length;
  @Id(2)
  String get selectorStr;
  @Id(3)
  int get selectorOffset;
}

abstract class SummarizedContentChildField extends base.SummaryClass {
  @Id(0)
  String get fieldName;
  @Id(1)
  int get nameOffset;
  @Id(2)
  int get nameLength;
  @Id(3)
  int get typeOffset;
  @Id(4)
  int get typeLength;
}

abstract class SummarizedExportedIdentifier extends base.SummaryClass {
  @Id(0)
  String get name;
  @Id(1)
  String get prefix;
  @Id(2)
  int get offset;
  @Id(3)
  int get length;
}

abstract class SummarizedPipesUse extends base.SummaryClass {
  @Id(0)
  String get name;
  @Id(1)
  String get prefix;
  @Id(2)
  int get offset;
  @Id(3)
  int get length;
}
