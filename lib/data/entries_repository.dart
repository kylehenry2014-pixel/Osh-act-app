import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/entry.dart';

/// The fixed display order for top-level categories.
const List<String> kCategoryOrder = [
  'Act',
  'General',
  'Health',
  'Mechanical',
  'Electrical',
  'OtherActs',
];

const Map<String, String> kCategoryLabel = {
  'Act': 'Occupational Health and Safety',
  'General': 'General',
  'Health': 'Health',
  'Mechanical': 'Mechanical',
  'Electrical': 'Electrical',
  'OtherActs': 'Other Acts',
};

/// Shorthand codes for quick-jump search, e.g. "CR 8" -> Construction Regs, Reg 8.
/// Keep this in sync with every collectionShort present in entries.json.
const Map<String, String> kCodeMap = {
  'ACT': 'OHS Act',
  'CR': 'Construction Regs',
  'GAR': 'General Admin Regs',
  'GSR': 'General Safety Regs',
  'MHI': 'Major Hazard Installation Regs',
  'HBA': 'Hazardous Biological Agents Regs',
  'EXR': 'Explosives Regs',
  'HWC': 'Hazardous Work by Children Regs',
  'FAC': 'Facilities Regs',
  'ASB': 'Asbestos Abatement Regs',
  'CDR': 'Commercial Diving Regs',
  'PAR': 'Physical Agents Regs',
  'HCA': 'Hazardous Chemical Agents Regs',
  'LEAD': 'Lead Regs',
  'NOISE': 'Noise Exposure Regs',
  'DMR': 'Driven Machinery Regs',
  'GMR': 'General Machinery Regs',
  'LEPCR': 'Lift/Escalator/Conveyor Regs',
  'CCR': 'Certificate of Competency Regs',
  'PER': 'Pressure Equipment Regs',
  'EIR': 'Electrical Installation Regs',
  'EMR': 'Electrical Machinery Regs',
  'ERG': 'Ergonomics Regs',
  'COIDA': 'COIDA',
  'MHSA': 'MHSA',
  'NEMA': 'NEMA',
};

final RegExp _codeJumpPattern =
    RegExp(r'^([A-Za-z]{2,6})\s*[.\-]?\s*(\d+[A-Za-z]?)(?:\.\d+[A-Za-z]?)?$');

class EntriesRepository {
  EntriesRepository._();
  static final EntriesRepository instance = EntriesRepository._();

  List<Entry> _entries = [];
  bool _loaded = false;

  List<Entry> get all => _entries;
  bool get isLoaded => _loaded;

  Entry? byId(String id) {
    try {
      return _entries.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/data/entries.json');
    final List<dynamic> jsonList = json.decode(raw) as List<dynamic>;
    _entries = jsonList
        .map((e) => Entry.fromJson(e as Map<String, dynamic>))
        .toList();
    _loaded = true;
  }

  List<String> categoriesPresent() {
    return kCategoryOrder.where((c) => _entries.any((e) => e.category == c)).toList();
  }

  int countInCategory(String category) =>
      _entries.where((e) => e.category == category).length;

  /// Distinct collection names within a category, in first-appearance order.
  List<String> collectionsInCategory(String category) {
    final names = <String>[];
    for (final e in _entries) {
      if (e.category == category && !names.contains(e.collection)) {
        names.add(e.collection);
      }
    }
    return names;
  }

  List<Entry> entriesInCollection(String collection) {
    final items = _entries.where((e) => e.collection == collection).toList();
    return sortedByNum(items);
  }

  List<Entry> sortedByNum(List<Entry> items) {
    final copy = List<Entry>.from(items);
    copy.sort((a, b) {
      final ka = a.numKey;
      final kb = b.numKey;
      if (ka.$1 != kb.$1) return ka.$1 - kb.$1;
      return ka.$2.compareTo(kb.$2);
    });
    return copy;
  }

  bool matchesQuery(Entry entry, String q) {
    final ql = q.toLowerCase();
    if (entry.num.toLowerCase() == ql) return true;
    return entry.searchableText.contains(ql);
  }

  /// Search results sorted the same way everywhere: category -> collection -> num.
  /// This is the single source of truth for result order, so on-screen order
  /// and Prev/Next paging order can never drift apart.
  List<Entry> sortResults(List<Entry> items) {
    final copy = List<Entry>.from(items);
    copy.sort((a, b) {
      final ca = kCategoryOrder.indexOf(a.category);
      final cb = kCategoryOrder.indexOf(b.category);
      if (ca != cb) return ca - cb;
      if (a.collection != b.collection) {
        return a.collection.compareTo(b.collection);
      }
      final ka = a.numKey;
      final kb = b.numKey;
      if (ka.$1 != kb.$1) return ka.$1 - kb.$1;
      return ka.$2.compareTo(kb.$2);
    });
    return copy;
  }

  List<Entry> search(String q) {
    if (q.trim().isEmpty) return [];
    return sortResults(_entries.where((e) => matchesQuery(e, q)).toList());
  }

  /// Tries to resolve a quick-jump code like "CR 8" or "cr8" to a single entry.
  /// Returns null if the query doesn't look like a code, or no match exists.
  Entry? tryCodeJump(String query) {
    final trimmed = query.trim();
    final match = _codeJumpPattern.firstMatch(trimmed);
    if (match == null) return null;
    final code = match.group(1)!.toUpperCase();
    final num = match.group(2)!.toUpperCase();
    final collectionShort = kCodeMap[code];
    if (collectionShort == null) return null;
    try {
      return _entries.firstWhere(
        (e) => e.collectionShort == collectionShort && e.num.toUpperCase() == num,
      );
    } catch (_) {
      return null;
    }
  }
}
