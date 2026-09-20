class SavedDocument {
  final String id;
  final String name;
  final String category;
  final String filePath;
  final DateTime savedAt;

  SavedDocument({
    required this.id,
    required this.name,
    required this.category,
    required this.filePath,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'filePath': filePath,
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedDocument.fromJson(Map<String, dynamic> json) => SavedDocument(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        filePath: json['filePath'] as String,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}
