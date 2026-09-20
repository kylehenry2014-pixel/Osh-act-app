/// A single toolbox talk topic - a short discussion point for a daily/weekly
/// site safety briefing.
class ToolboxTalk {
  final String id;
  final String num;
  final String category;
  final String title;
  final String content;

  const ToolboxTalk({
    required this.id,
    required this.num,
    required this.category,
    required this.title,
    required this.content,
  });

  factory ToolboxTalk.fromJson(Map<String, dynamic> json) => ToolboxTalk(
        id: json['id'] as String,
        num: json['num'] as String,
        category: json['category'] as String,
        title: json['title'] as String,
        content: json['content'] as String,
      );
}
