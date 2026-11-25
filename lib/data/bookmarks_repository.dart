import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores bookmarks and personal notes locally.
/// Damaged records are preserved rather than silently overwritten.
class BookmarksRepository {
  BookmarksRepository._();

  static final BookmarksRepository instance =
      BookmarksRepository._();

  static const _bookmarksKey = 'bookmarked_entry_ids';
  static const _notesKey = 'entry_notes';

  Set<String> _bookmarkedIds = {};
  Map<String, String> _notes = {};

  bool _loaded = false;
  bool _bookmarksDamaged = false;
  bool _notesDamaged = false;

  Future<void>? _loading;
  Future<void> _queue = Future<void>.value();

  bool get hasStorageDamage =>
      _bookmarksDamaged || _notesDamaged;

  Future<T> _serialise<T>(
    Future<T> Function() operation,
  ) {
    final result = _queue.then((_) => operation());

    _queue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );

    return result;
  }

  Future<void> load() {
    if (_loaded) return Future<void>.value();

    return _loading ??=
        _loadOnce().whenComplete(() => _loading = null);
  }

  Future<void> _loadOnce() async {
    final prefs = await SharedPreferences.getInstance();

    if (_reloadRequired) {
      await prefs.reload();
      _reloadRequired = false;
    }

    final bookmarks = <String>{};
    final notes = <String, String>{};

    var bookmarksDamaged = false;
    var notesDamaged = false;

    // Bookmarks and notes are loaded independently.
    try {
      final raw = prefs.get(_bookmarksKey);

      if (raw != null) {
        if (raw is! List ||
            raw.any((item) => item is! String)) {
          throw const FormatException(
            'Invalid bookmark storage.',
          );
        }

        bookmarks.addAll(raw.cast<String>());
      }
    } catch (_) {
      bookmarksDamaged = true;
      debugPrint('Bookmark storage requires recovery.');
    }

    try {
      final raw = prefs.get(_notesKey);

      if (raw != null) {
        if (raw is! String || raw.trim().isEmpty) {
          throw const FormatException(
            'Invalid note storage.',
          );
        }

        final decoded = jsonDecode(raw);

        if (decoded is! Map<String, dynamic>) {
          throw const FormatException(
            'Invalid note structure.',
          );
        }

        for (final entry in decoded.entries) {
          final value = entry.value;

          if (value is! String) {
            notesDamaged = true;
            continue;
          }

          notes[entry.key] = value;
        }
      }
    } catch (_) {
      notesDamaged = true;
      debugPrint('Personal note storage requires recovery.');
    }

    _bookmarkedIds = bookmarks;
    _notes = notes;

    _bookmarksDamaged = bookmarksDamaged;
    _notesDamaged = notesDamaged;

    _loaded = true;
  }

  bool isBookmarked(String entryId) =>
      _bookmarkedIds.contains(entryId);

  Set<String> get bookmarkedIds =>
      Set<String>.unmodifiable(_bookmarkedIds);

  Future<void> toggleBookmark(String entryId) {
    return _serialise(() async {
      await load();

      if (_bookmarksDamaged) {
        throw StateError(
          'Saved bookmarks require recovery before editing.',
        );
      }

      if (entryId.trim().isEmpty) {
        throw ArgumentError('Invalid entry ID.');
      }

      final next = Set<String>.from(_bookmarkedIds);

      if (!next.remove(entryId)) {
        next.add(entryId);
      }

      final prefs = await SharedPreferences.getInstance();

      try {
        final saved = await prefs.setStringList(
          _bookmarksKey,
          next.toList(),
        );

        if (!saved) {
          throw StateError('Bookmark storage write failed.');
        }
      } catch (_) {
        // The platform write result is uncertain.
        // Prevent further writes until storage is reloaded.
        _loaded = false;
        await _reloadAfterFailure(prefs);
        rethrow;
      }

      _bookmarkedIds = next;
    });
  }

  String? noteFor(String entryId) => _notes[entryId];

  Future<void> setNote(String entryId, String note) {
    return _serialise(() async {
      await load();

      if (_notesDamaged) {
        throw StateError(
          'Saved notes require recovery before editing.',
        );
      }

      if (entryId.trim().isEmpty) {
        throw ArgumentError('Invalid entry ID.');
      }

      final next = Map<String, String>.from(_notes);

      if (note.trim().isEmpty) {
        next.remove(entryId);
      } else {
        next[entryId] = note;
      }

      final prefs = await SharedPreferences.getInstance();

      try {
        final saved = await prefs.setString(
          _notesKey,
          jsonEncode(next),
        );

        if (!saved) {
          throw StateError('Personal note storage write failed.');
        }
      } catch (_) {
        _loaded = false;
        await _reloadAfterFailure(prefs);
        rethrow;
      }

      _notes = next;
    });
  }

  bool _reloadRequired = false;

  Future<void> _reloadAfterFailure(
    SharedPreferences prefs,
  ) async {
    _reloadRequired = true;

    try {
      await prefs.reload();
      _reloadRequired = false;
    } catch (_) {
      debugPrint('Bookmark preferences reload failed.');
    }
  }
}