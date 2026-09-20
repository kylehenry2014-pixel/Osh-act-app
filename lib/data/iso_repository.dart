import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/iso_clause.dart';

class IsoRepository {
  IsoRepository._();
  static final IsoRepository instance = IsoRepository._();

  List<IsoClause> _clauses = [];
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/data/iso_clauses.json');
    final List<dynamic> jsonList = json.decode(raw) as List<dynamic>;
    _clauses = jsonList.map((e) => IsoClause.fromJson(e as Map<String, dynamic>)).toList();
    _loaded = true;
  }

  List<IsoClause> get all => _clauses;

  /// Distinct standards, in first-appearance order, as (id, name) pairs.
  List<(String, String)> standards() {
    final seen = <String>{};
    final result = <(String, String)>[];
    for (final c in _clauses) {
      if (seen.add(c.standardId)) result.add((c.standardId, c.standardName));
    }
    return result;
  }

  List<IsoClause> clausesForStandard(String standardId) =>
      _clauses.where((c) => c.standardId == standardId).toList();

  IsoClause? byId(String id) {
    try {
      return _clauses.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }
}
