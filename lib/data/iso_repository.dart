import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/iso_clause.dart';

class IsoRepository {
  IsoRepository._();
  static final IsoRepository instance = IsoRepository._();

  List<IsoClause> _clauses = [];
  bool _loaded = false;

  Future<void>? _catalogueLoading;

  Future<void> load() {
    if (_loaded) return Future<void>.value();

    return _catalogueLoading ??=
        _loadCatalogue().whenComplete(
          () => _catalogueLoading = null,
        );
  }

  Future<void> _loadCatalogue() async {
    final raw = await rootBundle.loadString(
      'assets/data/iso_clauses.json',
    );

    final decoded = jsonDecode(raw);

    if (decoded is! List || decoded.isEmpty) {
      throw const FormatException(
        'ISO catalogue is invalid or empty.',
      );
    }

    final clauses = <IsoClause>[];
    final ids = <String>{};

    for (final item in decoded) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException(
          'Invalid ISO clause record.',
        );
      }

      final clause = IsoClause.fromJson(item);

      if (clause.id.trim().isEmpty ||
          clause.standardId.trim().isEmpty ||
          clause.standardName.trim().isEmpty) {
        throw const FormatException(
          'Incomplete ISO clause record.',
        );
      }

      if (!ids.add(clause.id)) {
        throw const FormatException(
          'Duplicate ISO clause ID.',
        );
      }

      clauses.add(clause);
    }

    _clauses = clauses;
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
