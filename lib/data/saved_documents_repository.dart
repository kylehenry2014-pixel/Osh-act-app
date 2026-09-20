import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/saved_document.dart';

/// Lets users keep a permanent local copy of a downloadable Word document
/// (a checklist or toolbox talk) inside the app itself, rather than only
/// having a one-off download that's easy to lose track of. Documents are
/// copied into the app's own storage folder and listed in a "My Documents"
/// screen; metadata (name, category, saved date) is kept in
/// shared_preferences, same pattern as BookmarksRepository.
class SavedDocumentsRepository {
  static final SavedDocumentsRepository instance = SavedDocumentsRepository._();
  SavedDocumentsRepository._();

  static const _prefsKey = 'saved_documents';
  final List<SavedDocument> _documents = [];

  List<SavedDocument> get all {
    final sorted = List<SavedDocument>.from(_documents)
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return List.unmodifiable(sorted);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _documents.clear();
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _documents.addAll(
        list.map((e) => SavedDocument.fromJson(e as Map<String, dynamic>)),
      );
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_documents.map((d) => d.toJson()).toList()),
    );
  }

  /// Copies the file at [sourcePath] into the app's permanent storage and
  /// records it as saved. [name] is the display name shown in "My
  /// Documents" (e.g. "Scaffold Inspection Checklist"), [category] groups
  /// documents in the list (e.g. "Checklist", "Toolbox Talk").
  Future<SavedDocument> saveDocument({
    required String sourcePath,
    required String name,
    required String category,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final docsDir = Directory('${appDir.path}/saved_documents');
    if (!await docsDir.exists()) {
      await docsDir.create(recursive: true);
    }
    final id = const Uuid().v4();
    final extension =
        sourcePath.contains('.') ? sourcePath.split('.').last : 'docx';
    final destPath = '${docsDir.path}/$id.$extension';
    await File(sourcePath).copy(destPath);

    final document = SavedDocument(
      id: id,
      name: name,
      category: category,
      filePath: destPath,
      savedAt: DateTime.now(),
    );
    _documents.add(document);
    await _persist();
    return document;
  }

  Future<void> delete(String id) async {
    final index = _documents.indexWhere((d) => d.id == id);
    if (index == -1) return;
    final document = _documents[index];
    final file = File(document.filePath);
    if (await file.exists()) {
      await file.delete();
    }
    _documents.removeAt(index);
    await _persist();
  }
}
