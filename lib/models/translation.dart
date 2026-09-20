/// A translation of one entry's title and body into another language.
/// This is always an unofficial, non-binding translation - the English
/// text bundled in entries.json remains the only legally authoritative
/// version, since it is sourced directly from the Government Gazette.
class EntryTranslation {
  final String entryId;
  final String language;
  final String title;
  final String body;

  const EntryTranslation({
    required this.entryId,
    required this.language,
    required this.title,
    required this.body,
  });

  factory EntryTranslation.fromJson(Map<String, dynamic> json) {
    return EntryTranslation(
      entryId: json['entryId'] as String,
      language: json['language'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
    );
  }
}
