import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Display order of the sign groups. Any other group name found in the
/// data is listed after these.
const List<String> kSignGroupOrder = [
  'Warning',
  'Prohibition',
  'Mandatory',
  'Safe condition and emergency',
];

class SafetySign {
  final String id;
  final String label;
  final String group;
  final String file;

  const SafetySign({
    required this.id,
    required this.label,
    required this.group,
    required this.file,
  });

  factory SafetySign.fromJson(Map<String, dynamic> json) => SafetySign(
        id: (json['id'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
        group: (json['group'] ?? '').toString(),
        file: (json['file'] ?? '').toString(),
      );
}

/// Loads the bundled safety sign library (assets/data/signage.json).
/// Each record has an id, a label, a group and the asset path of its image.
class SignageRepository {
  SignageRepository._();
  static final SignageRepository instance = SignageRepository._();

  List<SafetySign> _signs = [];
  bool _loaded = false;

  List<SafetySign> get all => _signs;
  bool get isLoaded => _loaded;

  static String _norm(String s) => s.trim().toLowerCase();

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
      'assets/data/signage.json',
    );

    final decoded = jsonDecode(raw);
    List<dynamic>? records;

    // Retain compatibility with both existing
    // catalogue structures.
    if (decoded is List) {
      records = decoded;
    } else if (decoded is Map) {
      for (final value in decoded.values) {
        if (value is List) {
          records = value;
          break;
        }
      }
    }

    if (records == null || records.isEmpty) {
      throw const FormatException(
        'Signage catalogue is invalid or empty.',
      );
    }

    final signs = <SafetySign>[];
    final ids = <String>{};

    for (final item in records) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException(
          'Invalid safety sign record.',
        );
      }

      for (final key in ['id', 'label', 'group', 'file']) {
        final value = item[key];

        if (value is! String || value.trim().isEmpty) {
          throw const FormatException(
            'Incomplete safety sign record.',
          );
        }
      }

      final sign = SafetySign.fromJson(item);

      if (!ids.add(sign.id)) {
        throw const FormatException(
          'Duplicate safety sign ID.',
        );
      }

      signs.add(sign);
    }

    _signs = signs;
    _loaded = true;
  }

  bool inGroup(SafetySign sign, String group) =>
      _norm(sign.group) == _norm(group);

  List<SafetySign> signsInGroup(String group) =>
      _signs.where((s) => inGroup(s, group)).toList();

  /// The standard groups first (in fixed order), then any extra group
  /// names that appear in the data, so no sign is ever left out.
  List<String> get groups {
    final result = List<String>.from(kSignGroupOrder);
    for (final s in _signs) {
      final known = result.any((g) => _norm(g) == _norm(s.group));
      if (!known && s.group.trim().isNotEmpty) {
        result.add(s.group.trim());
      }
    }
    return result;
  }
}
