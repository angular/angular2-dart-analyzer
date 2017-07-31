import 'dart:collection';

import 'package:front_end/src/base/api_signature.dart';

abstract class FileHasher {
  ApiSignature getContentHash(String path);
  ApiSignature getUnitElementHash(String path);
}

class FileTracker {
  static const int salt = 1;

  final FileHasher _fileHasher;

  FileTracker(this._fileHasher);

  final _dartToDart = new _RelationshipTracker();
  final _dartToHtml = new _RelationshipTracker();

  final _dartFilesWithDartTemplates = new HashSet<String>();

  final contentHashes = <String, _FileHash>{};

  void rehashContents(String path) {
    final signature = _fileHasher.getContentHash(path);
    final bytes = signature.toByteList();
    contentHashes[path] = new _FileHash(
        bytes,
        new ApiSignature()
          ..addInt(salt)
          ..addBytes(bytes));
  }

  List<int> _getContentHash(String path) {
    if (contentHashes[path] == null) {
      rehashContents(path);
    }
    return contentHashes[path].unsaltedBytes;
  }

  void setDartHtmlTemplates(String dartPath, List<String> htmlPaths) =>
      _dartToHtml.setFileReferencesFiles(dartPath, htmlPaths);

  // ignore: avoid_positional_boolean_parameters
  void setDartHasTemplate(String dartPath, bool hasTemplate) {
    if (hasTemplate) {
      _dartFilesWithDartTemplates.add(dartPath);
    } else {
      _dartFilesWithDartTemplates.remove(dartPath);
    }
  }

  List<String> getHtmlPathsReferencedByDart(String dartPath) =>
      _dartToHtml.getFilesReferencedBy(dartPath);

  List<String> getDartPathsReferencingHtml(String htmlPath) =>
      _dartToHtml.getFilesReferencingFile(htmlPath);

  void setDartImports(String dartPath, List<String> imports) {
    _dartToDart.setFileReferencesFiles(dartPath, imports);
  }

  List<String> getHtmlPathsReferencingHtml(String htmlPath) => _dartToHtml
      .getFilesReferencingFile(htmlPath)
      .map(_dartToDart.getFilesReferencingFile)
      .fold(<String>[], (list, acc) => list..addAll(acc))
      .map(_dartToHtml.getFilesReferencedBy)
      .fold(<String>[], (list, acc) => list..addAll(acc))
      .toList();

  List<String> getDartPathsAffectedByHtml(String htmlPath) => _dartToHtml
      .getFilesReferencingFile(htmlPath)
      .map(_dartToDart.getFilesReferencingFile)
      .fold(<String>[], (list, acc) => list..addAll(acc))
      .where(_dartFilesWithDartTemplates.contains)
      .toList();

  List<String> getHtmlPathsAffectingDart(String dartPath) {
    if (_dartFilesWithDartTemplates.contains(dartPath)) {
      return getHtmlPathsAffectingDartContext(dartPath);
    }

    return [];
  }

  List<String> getHtmlPathsAffectingDartContext(String dartPath) => _dartToDart
      .getFilesReferencedBy(dartPath)
      .map(_dartToHtml.getFilesReferencedBy)
      .fold(<String>[], (list, acc) => list..addAll(acc)).toList();

  ApiSignature getDartSignature(String dartPath) {
    final signature = new ApiSignature()
      ..addInt(salt)
      ..addBytes(_fileHasher.getUnitElementHash(dartPath).toByteList());
    for (final htmlPath in getHtmlPathsAffectingDart(dartPath)) {
      signature.addBytes(_getContentHash(htmlPath));
    }
    return signature;
  }

  ApiSignature getHtmlSignature(String htmlPath) {
    final signature = new ApiSignature()
      ..addInt(salt)
      ..addBytes(_getContentHash(htmlPath));
    for (final dartPath in getDartPathsReferencingHtml(htmlPath)) {
      signature.addBytes(_fileHasher.getUnitElementHash(dartPath).toByteList());
      for (final subHtmlPath in getHtmlPathsAffectingDartContext(dartPath)) {
        signature.addBytes(_getContentHash(subHtmlPath));
      }
    }
    return signature;
  }

  ApiSignature getContentSignature(String path) {
    if (contentHashes[path] == null) {
      rehashContents(path);
    }
    return contentHashes[path].saltedSignature;
  }

  ApiSignature getUnitElementSignature(String path) => new ApiSignature()
    ..addInt(salt)
    ..addBytes(_fileHasher.getUnitElementHash(path).toByteList());
}

class _FileHash {
  final List<int> unsaltedBytes;
  final ApiSignature saltedSignature;

  _FileHash(this.unsaltedBytes, this.saltedSignature);
}

class _RelationshipTracker {
  final _filesReferencedByFile = <String, List<String>>{};
  final _filesReferencingFile = <String, List<String>>{};

  void setFileReferencesFiles(String filePath, List<String> referencesPaths) {
    final priorRelationships = new HashSet<String>();
    if (_filesReferencedByFile.containsKey(filePath)) {
      for (final referencesPath in _filesReferencedByFile[filePath]) {
        if (!referencesPaths.contains(referencesPath)) {
          _filesReferencingFile[referencesPath].remove(filePath);
        } else {
          priorRelationships.add(referencesPath);
        }
      }
    }

    _filesReferencedByFile[filePath] = referencesPaths;

    for (final referencesPath in referencesPaths) {
      if (priorRelationships.contains(referencesPath)) {
        continue;
      }

      if (!_filesReferencingFile.containsKey(referencesPath)) {
        _filesReferencingFile[referencesPath] = [filePath];
      } else {
        _filesReferencingFile[referencesPath].add(filePath);
      }
    }
  }

  List<String> getFilesReferencedBy(String filePath) =>
      _filesReferencedByFile[filePath] ?? [];

  List<String> getFilesReferencingFile(String usesPath) =>
      _filesReferencingFile[usesPath] ?? [];
}
