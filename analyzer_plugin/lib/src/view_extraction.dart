import 'dart:collection';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:angular_analyzer_plugin/src/model.dart';
import 'package:angular_analyzer_plugin/tasks.dart';
import 'package:angular_analyzer_plugin/src/tasks.dart';
import 'package:analyzer/error/error.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html;
import 'package:angular_analyzer_plugin/src/angular_html_parser.dart';
import 'package:analyzer/src/error/codes.dart';

class ViewExtractor extends AnnotationProcessorMixin {
  AnalysisContext context;
  Source source;
  ast.CompilationUnit unit;
  List<AbstractDirective> directivesDefinedInFile;

  ViewExtractor(
      this.unit, this.directivesDefinedInFile, this.context, this.source);

  List<View> getViews() {
    initAnnotationProcessor(source);
    //
    // Prepare inputs.
    //

    //
    // Process all classes.
    //
    final views = <View>[];
    for (final unitMember in unit.declarations) {
      if (unitMember is ast.ClassDeclaration) {
        final classElement = unitMember.element;
        ast.Annotation viewAnnotation;
        ast.Annotation componentAnnotation;

        for (final annotation in unitMember.metadata) {
          if (isAngularAnnotation(annotation, 'View')) {
            viewAnnotation = annotation;
          } else if (isAngularAnnotation(annotation, 'Component')) {
            componentAnnotation = annotation;
          }
        }

        if (viewAnnotation == null && componentAnnotation == null) {
          continue;
        }

        //@TODO when there's both a @View and @Component, handle edge cases
        final view =
            _createView(classElement, viewAnnotation ?? componentAnnotation);

        if (view != null) {
          views.add(view);
        }
      }
    }

    return views;
  }

  /// Create a new [View] for the given [annotation], may return `null`
  /// if [annotation] or [classElement] don't provide enough information.
  View _createView(ClassElement classElement, ast.Annotation annotation) {
    // Template in a separate HTML file.
    Source templateUriSource;
    var definesTemplate = false;
    var definesTemplateUrl = false;
    SourceRange templateUrlRange;
    {
      // ignore: omit_local_variable_types
      final ast.Expression templateUrlExpression =
          getNamedArgument(annotation, 'templateUrl');
      definesTemplateUrl = templateUrlExpression != null;
      final templateUrl = getExpressionString(templateUrlExpression);
      if (templateUrl != null) {
        final sourceFactory = context.sourceFactory;
        templateUriSource = sourceFactory.resolveUri(source, templateUrl);

        if (templateUriSource == null || !templateUriSource.exists()) {
          errorReporter.reportErrorForNode(
              AngularWarningCode.REFERENCED_HTML_FILE_DOESNT_EXIST,
              templateUrlExpression);
        }

        templateUrlRange = new SourceRange(
            templateUrlExpression.offset, templateUrlExpression.length);
      }
    }
    // Try to find inline "template".
    String templateText;
    var templateOffset = 0;
    {
      // ignore: omit_local_variable_types
      final ast.Expression expression =
          getNamedArgument(annotation, 'template');
      if (expression != null) {
        templateOffset = expression.offset;
        definesTemplate = true;
        // ignore: omit_local_variable_types
        final OffsettingConstantEvaluator constantEvaluation =
            calculateStringWithOffsets(expression);

        // highly dynamically generated constant expressions can't be validated
        if (constantEvaluation == null ||
            !constantEvaluation.offsetsAreValid ||
            constantEvaluation.value is! String) {
          templateText = '';
        } else {
          templateText = constantEvaluation.value;
        }
      }
    }

    if (definesTemplate && definesTemplateUrl) {
      errorReporter.reportErrorForNode(
          AngularWarningCode.TEMPLATE_URL_AND_TEMPLATE_DEFINED, annotation);

      return null;
    }

    if (!definesTemplate && !definesTemplateUrl) {
      errorReporter.reportErrorForNode(
          AngularWarningCode.NO_TEMPLATE_URL_OR_TEMPLATE_DEFINED, annotation);

      return null;
    }

    // Find the corresponding Component.
    final component = _findComponentAnnotationOrReportError(classElement);
    if (component == null) {
      return null;
    }
    final directiveReferences = <DirectiveReference>[];
    findDirectives(annotation, directiveReferences);
    // Create View.
    return new View(classElement, component, <AbstractDirective>[],
        templateText: templateText,
        templateOffset: templateOffset,
        templateUriSource: templateUriSource,
        templateUrlRange: templateUrlRange,
        directiveReferences: directiveReferences,
        annotation: annotation);
  }

  Component _findComponentAnnotationOrReportError(ClassElement classElement) {
    for (final directive in directivesDefinedInFile) {
      if (directive is Component && directive.classElement == classElement) {
        return directive;
      }
    }
    errorReporter.reportErrorForElement(
        AngularWarningCode.COMPONENT_ANNOTATION_MISSING, classElement, []);
    return null;
  }

  void findDirectives(
      ast.Annotation annotation, List<DirectiveReference> directiveReferences) {
    // Prepare directives and elementTags
    // ignore: omit_local_variable_types
    final ast.Expression listExpression =
        getNamedArgument(annotation, 'directives');
    if (listExpression is ast.ListLiteral) {
      // ignore: omit_local_variable_types
      for (final ast.Expression item in listExpression.elements) {
        if (item is ast.Identifier) {
          final name = item.name;
          var prefix = "";
          if (item is ast.PrefixedIdentifier) {
            prefix = item.prefix.name;
          }
          final element = item.staticElement;
          // LIST_OF_DIRECTIVES or TypeLiteral
          if (element is ClassElement ||
              element is PropertyAccessorElement &&
                  element.variable.constantValue != null) {
            directiveReferences.add(new DirectiveReference(
                name, prefix, new SourceRange(item.offset, item.length)));
            continue;
          }
        }
        // unknown
        errorReporter.reportErrorForNode(
            AngularWarningCode.TYPE_LITERAL_EXPECTED, item);
      }
    }
  }
}

class TemplateParser {
  html.Document document;
  final parseErrors = <AnalysisError>[];

  void parse(String content, Source source, {int offset = 0}) {
    if (offset != null) {
      // ignore: prefer_interpolation_to_compose_strings, parameter_assignments
      content = ' ' * offset + content;
    }
    final parser = new AngularHtmlParser(content,
        generateSpans: true, lowercaseAttrName: false);
    parser.compatMode = 'quirks';
    document = parser.parse();

    final htmlErrors = parser.errors;

    for (final parseError in htmlErrors) {
      if (parseError.errorCode == 'expected-doctype-but-got-start-tag' ||
          parseError.errorCode == 'expected-doctype-but-got-chars' ||
          parseError.errorCode == 'expected-doctype-but-got-eof') {
        continue;
      }

      final span = parseError.span;
      // html parser lib isn't nice enough to send this error all the time
      // see github #47 for dart-lang/html
      if (span == null) continue;

      parseErrors.add(new AnalysisError(source, span.start.offset, span.length,
          HtmlErrorCode.PARSE_ERROR, [parseError.errorCode]));
    }
  }
}

void setIgnoredErrors(Template template, html.Document document) {
  if (document == null || document.nodes.isEmpty) {
    return;
  }
  // ignore: omit_local_variable_types
  final html.Node firstNode = document.nodes[0];
  if (firstNode is html.Comment) {
    var text = firstNode.text.trim();
    if (text.startsWith("@ngIgnoreErrors")) {
      text = text.substring("@ngIgnoreErrors".length);
      // Per spec: optional color
      if (text.startsWith(":")) {
        text = text.substring(1);
      }
      // Per spec: optional commas
      final delim = text.contains(',') ? ',' : ' ';
      template.ignoredErrors.addAll(new HashSet.from(
          text.split(delim).map((c) => c.trim().toUpperCase())));
    }
  }
}
