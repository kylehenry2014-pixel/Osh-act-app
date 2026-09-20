/// A single clause of explanatory content for an ISO standard (e.g. ISO
/// 45001 clause 6.1.2). This is original guidance content written to
/// explain what a clause requires in practice - never a reproduction of
/// the standard's own text, which is copyrighted and commercially
/// licensed, unlike the freely-reproducible OHS Act and regulations.
class IsoClause {
  final String id;
  final String standardId;
  final String standardName;
  final String number;
  final String title;
  final String explanation;
  final List<String> practicalPoints;

  /// IDs of entries in EntriesRepository (OHS Act/regulation sections)
  /// that relate to this clause, e.g. ['gar-8'].
  final List<String> relatedRegIds;

  const IsoClause({
    required this.id,
    required this.standardId,
    required this.standardName,
    required this.number,
    required this.title,
    required this.explanation,
    required this.practicalPoints,
    required this.relatedRegIds,
  });

  factory IsoClause.fromJson(Map<String, dynamic> json) {
    return IsoClause(
      id: json['id'] as String,
      standardId: json['standardId'] as String,
      standardName: json['standardName'] as String,
      number: json['number'] as String,
      title: json['title'] as String,
      explanation: json['explanation'] as String,
      practicalPoints: (json['practicalPoints'] as List<dynamic>).map((e) => e as String).toList(),
      relatedRegIds: (json['relatedRegIds'] as List<dynamic>).map((e) => e as String).toList(),
    );
  }
}
