import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/certificate.dart';
import 'notification_service.dart';

/// Stores saved certificates (name, photo pages, expiry date) locally on the
/// device, and keeps their expiry-reminder notifications in sync. Entirely
/// offline - certificate photos never leave the device. A certificate can
/// hold multiple photo pages (e.g. a full multi-page medical pack).
class CertificatesRepository {
  CertificatesRepository._();
  static final CertificatesRepository instance = CertificatesRepository._();

  static const _storageKey = 'saved_certificates';
  static const _uuid = Uuid();

  List<Certificate> _certificates = [];
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      final List<dynamic> decoded = json.decode(raw) as List<dynamic>;
      _certificates = decoded
          .map((e) => Certificate.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    _loaded = true;
  }

  /// Certificates sorted by expiry date, soonest first - expired and
  /// expiring-soon items naturally float to the top.
  List<Certificate> get all {
    final list = [..._certificates];
    list.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return list;
  }

  /// Copies picked/captured image files into the app's permanent local
  /// storage (so they survive even if the original camera-roll photos or
  /// temp files are later deleted), then creates and saves the certificate
  /// record covering all of them as pages of one document.
  Future<Certificate> add({
    required String name,
    required List<String> sourceImagePaths,
    required DateTime expiryDate,
    String? notes,
  }) async {
    assert(sourceImagePaths.isNotEmpty, 'A certificate needs at least one page');
    final id = _uuid.v4();
    final savedPaths = <String>[];
    for (var i = 0; i < sourceImagePaths.length; i++) {
      savedPaths.add(await _copyImageToAppStorage(sourceImagePaths[i], id, i));
    }

    final cert = Certificate(
      id: id,
      name: name,
      imagePaths: savedPaths,
      expiryDate: expiryDate,
      createdAt: DateTime.now(),
      notes: notes,
    );

    _certificates.add(cert);
    await _persist();
    await NotificationService.instance.scheduleForCertificate(cert);
    return cert;
  }

  /// Appends more pages to an existing certificate - e.g. adding the rest
  /// of a medical pack scanned in a second sitting.
  Future<Certificate> addPages(String certId, List<String> newSourcePaths) async {
    final index = _certificates.indexWhere((c) => c.id == certId);
    if (index == -1) throw StateError('Certificate not found: $certId');
    final existing = _certificates[index];

    final newSavedPaths = <String>[];
    for (var i = 0; i < newSourcePaths.length; i++) {
      final pageIndex = existing.imagePaths.length + i;
      newSavedPaths.add(await _copyImageToAppStorage(newSourcePaths[i], certId, pageIndex));
    }

    final updated = existing.copyWith(imagePaths: [...existing.imagePaths, ...newSavedPaths]);
    _certificates[index] = updated;
    await _persist();
    return updated;
  }

  /// Removes a single page from a certificate and deletes its file. A
  /// certificate must keep at least one page - remove the whole certificate
  /// via [delete] instead if removing the last page.
  Future<Certificate> removePage(String certId, String imagePath) async {
    final index = _certificates.indexWhere((c) => c.id == certId);
    if (index == -1) throw StateError('Certificate not found: $certId');
    final existing = _certificates[index];
    if (existing.imagePaths.length <= 1) {
      throw StateError('Cannot remove the last page - delete the certificate instead');
    }

    final updated = existing.copyWith(
      imagePaths: existing.imagePaths.where((p) => p != imagePath).toList(),
    );
    _certificates[index] = updated;
    await _persist();

    final file = File(imagePath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {
        // Non-fatal - an orphaned file is a minor storage cost.
      }
    }
    return updated;
  }

  Future<void> update(Certificate updated) async {
    final index = _certificates.indexWhere((c) => c.id == updated.id);
    if (index == -1) return;
    _certificates[index] = updated;
    await _persist();
    await NotificationService.instance.scheduleForCertificate(updated);
  }

  Future<void> delete(String id) async {
    final cert = _certificates.where((c) => c.id == id).firstOrNull;
    _certificates.removeWhere((c) => c.id == id);
    await _persist();
    await NotificationService.instance.cancelForCertificate(id);
    if (cert != null) {
      for (final path in cert.imagePaths) {
        final file = File(path);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {
            // Non-fatal - an orphaned file is a minor storage cost, not
            // worth failing the delete operation over.
          }
        }
      }
    }
  }

  Future<String> _copyImageToAppStorage(String sourcePath, String certId, int pageIndex) async {
    final appDir = await getApplicationDocumentsDirectory();
    final certsDir = Directory('${appDir.path}/certificates');
    if (!await certsDir.exists()) {
      await certsDir.create(recursive: true);
    }
    final extension = sourcePath.split('.').last;
    final destPath = '${certsDir.path}/${certId}_p$pageIndex.$extension';
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(_certificates.map((c) => c.toJson()).toList());
    await prefs.setString(_storageKey, encoded);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
