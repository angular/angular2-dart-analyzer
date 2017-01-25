import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/src/generated/parser.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/src/dart/ast/token.dart' hide SimpleToken;
import 'package:analyzer/src/dart/scanner/reader.dart';
import 'package:analyzer/src/dart/scanner/scanner.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:angular_analyzer_plugin/ast.dart';
import 'package:angular_analyzer_plugin/src/ng_expr_parser.dart';
import 'package:angular_analyzer_plugin/src/angular_html_parser.dart';
import 'package:angular_analyzer_plugin/src/strings.dart';
import 'package:angular_analyzer_plugin/tasks.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html;
import 'package:source_span/source_span.dart';

html.Element firstElement(html.Node node) {
  for (html.Element child in node.children) {
    if (child is html.Element) {
      return child;
    }
  }
  return null;
}

class HtmlTreeConverter {
  final EmbeddedDartParser dartParser;
  final Source templateSource;
  final AnalysisErrorListener errorListener;

  HtmlTreeConverter(this.dartParser, this.templateSource, this.errorListener);

  NodeInfo convert(html.Node node, {ElementInfo parent}) {
    if (node is html.Element) {
      String localName = node.localName;
      List<AttributeInfo> attributes = _convertAttributes(node);
      bool isTemplate = localName == 'template';
      SourceRange openingSpan = _toSourceRange(node.sourceSpan);
      SourceRange closingSpan = _toSourceRange(node.endSourceSpan);
      SourceRange openingNameSpan = openingSpan != null
          ? new SourceRange(openingSpan.offset + '<'.length, localName.length)
          : null;
      SourceRange closingNameSpan = closingSpan != null
          ? new SourceRange(closingSpan.offset + '</'.length, localName.length)
          : null;
      ElementInfo element = new ElementInfo(
          localName,
          openingSpan,
          closingSpan,
          openingNameSpan,
          closingNameSpan,
          isTemplate,
          attributes,
          findTemplateAttribute(attributes),
          parent);

      for (AttributeInfo attribute in attributes) {
        attribute.parent = element;
      }

      List<NodeInfo> children = _convertChildren(node, element);
      element.childNodes.addAll(children);

      if (!element.isSynthetic &&
          element.openingSpanIsClosed &&
          closingSpan != null &&
          (openingSpan.offset + openingSpan.length) == closingSpan.offset) {
        element.childNodes.add(new TextInfo(
            openingSpan.offset + openingSpan.length, '', element, [],
            synthetic: true));
      }

      return element;
    }
    if (node is html.Text) {
      int offset = node.sourceSpan.start.offset;
      String text = node.text;
      return new TextInfo(
          offset, text, parent, dartParser.findMustaches(text, offset));
    }
    return null;
  }

  List<AttributeInfo> _convertAttributes(html.Element element) {
    List<AttributeInfo> attributes = <AttributeInfo>[];
    element.attributes.forEach((name, String value) {
      if (name is String) {
        try {
          if (name == "") {
            attributes.add(_convertSyntheticAttribute(element));
          } else if (name.startsWith('*')) {
            attributes.add(_convertTemplateAttribute(element, name, true));
          } else if (name == 'template') {
            attributes.add(_convertTemplateAttribute(element, name, false));
          } else if (name.startsWith('[(')) {
            attributes.add(_convertExpressionBoundAttribute(
                element, name, "[(", ")]", ExpressionBoundType.twoWay));
          } else if (name.startsWith('[class.')) {
            attributes.add(_convertExpressionBoundAttribute(
                element, name, "[class.", "]", ExpressionBoundType.clazz));
          } else if (name.startsWith('[attr.')) {
            attributes.add(_convertExpressionBoundAttribute(
                element, name, "[attr.", "]", ExpressionBoundType.attr));
          } else if (name.startsWith('[style.')) {
            attributes.add(_convertExpressionBoundAttribute(
                element, name, "[style.", "]", ExpressionBoundType.style));
          } else if (name.startsWith('[')) {
            attributes.add(_convertExpressionBoundAttribute(
                element, name, "[", "]", ExpressionBoundType.input));
          } else if (name.startsWith('bind-')) {
            attributes.add(_convertExpressionBoundAttribute(
                element, name, "bind-", null, ExpressionBoundType.input));
          } else if (name.startsWith('on-')) {
            attributes.add(
                _convertStatementsBoundAttribute(element, name, "on-", null));
          } else if (name.startsWith('(')) {
            attributes
                .add(_convertStatementsBoundAttribute(element, name, "(", ")"));
          } else {
            var valueOffset = _valueOffset(element, name);
            if (valueOffset == null) {
              value = null;
            }

            attributes.add(new TextAttribute(
                name,
                _nameOffset(element, name),
                value,
                valueOffset,
                dartParser.findMustaches(value, valueOffset)));
          }
        } on IgnorableHtmlInternalError {
          // See https://github.com/dart-lang/html/issues/44, this error will
          // be thrown looking for nameOffset. Catch it so that analysis else
          // where continues.
          return;
        }
      }
    });
    return attributes;
  }

  TextAttribute _convertSyntheticAttribute(html.Element element) {
    FileSpan openSourceSpan = element.sourceSpan;
    int nameOffset = openSourceSpan.start.offset + openSourceSpan.length;
    TextAttribute textAttribute =
        new TextAttribute("", nameOffset, null, null, []);
    return textAttribute;
  }

  TemplateAttribute _convertTemplateAttribute(
      html.Element element, String origName, bool starSugar) {
    int origNameOffset = _nameOffset(element, origName);
    int valueOffset = _valueOffset(element, origName);
    String value = valueOffset == null ? null : element.attributes[origName];
    String name;
    int nameOffset;
    List<AttributeInfo> virtualAttributes;
    if (starSugar) {
      nameOffset = origNameOffset + '*'.length;
      name = _removePrefixSuffix(origName, '*', null);
      virtualAttributes = dartParser.parseTemplateVirtualAttributes(
          nameOffset, name + (' ' * '="'.length) + (value ?? ''));
    } else {
      name = origName;
      nameOffset = origNameOffset;
      virtualAttributes =
          dartParser.parseTemplateVirtualAttributes(valueOffset, value);
    }

    TemplateAttribute templateAttribute = new TemplateAttribute(
        name,
        nameOffset,
        value,
        valueOffset,
        origName,
        origNameOffset,
        virtualAttributes);

    for (AttributeInfo virtualAttribute in virtualAttributes) {
      virtualAttribute.parent = templateAttribute;
    }

    return templateAttribute;
  }

  StatementsBoundAttribute _convertStatementsBoundAttribute(
      html.Element element, String origName, String prefix, String suffix) {
    int origNameOffset = _nameOffset(element, origName);
    int valueOffset = _valueOffset(element, origName);
    String value = valueOffset == null ? null : element.attributes[origName];
    if (value == null) {
      errorListener.onError(new AnalysisError(templateSource, origNameOffset,
          origName.length, AngularWarningCode.EMPTY_BINDING, [origName]));
    }
    int propNameOffset = origNameOffset + prefix.length;
    String propName = _removePrefixSuffix(origName, prefix, suffix);
    return new StatementsBoundAttribute(
        propName,
        propNameOffset,
        value,
        valueOffset,
        origName,
        origNameOffset,
        dartParser.parseDartStatements(valueOffset, value));
  }

  ExpressionBoundAttribute _convertExpressionBoundAttribute(
      html.Element element,
      String origName,
      String prefix,
      String suffix,
      ExpressionBoundType bound) {
    int origNameOffset = _nameOffset(element, origName);
    int valueOffset = _valueOffset(element, origName);
    String value = valueOffset == null ? null : element.attributes[origName];
    if (value == null || value == "") {
      errorListener.onError(new AnalysisError(templateSource, origNameOffset,
          origName.length, AngularWarningCode.EMPTY_BINDING, [origName]));
      value = value == ""
          ? "null"
          : value; // we've created a warning. Suppress parse error now.
    }
    int propNameOffset = origNameOffset + prefix.length;
    String propName = _removePrefixSuffix(origName, prefix, suffix);
    return new ExpressionBoundAttribute(
        propName,
        propNameOffset,
        value,
        valueOffset,
        origName,
        origNameOffset,
        dartParser.parseDartExpression(valueOffset, value, true),
        bound);
  }

  List<NodeInfo> _convertChildren(html.Element node, ElementInfo parent) {
    List<NodeInfo> children = <NodeInfo>[];
    for (html.Node child in node.nodes) {
      NodeInfo childNode = convert(child, parent: parent);
      if (childNode != null) {
        children.add(childNode);
        if (childNode is ElementInfo) {
          parent.childNodesMaxEnd = childNode.childNodesMaxEnd;
        } else {
          parent.childNodesMaxEnd = childNode.offset + childNode.length;
        }
      }
    }
    return children;
  }

  TemplateAttribute findTemplateAttribute(List<AttributeInfo> attributes) {
    // TODO report errors when there are two or when its already a <template>
    for (AttributeInfo attribute in attributes) {
      if (attribute is TemplateAttribute) {
        return attribute;
      }
    }
    return null;
  }

  String _removePrefixSuffix(String value, String prefix, String suffix) {
    value = value.substring(prefix.length);
    if (suffix != null && value.endsWith(suffix)) {
      return value.substring(0, value.length - suffix.length);
    }
    return value;
  }

  int _nameOffset(html.Element element, String name) {
    String lowerName = name.toLowerCase();
    try {
      return element.attributeSpans[lowerName].start.offset;
      // See https://github.com/dart-lang/html/issues/44.
    } catch (e) {
      try {
        AttributeSpanContainer container =
            AttributeSpanContainer.generateAttributeSpans(element);
        return container.attributeSpans[name].start.offset;
      } catch (e) {
        throw new IgnorableHtmlInternalError(e);
      }
    }
  }

  int _valueOffset(html.Element element, String name) {
    String lowerName = name.toLowerCase();
    try {
      SourceSpan span = element.attributeValueSpans[lowerName];
      if (span != null) {
        return span.start.offset;
      } else {
        AttributeSpanContainer container =
            AttributeSpanContainer.generateAttributeSpans(element);
        return (container.attributeValueSpans.containsKey(name))
            ? container.attributeValueSpans[name].start.offset
            : null;
      }
    } catch (e) {
      throw new IgnorableHtmlInternalError(e);
    }
  }

  SourceRange _toSourceRange(SourceSpan span) {
    if (span != null) {
      return new SourceRange(span.start.offset, span.length);
    }
    return null;
  }
}

class EmbeddedDartParser {
  final Source templateSource;
  final AnalysisErrorListener errorListener;
  final TypeProvider typeProvider;
  final ErrorReporter errorReporter;

  EmbeddedDartParser(this.templateSource, this.errorListener, this.typeProvider,
      this.errorReporter);

  /**
   * Parse the given Dart [code] that starts at [offset].
   */
  Expression parseDartExpression(int offset, String code, bool detectTrailing) {
    if (code == null) {
      return null;
    }

    Token token = _scanDartCode(offset, code);
    Expression expression = _parseDartExpressionAtToken(token);

    if (detectTrailing && expression.endToken.next.type != TokenType.EOF) {
      int trailingExpressionBegin = expression.endToken.next.offset;
      errorListener.onError(new AnalysisError(
          templateSource,
          trailingExpressionBegin,
          offset + code.length - trailingExpressionBegin,
          AngularWarningCode.TRAILING_EXPRESSION));
    }

    return expression;
  }

  /**
   * Parse the given Dart [code] that starts ot [offset].
   * Also removes and reports dangling closing brackets.
   */
  List<Statement> parseDartStatements(int offset, String code) {
    List<Statement> allStatements = new List<Statement>();
    if (code == null) {
      return allStatements;
    }
    code = code + ';';
    Token token = _scanDartCode(offset, code);

    while (token.type != TokenType.EOF) {
      List<Statement> currentStatements = _parseDartStatementsAtToken(token);

      if (currentStatements.isNotEmpty) {
        allStatements.addAll(currentStatements);
        token = currentStatements.last.endToken.next;
      }
      if (token.type == TokenType.EOF) {
        break;
      }
      if (token.type == TokenType.CLOSE_CURLY_BRACKET) {
        int startCloseBracket = token.offset;
        while (token.type == TokenType.CLOSE_CURLY_BRACKET) {
          token = token.next;
        }
        int length = token.offset - startCloseBracket;
        errorListener.onError(new AnalysisError(
            templateSource,
            startCloseBracket,
            length,
            ParserErrorCode.UNEXPECTED_TOKEN,
            ["}"]));
        continue;
      } else {
        //Nothing should trigger here, but just in case to prevent infinite loop
        token = token.next;
      }
    }
    return allStatements;
  }

  /**
   * Parse the Dart expression starting at the given [token].
   */
  Expression _parseDartExpressionAtToken(Token token) {
    Parser parser =
        new NgExprParser(templateSource, errorListener, typeProvider);
    return parser.parseExpression(token);
  }

  /**
   * Parse the Dart statement starting at the given [token].
   */
  List<Statement> _parseDartStatementsAtToken(Token token) {
    Parser parser = new Parser(templateSource, errorListener);
    return parser.parseStatements(token);
  }

  /**
   * Scan the given Dart [code] that starts at [offset].
   */
  Token _scanDartCode(int offset, String code) {
    String text = ' ' * offset + code;
    CharSequenceReader reader = new CharSequenceReader(text);
    Scanner scanner = new Scanner(templateSource, reader, errorListener);
    return scanner.tokenize();
  }

  /**
   * Scan the given [text] staring at the given [offset] and resolve all of
   * its embedded expressions.
   */
  List<Mustache> findMustaches(String text, int fileOffset) {
    List<Mustache> mustaches = <Mustache>[];
    if (text == null || text.length < 2) {
      return mustaches;
    }

    int textOffset = 0;
    while (true) {
      // begin
      final int begin = text.indexOf('{{', textOffset);
      final int nextBegin = text.indexOf('{{', begin + 2);
      final int end = text.indexOf('}}', textOffset);
      int exprBegin, exprEnd;
      bool detectTrailing = false;
      if (begin == -1 && end == -1) {
        break;
      }

      if (end == -1) {
        errorListener.onError(new AnalysisError(templateSource,
            fileOffset + begin, 2, AngularWarningCode.UNTERMINATED_MUSTACHE));
        // Move the cursor ahead and keep looking for more unmatched mustaches.
        textOffset = begin + 2;
        exprBegin = textOffset;
        exprEnd = _startsWithWhitespace(text.substring(exprBegin))
            ? exprBegin
            : text.length;
      } else if (begin == -1 || end < begin) {
        errorListener.onError(new AnalysisError(templateSource,
            fileOffset + end, 2, AngularWarningCode.UNOPENED_MUSTACHE));
        // Move the cursor ahead and keep looking for more unmatched mustaches.
        textOffset = end + 2;
        continue;
      } else if (nextBegin != -1 && nextBegin < end) {
        errorListener.onError(new AnalysisError(templateSource,
            fileOffset + begin, 2, AngularWarningCode.UNTERMINATED_MUSTACHE));
        // Skip this open mustache, check the next open we found
        textOffset = begin + 2;
        exprBegin = textOffset;
        exprEnd = nextBegin;
      } else {
        exprBegin = begin + 2;
        exprEnd = end;
        textOffset = end + 2;
        detectTrailing = true;
      }
      // resolve
      String code = text.substring(exprBegin, exprEnd);
      Expression expression =
          parseDartExpression(fileOffset + exprBegin, code, detectTrailing);

      var offset = fileOffset + begin;
      var length;
      if (end == -1) {
        length = expression.offset + expression.length - offset;
      } else {
        length = end + 2 - begin;
      }

      mustaches.add(new Mustache(offset, length, expression));
    }

    return mustaches;
  }

  bool _startsWithWhitespace(String string) {
    // trim returns the original string when no changes were made
    return !identical(string.trimLeft(), string);
  }

  /**
   * Desugar a template="" or *blah="" attribute into its list of virtual [AttributeInfo]s
   */
  List<AttributeInfo> parseTemplateVirtualAttributes(int offset, String code) {
    List<AttributeInfo> attributes = <AttributeInfo>[];
    Token token = _scanDartCode(offset, code);
    String prefix = null;
    while (token.type != TokenType.EOF) {
      // skip optional comma or semicolons
      if (_isDelimiter(token)) {
        token = token.next;
        continue;
      }
      // maybe a local variable
      if (_isTemplateVarBeginToken(token)) {
        if (token.type == TokenType.HASH) {
          errorReporter.reportErrorForToken(
              AngularWarningCode.UNEXPECTED_HASH_IN_TEMPLATE, token);
        }
        int originalVarOffset = token.offset;
        String originalName = token.lexeme;
        token = token.next;
        // get the local variable name
        String localVarName = "";
        int localVarOffset = token.offset;
        if (!_tokenMatchesIdentifier(token)) {
          errorReporter.reportErrorForToken(
              AngularWarningCode.EXPECTED_IDENTIFIER, token);
        } else {
          localVarOffset = token.offset;
          localVarName = token.lexeme;
          originalName +=
              ' ' * (token.offset - originalVarOffset) + localVarName;
          token = token.next;
        }
        // get an optional internal variable
        int internalVarOffset = null;
        String internalVarName = null;
        if (token.type == TokenType.EQ) {
          token = token.next;
          // get the internal variable
          if (!_tokenMatchesIdentifier(token)) {
            errorReporter.reportErrorForToken(
                AngularWarningCode.EXPECTED_IDENTIFIER, token);
            break;
          }
          internalVarOffset = token.offset;
          internalVarName = token.lexeme;
          token = token.next;
        }
        // declare the local variable
        // Note the care that the varname's offset is preserved in place.
        attributes.add(new TextAttribute.synthetic(
            'let-$localVarName',
            localVarOffset - 'let-'.length,
            internalVarName,
            internalVarOffset,
            originalName,
            originalVarOffset, []));
        continue;
      }
      // key
      int keyOffset = token.offset;
      String originalName = null;
      int originalNameOffset = keyOffset;
      String key = null;
      if (_tokenMatchesIdentifier(token)) {
        // scan for a full attribute name
        key = '';
        int lastEnd = token.offset;
        while (token.offset == lastEnd &&
            (_tokenMatchesIdentifier(token) || token.type == TokenType.MINUS)) {
          key += token.lexeme;
          lastEnd = token.end;
          token = token.next;
        }

        originalName = key;

        // add the prefix
        if (prefix == null) {
          prefix = key;
        } else {
          key = prefix + capitalize(key);
        }
      } else {
        errorReporter.reportErrorForToken(
            AngularWarningCode.EXPECTED_IDENTIFIER, token);
        break;
      }
      // skip optional ':' or '='
      if (token.type == TokenType.COLON || token.type == TokenType.EQ) {
        token = token.next;
      }
      // expression
      if (!_isTemplateVarBeginToken(token) &&
          !_isDelimiter(token) &&
          token.type != TokenType.EOF) {
        Expression expression = _parseDartExpressionAtToken(token);
        var start = token.offset - offset;
        token = expression.endToken.next;
        var end = token.offset - offset;
        var exprCode = code.substring(start, end);
        attributes.add(new ExpressionBoundAttribute(
            key,
            keyOffset,
            exprCode,
            token.offset,
            originalName,
            originalNameOffset,
            expression,
            ExpressionBoundType.input));
      } else {
        attributes.add(new TextAttribute.synthetic(
            key, keyOffset, null, null, originalName, originalNameOffset, []));
      }
    }

    return attributes;
  }

  static bool _isDelimiter(Token token) =>
      token.type == TokenType.COMMA || token.type == TokenType.SEMICOLON;

  static bool _isTemplateVarBeginToken(Token token) {
    return token is KeywordToken && token.keyword == Keyword.VAR ||
        (token.type == TokenType.IDENTIFIER && token.lexeme == 'let') ||
        token.type == TokenType.HASH;
  }

  static bool _tokenMatchesBuiltInIdentifier(Token token) =>
      token is KeywordToken && token.keyword.isPseudoKeyword;

  static bool _tokenMatchesIdentifier(Token token) =>
      token.type == TokenType.IDENTIFIER ||
      _tokenMatchesBuiltInIdentifier(token);
}

class IgnorableHtmlInternalError extends StateError {
  IgnorableHtmlInternalError(String msg) : super(msg);
}
