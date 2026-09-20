class Entry {
  final String id;
  final String category;
  final String collection;
  final String collectionShort;
  final String num;
  final String title;
  final String tags;
  final String body;

  Entry({
    required this.id,
    required this.category,
    required this.collection,
    required this.collectionShort,
    required this.num,
    required this.title,
    required this.tags,
    required this.body,
  });

  factory Entry.fromJson(Map<String, dynamic> json) {
    return Entry(
      id: json['id'] as String,
      category: json['category'] as String,
      collection: json['collection'] as String,
      collectionShort: json['collectionShort'] as String,
      num: json['num'] as String,
      title: json['title'] as String,
      tags: (json['tags'] ?? '') as String,
      body: json['body'] as String,
    );
  }

  /// Lowercased blob of title + body + tags, used for text search.
  String get searchableText =>
      '$title $body $tags'.toLowerCase();

  /// Splits [num] into a numeric prefix and an alphabetic suffix so that
  /// "13A" sorts correctly after "13" and before "13B" (natural sort),
  /// rather than a naive string or int sort.
  (int, String) get numKey {
    final match = RegExp(r'^(\d+)([A-Za-z]*)$').firstMatch(num);
    if (match == null) return (999999, num);
    return (int.parse(match.group(1)!), match.group(2) ?? '');
  }
}
