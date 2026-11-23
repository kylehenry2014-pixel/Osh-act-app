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

  Future<void> load() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/data/signage.json');
    final decoded = json.decode(raw);
    List<dynamic> list = <dynamic>[];
    if (decoded is List) {
      list = decoded;
    } else if (decoded is Map) {
      for (final v in decoded.values) {
        if (v is List) {
          list = v;
          break;
        }
      }
    }
    _signs = list
        .whereType<Map>()
        .map((m) => SafetySign.fromJson(Map<String, dynamic>.from(m)))
        .where((s) => s.file.isNotEmpty)
        .toList();
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
