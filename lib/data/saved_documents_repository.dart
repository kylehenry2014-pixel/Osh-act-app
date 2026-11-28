import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/saved_document.dart';
import 'document_integrity.dart';

class SavedDocumentsRepository {
  static final SavedDocumentsRepository instance =
      SavedDocumentsRepository._();

  SavedDocumentsRepository._()
      : _directoryProvider = getApplicationDocumentsDirectory,
        _metadataWriter = _defaultMetadataWriter,
        _metadataReloader = _defaultMetadataReloader;

  /// Independent repository for isolated automated tests.
  /// Tests must supply temporary storage and mocked preferences.
  @visibleForTesting
  SavedDocumentsRepository.forTesting({
    required Future<Directory> Function() directoryProvider,
    Future<bool> Function(
      SharedPreferences prefs,
      String key,
      String value,
    )? metadataWriter,
    Future<void> Function(
      SharedPreferences prefs,
    )? metadataReloader,
  })  : _directoryProvider = directoryProvider,
        _metadataWriter =
            metadataWriter ?? _defaultMetadataWriter,
        _metadataReloader =
            metadataReloader ?? _defaultMetadataReloader;

  final Future<Directory> Function() _directoryProvider;

  final Future<bool> Function(
    SharedPreferences prefs,
    String key,
    String value,
  ) _metadataWriter;

  final Future<void> Function(
    SharedPreferences prefs,
  ) _metadataReloader;

  static Future<bool> _defaultMetadataWriter(
    SharedPreferences prefs,
    String key,
    String value,
  ) {
    return prefs.setString(key, value);
  }

  static Future<void> _defaultMetadataReloader(
    SharedPreferences prefs,
  ) {
    return prefs.reload();
  }

  static const _prefsKey = 'saved_documents';

  final List<SavedDocument> _documents = [];

  bool _loaded = false;
  bool _reloadRequired = false;
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

    if (_reloadRequired) {
      await _metadataReloader(prefs);
    }

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

    _reloadRequired = false;
    _loaded = true;
  }

  Future<void> _commit(
    List<SavedDocument> next,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final encoded = jsonEncode(
      next.map((document) => document.toJson()).toList(),
    );

    try {
      final saved = await _metadataWriter(
        prefs,
        _prefsKey,
        encoded,
      );

      if (!saved) {
        throw StateError(
          'Could not save document records.',
        );
      }
    } catch (_) {
      // A failed write may still have reached platform storage.
      // Never assume the previous in-memory records are authoritative.
      _loaded = false;
      _reloadRequired = true;

      try {
        await load();

        final recovered = jsonEncode(
          _documents.map(
            (document) => document.toJson(),
          ).toList(),
        );

        if (recovered == encoded) {
          // The requested metadata was persisted despite
          // the reported write failure.
          return;
        }
      } catch (_) {
        _loaded = false;
        _reloadRequired = true;

        debugPrint(
          'Saved document metadata recovery unavailable.',
        );
      }

      rethrow;
    }

    _documents
      ..clear()
      ..addAll(next);
  }

  Future<Directory> _documentsDirectory() async {
    final appDir = await _directoryProvider();

    final directory = Directory(
      appDir.path.endsWith(Platform.pathSeparator)
          ? '${appDir.path}saved_documents'
          : '${appDir.path}${Platform.pathSeparator}saved_documents',
    );

    final existingType = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );

    if (existingType != FileSystemEntityType.notFound &&
        existingType != FileSystemEntityType.directory) {
      throw StateError('Document storage is not a safe directory.');
    }

    await directory.create(recursive: true);

    final appRoot = await appDir.resolveSymbolicLinks();
    final documentRoot = await directory.resolveSymbolicLinks();
    final separator = Platform.pathSeparator;
    final expectedRoot = appRoot.endsWith(separator)
        ? '${appRoot}saved_documents'
        : '$appRoot${separator}saved_documents';

    if (documentRoot != expectedRoot) {
      throw StateError('Document storage location is unsafe.');
    }

    return directory;
  }


  /// Returns a validated, canonical path for a stored document.
  Future<String> validateForOpening(String id) {
    return _serialise(() async {
      await load();

      final matches = _documents.where(
        (document) => document.id == id,
      ).toList();

      if (matches.length != 1) {
        throw StateError('Saved document record not found.');
      }

      final file = await _validatedStoredFile(
        matches.single.filePath,
      );

      await DocumentIntegrity.validateFile(file);

      return file.path;
    });
  }

  Future<File> _validatedStoredFile(String path) async {
    final directory = await _documentsDirectory();
    final root = await directory.resolveSymbolicLinks();

    final separator = Platform.pathSeparator;
    final prefix = root.endsWith(separator)
        ? root
        : '$root$separator';

    final file = File(path);

    if (!file.isAbsolute) {
      throw StateError('Invalid document path.');
    }

    if (path.split(RegExp(r'[/\\]')).any(
      (segment) => segment == '..' || segment == '.',
    )) {
      throw StateError('Invalid document path.');
    }

    final type = await FileSystemEntity.type(
      path,
      followLinks: false,
    );

    if (type != FileSystemEntityType.file) {
      throw StateError(
        'This document is unavailable or has an unsafe path.',
      );
    }

    final resolved = await file.resolveSymbolicLinks();

    if (!resolved.startsWith(prefix)) {
      throw StateError('Document is outside authorised storage.');
    }

    final relative = resolved.substring(prefix.length);

    if (relative.isEmpty ||
        relative.contains('/') ||
        relative.contains('\\')) {
      throw StateError('Invalid document storage location.');
    }

    final expectedPath = '${directory.path}$separator$relative';

    if (path != expectedPath && path != resolved) {
      throw StateError('Document path redirection is not allowed.');
    }

    return File(resolved);
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

      final extension = DocumentIntegrity.extensionFor(
        source.uri.pathSegments.last,
      );

      await DocumentIntegrity.validateFile(
        source,
        expectedExtension: extension,
      );

      final sourceLength = await source.length();

      final directory = await _documentsDirectory();

      final id = const Uuid().v4();

      final destination = File(
        '${directory.path}${Platform.pathSeparator}$id.$extension',
      );

      final document = SavedDocument(
        id: id,
        name: cleanName,
        category: cleanCategory,
        filePath: destination.path,
        savedAt: DateTime.now(),
      );

      // Reserve a new destination without replacing an existing file.
      await destination.create(exclusive: true);

      try {
        final output = destination.openWrite();

        try {
          await output.addStream(source.openRead());
          await output.flush();
        } finally {
          await output.close();
        }

        if (await destination.length() != sourceLength) {
          throw StateError(
            'The document copy is incomplete.',
          );
        }

        final validatedCopy = await _validatedStoredFile(
          destination.path,
        );

        await DocumentIntegrity.validateFile(
          validatedCopy,
          expectedExtension: extension,
        );

        final next = List<SavedDocument>.of(_documents)
          ..add(document);

        await _commit(next);

        return document;
      } catch (error) {
        // Delete only when the current metadata is known.
        // If recovery failed, preserving an orphaned file
        // is safer than deleting a registered document.
        if (_loaded && !_reloadRequired) {
          await _deleteUnusedFile(destination.path);
        } else {
          debugPrint(
            'Document copy preserved pending metadata recovery.',
          );
        }

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
    // Physical cleanup requires authoritative metadata.
    if (!_loaded || _reloadRequired) {
      return;
    }

    try {
      if (_documents.any(
        (document) => document.filePath == path,
      )) {
        return;
      }

      final type = await FileSystemEntity.type(
        path,
        followLinks: false,
      );

      if (type == FileSystemEntityType.notFound) {
        return;
      }

      // Apply the same containment and path checks used
      // when opening a stored document.
      final file = await _validatedStoredFile(path);
      final resolved = file.path;

      // Preserve files referenced by any remaining record,
      // including records using an alternative path.
      for (final document in _documents) {
        final retained = File(document.filePath);

        if (await retained.exists() &&
            await retained.resolveSymbolicLinks() ==
                resolved) {
          return;
        }
      }

      // Revalidate immediately before physical deletion.
      // Do not require a valid signature: damaged documents
      // must remain removable.
      final confirmed = await _validatedStoredFile(path);

      if (confirmed.path != resolved) {
        throw StateError(
          'Document location changed during cleanup.',
        );
      }

      await confirmed.delete();
    } catch (error) {
      // Cleanup failure must not corrupt saved records.
      debugPrint('Document cleanup failed: $error');
    }
  }
}