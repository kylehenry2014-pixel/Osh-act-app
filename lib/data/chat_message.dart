/// A single message in a Safety Chat Bot conversation.
class ChatMessage {
  final String role; // "user" or "assistant"
  final String content;

  const ChatMessage({required this.role, required this.content});

  bool get isUser => role == 'user';

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}
