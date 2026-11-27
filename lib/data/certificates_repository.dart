import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/certificate.dart';
import 'notification_service.dart';
import 'download_allowance_service.dart';

/// Stores certificates and their photo pages locally.
///
/// Existing certificate records and image paths remain compatible.
/// All mutations are serialised to prevent overlapping writes.
class CertificatesRepository {
  CertificatesRepository._();

  static final CertificatesRepository instance =
      CertificatesRepository._();

  static const _storageKey = 'saved_certificates';
  static const _uuid = Uuid();

  List<Certificate> _certificates = [];

  bool _loaded = false;
  bool _reloadRequired = false;
  Future<void>? _loading;

  Future<void> _operationQueue = Future<void>.value();

  // =====================================================
  // SERIALISED STORAGE OPERATIONS
  // =====================================================

  Future<T> _serialise<T>(
    Future<T> Function() operation,
  ) {
    final result = _operationQueue.then<T>(
      (_) => operation(),
    );

    _operationQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );

    return result;
  }

  // =====================================================
  // LOAD EXISTING CERTIFICATES
  // =====================================================

  Future<void> load() async {
    if (_loaded) return;

    final pending = _loading;

    if (pending != null) {
      await pending;
      return;
    }

    final operation = _loadFromStorage();
    _loading = operation;

    try {
      await operation;
    } finally {
      _loading = null;
    }
  }

  Future<void> _loadFromStorage() async {
    final prefs =
        await SharedPreferences.getInstance();

    if (_reloadRequired) {
      await prefs.reload();
    }

    final raw = prefs.getString(_storageKey);

    if (raw == null || raw.isEmpty) {
      _certificates = [];
      _reloadRequired = false;
      _loaded = true;
      return;
    }

    try {
      final decoded = json.decode(raw);

      if (decoded is! List) {
        throw const FormatException(
          'Invalid certificate storage format.',
        );
      }

      final certificates = decoded.map((entry) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException(
            'Invalid certificate record.',
          );
        }

        return Certificate.fromJson(entry);
      }).toList();

      _certificates = certificates;
      _reloadRequired = false;
      _loaded = true;
    } catch (error) {
      // Never overwrite unreadable certificate data.
      debugPrint(
        'Certificate storage could not be read: $error',
      );

      rethrow;
    }
  }

  // =====================================================
  // SORTED CERTIFICATE LIST
  // =====================================================

  List<Certificate> get all {
    final list = [..._certificates];

    list.sort(
      (a, b) =>
          a.expiryDate.compareTo(b.expiryDate),
    );

    return list;
  }

  int _findIndex(String id) {
    final index = _certificates.indexWhere(
      (certificate) => certificate.id == id,
    );

    if (index == -1) {
      throw StateError(
        'Certificate not found: $id',
      );
    }

    return index;
  }

  // =====================================================
  // CREATE CERTIFICATE
  // =====================================================

  Future<Certificate> add({
    required String name,
    required List<String> sourceImagePaths,
    required DateTime expiryDate,
    String? notes,
  }) {
    final sources = List<String>.of(
      sourceImagePaths,
    );

    return _serialise(() async {
      await load();

      if (sources.isEmpty) {
        throw ArgumentError(
          'A certificate needs at least one page.',
        );
      }

      if (name.trim().isEmpty) {
        throw ArgumentError(
          'A certificate name is required.',
        );
      }

      final id = _uuid.v4();
      final savedPaths = <String>[];

      late final Certificate certificate;

      try {
        for (final source in sources) {
          savedPaths.add(
            await _copyImageToAppStorage(
              source,
              id,
            ),
          );
        }

        certificate = Certificate(
          id: id,
          name: name.trim(),
          imagePaths: savedPaths,
          expiryDate: expiryDate,
          createdAt: DateTime.now(),
          notes: notes,
        );

        // All certificate pages have been copied successfully.
        // Consume one allowance before registering the certificate.
        await DownloadAllowanceService.instance.checkAndConsume();

        await _commit([
          ..._certificates,
          certificate,
        ]);
      } catch (_) {
        await _deleteUnusedFiles(savedPaths);
        rethrow;
      }

      await _scheduleReminderSafely(certificate);

      return certificate;
    });
  }

  // =====================================================
  // APPEND CERTIFICATE PAGES
  // =====================================================

  Future<Certificate> addPages(
    String certId,
    List<String> newSourcePaths,
  ) {
    final sources = List<String>.of(
      newSourcePaths,
    );

    return _serialise(() async {
      await load();

      final index = _findIndex(certId);
      final existing = _certificates[index];

      if (sources.isEmpty) {
        return existing;
      }

      final savedPaths = <String>[];

      try {
        for (final source in sources) {
          savedPaths.add(
            await _copyImageToAppStorage(
              source,
              certId,
            ),
          );
        }

        final updated = existing.copyWith(
          imagePaths: [
            ...existing.imagePaths,
            ...savedPaths,
          ],
        );

        final next = [..._certificates];
        next[index] = updated;

        await _commit(next);

        return updated;
      } catch (_) {
        await _deleteUnusedFiles(savedPaths);
        rethrow;
      }
    });
  }

  // =====================================================
  // REMOVE A CERTIFICATE PAGE
  // =====================================================

  Future<Certificate> removePage(
    String certId,
    String imagePath,
  ) {
    return _serialise(() async {
      await load();

      final index = _findIndex(certId);
      final existing = _certificates[index];

      if (!existing.imagePaths.contains(imagePath)) {
        throw ArgumentError(
          'This page does not belong to the certificate.',
        );
      }

      final remaining = existing.imagePaths
          .where((path) => path != imagePath)
          .toList();

      if (remaining.isEmpty) {
        throw StateError(
          'Cannot remove the last certificate page.',
        );
      }

      final updated = existing.copyWith(
        imagePaths: remaining,
      );

      final next = [..._certificates];
      next[index] = updated;

      // Save metadata before removing any files.
      await _commit(next);

      await _deleteUnusedFiles([imagePath]);

      return updated;
    });
  }

  // =====================================================
  // UPDATE CERTIFICATE
  // =====================================================

  /// Saves metadata and newly selected pages together.
  /// Existing files are removed only after a successful commit.
  Future<Certificate> editCertificate({
    required String certId,
    required String name,
    required List<String> selectedPaths,
    required DateTime expiryDate,
    String? notes,
  }) {
    final requestedPaths = List<String>.of(selectedPaths);

    return _serialise(() async {
      await load();

      final index = _findIndex(certId);
      final existing = _certificates[index];

      if (name.trim().isEmpty) {
        throw ArgumentError(
          'A certificate name is required.',
        );
      }

      if (requestedPaths.isEmpty) {
        throw ArgumentError(
          'A certificate needs at least one page.',
        );
      }

      final originalPaths = existing.imagePaths.toSet();
      final copiedPaths = <String>[];
      final finalPaths = <String>[];

      late final Certificate updated;

      try {
        for (final path in requestedPaths) {
          if (originalPaths.contains(path)) {
            if (!await File(path).exists()) {
              throw StateError(
                'An existing certificate page is missing. '
                'Remove or replace the missing page before saving.',
              );
            }

            finalPaths.add(path);
          } else {
            final copied = await _copyImageToAppStorage(
              path,
              certId,
            );

            copiedPaths.add(copied);
            finalPaths.add(copied);
          }
        }

        updated = existing.copyWith(
          name: name.trim(),
          imagePaths: finalPaths,
          expiryDate: expiryDate,
          notes: notes ?? '',
        );

        final next = [..._certificates];
        next[index] = updated;

        // The original certificate remains untouched
        // until the updated record has been saved.
        await _commit(next);
      } catch (_) {
        await _deleteUnusedFiles(copiedPaths);
        rethrow;
      }

      final removedPaths = existing.imagePaths.where(
        (path) => !finalPaths.contains(path),
      );

      // Only remove old photos after successful persistence.
      await _deleteUnusedFiles(removedPaths);

      await _scheduleReminderSafely(updated);

      return updated;
    });
  }

  Future<void> update(Certificate updated) {
    return _serialise(() async {
      await load();

      final index = _findIndex(updated.id);

      if (updated.name.trim().isEmpty) {
        throw ArgumentError(
          'A certificate name is required.',
        );
      }

      if (updated.imagePaths.isEmpty) {
        throw ArgumentError(
          'A certificate needs at least one page.',
        );
      }

      for (final path in updated.imagePaths) {
        if (!await File(path).exists()) {
          throw StateError(
            'A certificate image is missing.',
          );
        }
      }

      final existing = _certificates[index];

      final removedPaths = existing.imagePaths
          .where(
            (path) =>
                !updated.imagePaths.contains(path),
          )
          .toList();

      final next = [..._certificates];
      next[index] = updated;

      await _commit(next);

      await _deleteUnusedFiles(removedPaths);

      await _scheduleReminderSafely(updated);
    });
  }

  // =====================================================
  // DELETE CERTIFICATE
  // =====================================================

  Future<void> delete(String id) {
    return _serialise(() async {
      await load();

      final index = _certificates.indexWhere(
        (certificate) => certificate.id == id,
      );

      if (index == -1) return;

      final certificate = _certificates[index];

      final next = [..._certificates]
        ..removeAt(index);

      // Commit before deleting photos.
      await _commit(next);

      await _cancelReminderSafely(id);

      await _deleteUnusedFiles(
        certificate.imagePaths,
      );
    });
  }

  // =====================================================
  // UNIQUE IMAGE STORAGE
  // =====================================================

  Future<Directory> _certificateDirectory() async {
    final appDir =
        await getApplicationDocumentsDirectory();

    final directory = Directory(
      '${appDir.path}/certificates',
    );

    await directory.create(recursive: true);

    return directory;
  }

  Future<String> _copyImageToAppStorage(
    String sourcePath,
    String certId,
  ) async {
    final source = File(sourcePath);

    if (!await source.exists()) {
      throw FileSystemException(
        'Certificate source image not found.',
        sourcePath,
      );
    }

    final directory =
        await _certificateDirectory();

    final filename = source.uri.pathSegments.last;
    final dotIndex = filename.lastIndexOf('.');

    final candidate = dotIndex >= 0
        ? filename.substring(dotIndex + 1)
            .toLowerCase()
        : '';

    final extension =
        RegExp(r'^[a-z0-9]{1,8}$')
                .hasMatch(candidate)
            ? candidate
            : 'jpg';

    final imageId = _uuid.v4();

    final destination = File(
      '${directory.path}/${certId}_$imageId.$extension',
    );

    try {
      await source.copy(destination.path);

      if (await destination.length() == 0) {
        throw const FileSystemException(
          'Certificate image is empty.',
        );
      }

      return destination.path;
    } catch (_) {
      try {
        if (await destination.exists()) {
          await destination.delete();
        }
      } catch (_) {
        // Best-effort cleanup.
      }

      rethrow;
    }
  }

  // =====================================================
  // SAFE FILE CLEANUP
  // =====================================================

  Future<void> _deleteUnusedFiles(
    Iterable<String> paths,
  ) async {
    if (_reloadRequired || !_loaded) {
      debugPrint(
        'Certificate image cleanup deferred pending storage recovery.',
      );
      return;
    }

    final referenced = _certificates
        .expand((certificate) => certificate.imagePaths)
        .toSet();

    for (final path in paths.toSet()) {
      if (referenced.contains(path)) continue;

      try {
        final file = File(path);

        if (!await file.exists()) continue;

        final directory =
            await _certificateDirectory();

        final root =
            await directory.resolveSymbolicLinks();

        final resolved =
            await file.resolveSymbolicLinks();

        final prefix =
            '$root${Platform.pathSeparator}';

        // Never delete files outside certificate storage.
        if (!resolved.startsWith(prefix)) {
          continue;
        }

        // Do not delete through symbolic links.
        final type = await FileSystemEntity.type(
          path,
          followLinks: false,
        );

        if (type != FileSystemEntityType.file) {
          continue;
        }

        await file.delete();
      } catch (error) {
        debugPrint(
          'Certificate file cleanup deferred: $error',
        );
      }
    }
  }

  // =====================================================
  // TRANSACTION-LIKE METADATA COMMIT
  // =====================================================

  Future<void> _commit(
    List<Certificate> next,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    final encoded = json.encode(
      next.map((certificate) {
        return certificate.toJson();
      }).toList(),
    );

    try {
      final saved = await prefs.setString(
        _storageKey,
        encoded,
      );

      if (!saved) {
        throw StateError(
          'Certificate changes could not be saved.',
        );
      }
    } catch (_) {
      // The platform may have persisted the metadata
      // even though the write reported a failure.
      // Preserve all images until storage is reloaded.
      _loaded = false;
      _reloadRequired = true;

      debugPrint(
        'Certificate metadata write requires recovery.',
      );

      rethrow;
    }

    // Update memory only after successful persistence.
    _certificates = next;
  }

  // =====================================================
  // NOTIFICATION FAILURE IS NON-FATAL
  // =====================================================

  Future<void> _scheduleReminderSafely(
    Certificate certificate,
  ) async {
    try {
      await NotificationService.instance
          .scheduleForCertificate(certificate);
    } catch (error) {
      debugPrint(
        'Certificate saved, but reminder failed: $error',
      );
    }
  }

  Future<void> _cancelReminderSafely(
    String id,
  ) async {
    try {
      await NotificationService.instance
          .cancelForCertificate(id);
    } catch (error) {
      debugPrint(
        'Certificate reminder cancellation failed: $error',
      );
    }
  }
}