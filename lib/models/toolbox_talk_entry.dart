class ToolboxTalkEntry {
  final String category;
  final String title;
  final String description;
  final String fullTitle;
  final String assetPath;

  ToolboxTalkEntry({
    required this.category,
    required this.title,
    required this.description,
    required this.fullTitle,
    required this.assetPath,
  });

  factory ToolboxTalkEntry.fromJson(Map<String, dynamic> json) =>
      ToolboxTalkEntry(
        category: json['category'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        fullTitle: json['fullTitle'] as String,
        assetPath: json['assetPath'] as String,
      );

  /// The file name a saved copy of this talk should use - derived from the
  /// asset path so it stays consistent with what's on disk.
  String get fileName => assetPath.split('/').last;
}
