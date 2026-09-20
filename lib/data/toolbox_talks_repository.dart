import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/toolbox_talk_entry.dart';

/// Loads the bundled Toolbox Talks index (1000 entries across 50
/// categories) and provides search/filter over it. The actual .docx
/// files themselves are bundled as flat assets under assets/toolbox_talks/;
/// this repository only holds their metadata (category, title,
/// description, asset path) for listing/searching in the UI.
class ToolboxTalksRepository {
  static final ToolboxTalksRepository instance = ToolboxTalksRepository._();
  ToolboxTalksRepository._();

  List<ToolboxTalkEntry> _all = [];
  List<String> _categories = [];

  List<ToolboxTalkEntry> get all => List.unmodifiable(_all);
  List<String> get categories => List.unmodifiable(_categories);

  Future<void> load() async {
    final raw =
        await rootBundle.loadString('assets/toolbox_talks_index_v2.json');
    final list = jsonDecode(raw) as List;
    _all = list
        .map((e) => ToolboxTalkEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    final catSet = <String>{};
    for (final entry in _all) {
      catSet.add(entry.category);
    }
    _categories = catSet.toList()..sort();
  }

  /// Returns entries matching [query] (case-insensitive, checked against
  /// title, description, and category) and optionally narrowed to
  /// [category] (pass null or 'All' for every category).
  List<ToolboxTalkEntry> search({String query = '', String? category}) {
    final q = query.trim().toLowerCase();
    return _all.where((entry) {
      final matchesCategory =
          category == null || category == 'All' || entry.category == category;
      if (!matchesCategory) return false;
      if (q.isEmpty) return true;
      return entry.title.toLowerCase().contains(q) ||
          entry.description.toLowerCase().contains(q) ||
          entry.category.toLowerCase().contains(q);
    }).toList();
  }

  /// A deterministic "talk of the day" - same topic all day, changes daily,
  /// cycles through all 1000 topics roughly every 2.7 years. No backend needed.
  ToolboxTalkEntry talkOfTheDay() {
    if (_all.isEmpty) {
      throw StateError('ToolboxTalksRepository.load() must be called first');
    }
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    return _all[dayOfYear % _all.length];
  }
}
