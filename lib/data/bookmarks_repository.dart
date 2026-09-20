import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores which entries are bookmarked and any personal notes the user has
/// written against a specific entry, persisted locally on the device.
class BookmarksRepository {
  BookmarksRepository._();
  static final BookmarksRepository instance = BookmarksRepository._();

  static const _bookmarksKey = 'bookmarked_entry_ids';
  static const _notesKey = 'entry_notes';

  Set<String> _bookmarkedIds = {};
  Map<String, String> _notes = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _bookmarkedIds = (prefs.getStringList(_bookmarksKey) ?? []).toSet();
    final rawNotes = prefs.getString(_notesKey);
    if (rawNotes != null && rawNotes.isNotEmpty) {
      final decoded = json.decode(rawNotes) as Map<String, dynamic>;
      _notes = decoded.map((k, v) => MapEntry(k, v as String));
    }
    _loaded = true;
  }

  bool isBookmarked(String entryId) => _bookmarkedIds.contains(entryId);

  Set<String> get bookmarkedIds => _bookmarkedIds;

  Future<void> toggleBookmark(String entryId) async {
    if (_bookmarkedIds.contains(entryId)) {
      _bookmarkedIds.remove(entryId);
    } else {
      _bookmarkedIds.add(entryId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_bookmarksKey, _bookmarkedIds.toList());
  }

  String? noteFor(String entryId) => _notes[entryId];

  Future<void> setNote(String entryId, String note) async {
    if (note.trim().isEmpty) {
      _notes.remove(entryId);
    } else {
      _notes[entryId] = note;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_notesKey, json.encode(_notes));
  }
}
