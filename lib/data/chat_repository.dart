import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_message.dart';

class ChatRepository {
  static final ChatRepository instance = ChatRepository._();
  ChatRepository._();

  FirebaseFunctions get _functions => FirebaseFunctions.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  Future<void> _ensureSignedIn() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
  }

  Future<String> sendMessage(List<ChatMessage> conversation) async {
    if (Firebase.apps.isEmpty) {
      throw const ChatException(
          'The Safety Chat Bot isn\'t connected yet. Please try again later.');
    }
    try {
      await _ensureSignedIn();
      final callable = _functions.httpsCallable(
        'chatWithSafetyBot',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
      );
      final result = await callable.call<Map<String, dynamic>>({
        'messages': conversation.map((m) => m.toJson()).toList(),
      });
      final reply = result.data['reply'] as String?;
      if (reply == null || reply.isEmpty) {
        throw const ChatException(
            'The assistant did not return a response. Please try again.');
      }
      return reply;
    } on FirebaseFunctionsException catch (e) {
      throw ChatException(_friendlyMessage(e),
          isQuotaExceeded: e.code == 'resource-exhausted');
    } catch (_) {
      throw const ChatException(
          'Could not reach the Safety Chat Bot. Check your connection and try again.');
    }
  }

  String _friendlyMessage(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'resource-exhausted':
        return e.message ?? "You've reached today's free question limit.";
      case 'unavailable':
      case 'deadline-exceeded':
        return 'The assistant is taking too long to respond. Please try again.';
      case 'unauthenticated':
        return 'Still connecting - please try again in a moment.';
      default:
        return 'Something went wrong talking to the assistant. Please try again.';
    }
  }
}

class ChatException implements Exception {
  final String message;
  final bool isQuotaExceeded;
  const ChatException(this.message, {this.isQuotaExceeded = false});
  @override
  String toString() => message;
}
