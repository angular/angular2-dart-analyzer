import 'dart:async';
import 'dart:collection';

import 'package:analysis_server/plugin/protocol/protocol.dart' as protocol
    show Element, ElementKind;
import 'package:analysis_server/src/provisional/completion/completion_core.dart';
import 'package:analysis_server/src/provisional/completion/dart/completion_dart.dart';
import 'package:analysis_server/src/services/completion/completion_core.dart';
import 'package:analysis_server/src/services/completion/dart/completion_manager.dart';
import 'package:analysis_server/src/services/completion/dart/optype.dart';
import 'package:analysis_server/src/services/completion/dart/type_member_contributor.dart';
import 'package:analysis_server/src/services/completion/dart/inherited_reference_contributor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/task/dart.dart';
import 'package:analyzer/task/model.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:angular_analyzer_plugin/src/converter.dart';
import 'package:angular_analyzer_plugin/src/model.dart';
import 'package:angular_analyzer_plugin/src/selector.dart';
import 'package:angular_analyzer_plugin/src/tasks.dart';
import 'package:angular_analyzer_plugin/ast.dart';

import 'package:analysis_server/src/protocol_server.dart'
    show CompletionSuggestion, CompletionSuggestionKind, Location;

import 'package:analysis_server/src/protocol_server.dart'
    show CompletionSuggestion;

import 'embedded_dart_completion_request.dart';

bool offsetContained(int offset, int start, int length) {
  return start <= offset && start + length >= offset;
}

AngularAstNode findTarget(int offset, AngularAstNode root) {
  for (AngularAstNode child in root.children) {
    if (child is ElementInfo) {
      if (child.isSynthetic) {
        var target = findTarget(offset, child);
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
  AstNode dartSnippet = null;
  int offset;

  @override
  visitDocumentInfo(DocumentInfo document) {}

  // don't recurse, findTarget already did that
  @override
  visitElementInfo(ElementInfo element) {}

  @override
  visitTextAttr(TextAttribute attr) {}

  @override
  visitExpressionBoundAttr(ExpressionBoundAttribute attr) {
    if (attr.expression != null &&
        offsetContained(
            offset, attr.expression.offset, attr.expression.length)) {
      dartSnippet = attr.expression;
    }
  }

  @override
  visitStatementsBoundAttr(StatementsBoundAttribute attr) {
    for (Statement statement in attr.statements) {
      if (offsetContained(offset, statement.offset, statement.length)) {
        dartSnippet = statement;
      }
    }
  }

  @override
  visitMustache(Mustache mustache) {
    if (offsetContained(offset, mustache.exprBegin,
            mustache.exprEnd - mustache.exprBegin)) {
      dartSnippet = mustache.expression;
    }
  }

  @override
  visitTemplateAttr(TemplateAttribute attr) {
    // if we visit this, we're in a template but after one of its attributes.
    AttributeInfo attributeToAppendTo;
    for (AttributeInfo subAttribute in attr.virtualAttributes) {
      if (subAttribute.valueOffset == null && subAttribute.offset < offset) {
        attributeToAppendTo = subAttribute;
      }
    }

    if (attributeToAppendTo != null &&
        attributeToAppendTo is TextAttribute &&
        !attributeToAppendTo.name.startsWith("let")) {
      AnalysisErrorListener analysisErrorListener =
          new IgnoringAnalysisErrorListener();
      EmbeddedDartParser dartParser =
          new EmbeddedDartParser(null, analysisErrorListener, null, null);
      dartSnippet = dartParser.parseDartExpression(offset, '', false);
    }
  }
}

class IgnoringAnalysisErrorListener implements AnalysisErrorListener {
  @override
  void onError(AnalysisError error) {}
}

class LocalVariablesExtractor extends AngularAstVisitor {
  Map<String, LocalVariable> variables = null;

  // don't recurse, findTarget already did that
  @override
  visitDocumentInfo(DocumentInfo document) {}
  @override
  visitElementInfo(ElementInfo element) {}
  @override
  visitTextAttr(TextAttribute attr) {}

  @override
  visitExpressionBoundAttr(ExpressionBoundAttribute attr) {
    variables = attr.localVariables;
  }

  @override
  visitStatementsBoundAttr(StatementsBoundAttribute attr) {
    variables = attr.localVariables;
  }

  @override
  visitMustache(Mustache mustache) {
    variables = mustache.localVariables;
  }
}

class ReplacementRangeCalculator extends AngularAstVisitor {
  CompletionRequestImpl request;

  ReplacementRangeCalculator(this.request);

  @override
  visitDocumentInfo(DocumentInfo document) {}

  // don't recurse, findTarget already did that
  @override
  visitElementInfo(ElementInfo element) {
    if (element.openingSpan == null) {
      return;
    }
    int nameSpanEnd =
        element.openingNameSpan.offset + element.openingNameSpan.length;
    if (offsetContained(request.offset, element.openingSpan.offset,
        nameSpanEnd - element.openingSpan.offset)) {
      request.replacementOffset = element.openingSpan.offset;
      request.replacementLength = element.localName.length + 1;
    }
  }

  @override
  visitTextAttr(TextAttribute attr) {}

  @override
  visitTextInfo(TextInfo textInfo) {
    if (request.offset > textInfo.offset &&
        textInfo.text[request.offset - textInfo.offset - 1] == '<') {
      request.replacementOffset--;
      request.replacementLength = 1;
    }
  }

  @override
  visitExpressionBoundAttr(ExpressionBoundAttribute attr) {
    if (offsetContained(
        request.offset, attr.originalNameOffset, attr.originalName.length)) {
      request.replacementOffset = attr.originalNameOffset;
      request.replacementLength = attr.originalName.length;
    }
  }

  @override
  visitStatementsBoundAttr(StatementsBoundAttribute attr) {
    if (offsetContained(
        request.offset, attr.originalNameOffset, attr.originalName.length)) {
      request.replacementOffset = attr.originalNameOffset;
      request.replacementLength = attr.originalName.length;
    }
  }

  @override
  visitMustache(Mustache mustache) {}
}

class AngularDartCompletionContributor extends CompletionContributor {
  /**
   * Return a [Future] that completes with a list of suggestions
   * for the given completion [request].
   */
  Future<List<CompletionSuggestion>> computeSuggestions(
      CompletionRequest request) async {
    if (!request.source.shortName.endsWith('.dart')) {
      return [];
    }

    List<Template> templates = request.context.computeResult(
        new LibrarySpecificUnit(request.source, request.source),
        DART_TEMPLATES);
    List<OutputElement> standardHtmlEvents = request.context
        .computeResult(
            AnalysisContextTarget.request, STANDARD_HTML_ELEMENT_EVENTS)
        .values;
    List<InputElement> standardHtmlAttributes = request.context
        .computeResult(
            AnalysisContextTarget.request, STANDARD_HTML_ELEMENT_ATTRIBUTES)
        .values;

    return new TemplateCompleter().computeSuggestions(
        request, templates, standardHtmlEvents, standardHtmlAttributes);
  }
}

class AngularTemplateCompletionContributor extends CompletionContributor {
  /**
   * Return a [Future] that completes with a list of suggestions
   * for the given completion [request]. This will
   * throw [AbortCompletion] if the completion request has been aborted.
   */
  Future<List<CompletionSuggestion>> computeSuggestions(
      CompletionRequest request) async {
    if (request.source.shortName.endsWith('.html')) {
      List<Template> templates =
          request.context.computeResult(request.source, HTML_TEMPLATES);
      List<OutputElement> standardHtmlEvents = request.context
          .computeResult(
              AnalysisContextTarget.request, STANDARD_HTML_ELEMENT_EVENTS)
          .values;
      List<InputElement> standardHtmlAttributes = request.context
          .computeResult(
              AnalysisContextTarget.request, STANDARD_HTML_ELEMENT_ATTRIBUTES)
          .values;

      return new TemplateCompleter().computeSuggestions(
          request, templates, standardHtmlEvents, standardHtmlAttributes);
    }

    return [];
  }
}

class TemplateCompleter {
  static const int RELEVANCE_TRANSCLUSION = DART_RELEVANCE_DEFAULT + 10;

  Future<List<CompletionSuggestion>> computeSuggestions(
      CompletionRequest request,
      List<Template> templates,
      List<OutputElement> standardHtmlEvents,
      List<InputElement> standardHtmlAttributes) async {
    var suggestions = <CompletionSuggestion>[];
    for (Template template in templates) {
      var target = findTarget(request.offset, template.ast);
      target.accept(new ReplacementRangeCalculator(request));
      var extractor = new DartSnippetExtractor();
      extractor.offset = request.offset;
      target.accept(extractor);

      // If [CompletionRequest] is in
      // [StatementsBoundAttribute],
      // [ExpressionsBoundAttribute],
      // [Mustache],
      // [TemplateAttribute].
      if (extractor.dartSnippet != null) {
        var dartRequest = new EmbeddedDartCompletionRequest.from(
            request, extractor.dartSnippet);
        var range = new ReplacementRange.compute(
            dartRequest.offset, dartRequest.target);
        (request as CompletionRequestImpl)
          ..replacementOffset = range.offset
          ..replacementLength = range.length;

        dartRequest.libraryElement = template.view.classElement.library;
        var memberContributor = new TypeMemberContributor();
        var inheritedContributor = new InheritedReferenceContributor();

        suggestions.addAll(
          inheritedContributor.computeSuggestionsForClass(
            template.view.classElement,
            dartRequest,
            skipChildClass: false,
          ),
        );
        suggestions
            .addAll(await memberContributor.computeSuggestions(dartRequest));

        if (dartRequest.opType.includeIdentifiers) {
          var varExtractor = new LocalVariablesExtractor();
          target.accept(varExtractor);
          if (varExtractor.variables != null) {
            addLocalVariables(
              suggestions,
              varExtractor.variables,
              dartRequest.opType,
            );
          }
        }
      } else if (target is ElementInfo) {
        if (target.closingSpan != null &&
            offsetContained(request.offset, target.closingSpan.offset,
                target.closingSpan.length)) {
          // In closing tag, but could be directly after it; ex: '</div>^'.
          if (request.offset ==
              (target.closingSpan.offset + target.closingSpan.length)) {
            suggestHtmlTags(template, suggestions);
            if (target.parent != null || target.parent is! DocumentInfo) {
              suggestTransclusions(target.parent, suggestions);
            }
          }
          // Directly within closing tag; suggest nothing. Ex: '</div^>'
          else
            continue;
        }
        if (!offsetContained(request.offset, target.openingNameSpan.offset,
            target.openingNameSpan.length)) {
          // If request is not in [openingNameSpan], suggest decorators.
          suggestInputs(target.boundDirectives, suggestions,
              standardHtmlAttributes, target.boundStandardInputs);
          suggestOutputs(target.boundDirectives, suggestions,
              standardHtmlEvents, target.boundStandardOutputs);
        } else {
          // Otherwise, suggest HTML tags and transclusions.
          suggestHtmlTags(template, suggestions);
          if (target.parent != null || target.parent is! DocumentInfo) {
            suggestTransclusions(target.parent, suggestions);
          }
        }
      } else if (target is ExpressionBoundAttribute &&
          target.bound == ExpressionBoundType.input &&
          offsetContained(request.offset, target.originalNameOffset,
              target.originalName.length)) {
        suggestInputs(target.parent.boundDirectives, suggestions,
            standardHtmlAttributes, target.parent.boundStandardInputs,
            currentAttr: target);
      } else if (target is StatementsBoundAttribute) {
        suggestOutputs(target.parent.boundDirectives, suggestions,
            standardHtmlEvents, target.parent.boundStandardOutputs,
            currentAttr: target);
      } else if (target is TemplateAttribute) {
        suggestInputs(target.parent.boundDirectives, suggestions,
            standardHtmlAttributes, target.parent.boundStandardInputs);
        suggestOutputs(target.parent.boundDirectives, suggestions,
            standardHtmlEvents, target.parent.boundStandardOutputs);
      } else if (target is TextAttribute) {
        suggestInputs(target.parent.boundDirectives, suggestions,
            standardHtmlAttributes, target.parent.boundStandardInputs);
        suggestOutputs(target.parent.boundDirectives, suggestions,
            standardHtmlEvents, target.parent.boundStandardOutputs);
      } else if (target is TextInfo) {
        suggestHtmlTags(template, suggestions);
        suggestTransclusions(target.parent, suggestions);
      }
    }
    return suggestions;
  }

  suggestTransclusions(
      ElementInfo container, List<CompletionSuggestion> suggestions) {
    for (AbstractDirective directive in container.directives) {
      if (directive is! Component) {
        continue;
      }

      Component component = directive;
      Template template = component?.view?.template;
      if (template == null) {
        continue;
      }

      for (NgContent ngContent in template.ngContents) {
        if (ngContent.selector == null) {
          continue;
        }

        List<HtmlTagForSelector> tags = ngContent.selector.suggestTags();
        for (HtmlTagForSelector tag in tags) {
          Location location = new Location(
              template.view.templateSource.fullName,
              ngContent.offset,
              ngContent.length,
              0,
              0);
          suggestions.add(_createHtmlTagSuggestion(
              tag.toString(),
              RELEVANCE_TRANSCLUSION,
              _createHtmlTagTransclusionElement(tag.toString(),
                  protocol.ElementKind.CLASS_TYPE_ALIAS, location)));
        }
      }
    }
  }

  suggestHtmlTags(Template template, List<CompletionSuggestion> suggestions) {
    Map<String, List<AbstractDirective>> elementTagMap =
        template.view.elementTagsInfo;
    for (String elementTagName in elementTagMap.keys) {
      CompletionSuggestion currentSuggestion = _createHtmlTagSuggestion(
          '<' + elementTagName,
          DART_RELEVANCE_DEFAULT,
          _createHtmlTagElement(
              elementTagName,
              elementTagMap[elementTagName].first,
              protocol.ElementKind.CLASS_TYPE_ALIAS));
      if (currentSuggestion != null) {
        suggestions.add(currentSuggestion);
      }
    }
  }

  suggestInputs(
      List<DirectiveBinding> directives,
      List<CompletionSuggestion> suggestions,
      List<InputElement> standardHtmlAttributes,
      List<InputBinding> boundStandardAttributes,
      {ExpressionBoundAttribute currentAttr}) {
    for (DirectiveBinding directive in directives) {
      Set<InputElement> usedInputs = new HashSet.from(directive.inputBindings
          .where((b) => b.attribute != currentAttr)
          .map((b) => b.boundInput));

      for (InputElement input in directive.boundDirective.inputs) {
        // don't recommend [name] [name] [name]
        if (usedInputs.contains(input)) {
          continue;
        }
        suggestions.add(_createInputSuggestion(input, DART_RELEVANCE_DEFAULT,
            _createInputElement(input, protocol.ElementKind.SETTER)));
      }
    }

    Set<InputElement> usedStdInputs = new HashSet.from(boundStandardAttributes
        .where((b) => b.attribute != currentAttr)
        .map((b) => b.boundInput));

    for (InputElement input in standardHtmlAttributes) {
      // TODO don't recommend [hidden] [hidden] [hidden]
      if (usedStdInputs.contains(input)) {
        continue;
      }
      suggestions.add(_createInputSuggestion(input, DART_RELEVANCE_DEFAULT - 1,
          _createInputElement(input, protocol.ElementKind.SETTER)));
    }
  }

  suggestOutputs(
      List<DirectiveBinding> directives,
      List<CompletionSuggestion> suggestions,
      List<OutputElement> standardHtmlEvents,
      List<OutputBinding> boundStandardOutputs,
      {BoundAttributeInfo currentAttr}) {
    for (DirectiveBinding directive in directives) {
      Set<OutputElement> usedOutputs = new HashSet.from(directive.outputBindings
          .where((b) => b.attribute != currentAttr)
          .map((b) => b.boundOutput));
      for (OutputElement output in directive.boundDirective.outputs) {
        // don't recommend (close) (close) (close)
        if (usedOutputs.contains(output)) {
          continue;
        }
        suggestions.add(_createOutputSuggestion(output, DART_RELEVANCE_DEFAULT,
            _createOutputElement(output, protocol.ElementKind.GETTER)));
      }
    }

    Set<OutputElement> usedStdOutputs = new HashSet.from(boundStandardOutputs
        .where((b) => b.attribute != currentAttr)
        .map((b) => b.boundOutput));

    for (OutputElement output in standardHtmlEvents) {
      // don't recommend (click) (click) (click)
      if (usedStdOutputs.contains(output)) {
        continue;
      }
      suggestions.add(_createOutputSuggestion(
          output,
          DART_RELEVANCE_DEFAULT - 1, // just below regular relevance
          _createOutputElement(output, protocol.ElementKind.GETTER)));
    }
  }

  addLocalVariables(List<CompletionSuggestion> suggestions,
      Map<String, LocalVariable> localVars, OpType optype) {
    for (LocalVariable eachVar in localVars.values) {
      suggestions.add(_addLocalVariableSuggestion(
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
    relevance = optype.returnValueSuggestionsFilter(
            variable.dartVariable.type, relevance) ??
        DART_RELEVANCE_DEFAULT;
    return _createLocalSuggestion(variable, relevance, typeName,
        _createLocalElement(variable, elemKind, typeName));
  }

  CompletionSuggestion _createLocalSuggestion(LocalVariable localVar,
      int defaultRelevance, DartType type, protocol.Element element) {
    String completion = localVar.name;
    return new CompletionSuggestion(CompletionSuggestionKind.INVOCATION,
        defaultRelevance, completion, completion.length, 0, false, false,
        returnType: type.toString(), element: element);
  }

  protocol.Element _createLocalElement(
      LocalVariable localVar, protocol.ElementKind kind, DartType type) {
    String name = localVar.name;
    Location location = new Location(localVar.source.fullName,
        localVar.nameOffset, localVar.nameLength, 0, 0);
    int flags = protocol.Element.makeFlags();
    return new protocol.Element(kind, name, flags,
        location: location, returnType: type.toString());
  }

  CompletionSuggestion _createHtmlTagSuggestion(
      String elementTagName, int defaultRelevance, protocol.Element element) {
    return new CompletionSuggestion(
        CompletionSuggestionKind.INVOCATION,
        defaultRelevance,
        elementTagName,
        elementTagName.length,
        0,
        false,
        false,
        element: element);
  }

  protocol.Element _createHtmlTagElement(String elementTagName,
      AbstractDirective directive, protocol.ElementKind kind) {
    ElementNameSelector selector = directive.elementTags.firstWhere(
        (currSelector) => currSelector.toString() == elementTagName);
    int offset = selector.nameElement.nameOffset;
    int length = selector.nameElement.nameLength;

    Location location =
        new Location(directive.source.fullName, offset, length, 0, 0);
    int flags = protocol.Element
        .makeFlags(isAbstract: false, isDeprecated: false, isPrivate: false);
    return new protocol.Element(kind, '<' + elementTagName, flags,
        location: location);
  }

  protocol.Element _createHtmlTagTransclusionElement(
      String elementTagName, protocol.ElementKind kind, Location location) {
    int flags = protocol.Element
        .makeFlags(isAbstract: false, isDeprecated: false, isPrivate: false);
    return new protocol.Element(kind, elementTagName, flags,
        location: location);
  }

  CompletionSuggestion _createInputSuggestion(InputElement inputElement,
      int defaultRelevance, protocol.Element element) {
    String completion = '[' + inputElement.name + ']';
    return new CompletionSuggestion(CompletionSuggestionKind.INVOCATION,
        defaultRelevance, completion, completion.length, 0, false, false,
        element: element);
  }

  protocol.Element _createInputElement(
      InputElement inputElement, protocol.ElementKind kind) {
    String name = '[' + inputElement.name + ']';
    Location location = new Location(inputElement.source.fullName,
        inputElement.nameOffset, inputElement.nameLength, 0, 0);
    int flags = protocol.Element
        .makeFlags(isAbstract: false, isDeprecated: false, isPrivate: false);
    return new protocol.Element(kind, name, flags, location: location);
  }

  CompletionSuggestion _createOutputSuggestion(OutputElement outputElement,
      int defaultRelevance, protocol.Element element) {
    String completion = '(' + outputElement.name + ')';
    return new CompletionSuggestion(CompletionSuggestionKind.INVOCATION,
        defaultRelevance, completion, completion.length, 0, false, false,
        element: element, returnType: outputElement.eventType.toString());
  }

  protocol.Element _createOutputElement(
      OutputElement outputElement, protocol.ElementKind kind) {
    String name = '(' + outputElement.name + ')';
    Location location = new Location(outputElement.source.fullName,
        outputElement.nameOffset, outputElement.nameLength, 0, 0);
    int flags = protocol.Element.makeFlags();
    return new protocol.Element(kind, name, flags,
        location: location, returnType: outputElement.eventType.toString());
  }
}
