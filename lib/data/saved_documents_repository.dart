import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/saved_document.dart';

class SavedDocumentsRepository {
  static final SavedDocumentsRepository instance =
      SavedDocumentsRepository._();

  SavedDocumentsRepository._();

  static const _prefsKey = 'saved_documents';

  final List<SavedDocument> _documents = [];

  bool _loaded = false;
  Future<void>? _loading;

  Future<void> _queue = Future<void>.value();

  List<SavedDocument> get all {
    final sorted = List<SavedDocument>.of(_documents)
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));

    return List.unmodifiable(sorted);
  }

  Future<T> _serialise<T>(
    Future<T> Function() operation,
  ) {
    final result = _queue.then((_) => operation());

    _queue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        debugPrint('Saved document operation failed: $error');
      },
    );

    return result;
  }

  Future<void> load() {
    if (_loaded) return Future<void>.value();

    return _loading ??= _load().whenComplete(
      () => _loading = null,
    );
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);

    final restored = <SavedDocument>[];

    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);

        if (decoded is! List) {
          throw const FormatException(
            'Invalid saved document storage.',
          );
        }

        final ids = <String>{};

        for (final item in decoded) {
          if (item is! Map) {
            throw const FormatException(
              'Invalid saved document record.',
            );
          }

          final document = SavedDocument.fromJson(
            Map<String, dynamic>.from(item),
          );

          if (document.id.isEmpty ||
              document.filePath.isEmpty ||
              !ids.add(document.id)) {
            throw const FormatException(
              'Invalid or duplicate document record.',
            );
          }

          restored.add(document);
        }
      } catch (error) {
        debugPrint('Saved document storage error: $error');

        // Do not overwrite unreadable customer data.
        throw StateError(
          'Saved documents could not be loaded safely. '
          'Existing records have been preserved.',
        );
      }
    }

    _documents
      ..clear()
      ..addAll(restored);

    _loaded = true;
  }

  Future<void> _commit(
    List<SavedDocument> next,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final encoded = jsonEncode(
      next.map((document) => document.toJson()).toList(),
    );

    final saved = await prefs.setString(
      _prefsKey,
      encoded,
    );

    if (!saved) {
      throw StateError(
        'Could not save document records.',
      );
    }

    _documents
      ..clear()
      ..addAll(next);
  }

  Future<Directory> _documentsDirectory() async {
    final appDir =
        await getApplicationDocumentsDirectory();

    final directory = Directory(
      '${appDir.path}/saved_documents',
    );

    await directory.create(recursive: true);

    return directory;
  }

  Future<SavedDocument> saveDocument({
    required String sourcePath,
    required String name,
    required String category,
  }) {
    return _serialise(() async {
      await load();

      final cleanName = name.trim();
      final cleanCategory = category.trim();

      if (cleanName.isEmpty ||
          cleanCategory.isEmpty) {
        throw ArgumentError(
          'Document name and category are required.',
        );
      }

      final source = File(sourcePath);

      if (!await source.exists()) {
        throw StateError(
          'The source document could not be found.',
        );
      }

      final sourceLength = await source.length();

      if (sourceLength == 0) {
        throw StateError(
          'The source document is empty.',
        );
      }

      final directory = await _documentsDirectory();

      final extensionMatch = RegExp(
        r'\.([a-zA-Z0-9]{1,10})$',
      ).firstMatch(source.uri.pathSegments.last);

      final extension =
          extensionMatch?.group(1)?.toLowerCase() ??
              'docx';

      final id = const Uuid().v4();

      final destination = File(
        '${directory.path}/$id.$extension',
      );

      final document = SavedDocument(
        id: id,
        name: cleanName,
        category: cleanCategory,
        filePath: destination.path,
        savedAt: DateTime.now(),
      );

      try {
        await source.copy(destination.path);

        if (await destination.length() != sourceLength) {
          throw StateError(
            'The document copy is incomplete.',
          );
        }

        final next = List<SavedDocument>.of(_documents)
          ..add(document);

        await _commit(next);

        return document;
      } catch (error) {
        // Remove an incomplete or uncommitted copy.
        await _deleteUnusedFile(destination.path);
        rethrow;
      }
    });
  }

  Future<void> delete(String id) {
    return _serialise(() async {
      await load();

      final index = _documents.indexWhere(
        (document) => document.id == id,
      );

      if (index == -1) return;

      final document = _documents[index];

      final next = List<SavedDocument>.of(_documents)
        ..removeAt(index);

      // Commit metadata before deleting the physical file.
      await _commit(next);

      await _deleteUnusedFile(document.filePath);
    });
  }

  Future<void> _deleteUnusedFile(String path) async {
    try {
      if (_documents.any(
        (document) => document.filePath == path,
      )) {
        return;
      }

      final file = File(path);

      final type = await FileSystemEntity.type(
        path,
        followLinks: false,
      );

      if (type != FileSystemEntityType.file) return;

      final directory = await _documentsDirectory();

      final root =
          await directory.resolveSymbolicLinks();

      final resolved =
          await file.resolveSymbolicLinks();

      final prefix = root.endsWith(Platform.pathSeparator)
          ? root
          : '$root${Platform.pathSeparator}';

      if (!resolved.startsWith(prefix)) {
        debugPrint(
          'Skipped document cleanup outside app storage.',
        );
        return;
      }

      for (final document in _documents) {
        final retained = File(document.filePath);

        if (await retained.exists() &&
            await retained.resolveSymbolicLinks() ==
                resolved) {
          return;
        }
      }

      await file.delete();
    } catch (error) {
      // Cleanup failure must not corrupt saved records.
      debugPrint('Document cleanup failed: $error');
    }
  }
}