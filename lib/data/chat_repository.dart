import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'chat_message.dart';

class ChatRepository {
  static final ChatRepository instance = ChatRepository._();

  ChatRepository._();

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instance;

  FirebaseAuth get _auth => FirebaseAuth.instance;

  Future<void>? _signInFuture;
  Future<String>? _activeRequest;
  String? _activeRequestKey;

  bool get isBusy => _activeRequest != null;

  Future<void> _ensureSignedIn() {
    if (_auth.currentUser != null) {
      return Future<void>.value();
    }

    return _signInFuture ??= _signIn().whenComplete(
      () => _signInFuture = null,
    );
  }

  Future<void> _signIn() async {
    await _auth.signInAnonymously();
  }

  Future<String> sendMessage(
    List<ChatMessage> conversation,
  ) async {
    if (Firebase.apps.isEmpty) {
      throw const ChatException(
        'The Safety Chat Bot is not connected yet. '
        'Please try again later.',
      );
    }

    if (conversation.isEmpty) {
      throw const ChatException(
        'Please enter a message first.',
      );
    }

    if (!conversation.last.isUser ||
        conversation.any((message) =>
            (message.role != 'user' &&
                message.role != 'assistant') ||
            message.content.trim().isEmpty)) {
      throw const ChatException(
        'The conversation contains an invalid message.',
      );
    }

    // Snapshot the conversation so changes to the UI
    // cannot modify an active request.
    final messages = conversation
        .map((message) => message.toJson())
        .toList();

    final requestKey = jsonEncode(messages);

    final active = _activeRequest;

    if (active != null) {
      if (_activeRequestKey == requestKey) {
        return active;
      }

      throw const ChatException(
        'Please wait for the current response '
        'before sending another message.',
      );
    }

    _activeRequestKey = requestKey;

    final request = _send(messages);

    _activeRequest = request;

    try {
      return await request;
    } finally {
      _activeRequest = null;
      _activeRequestKey = null;
    }
  }

  Future<String> _send(
    List<dynamic> messages,
  ) async {
    try {
      await _ensureSignedIn().timeout(
        const Duration(seconds: 15),
      );

      final callable = _functions.httpsCallable(
        'chatWithSafetyBot',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 45),
        ),
      );

      final result =
          await callable.call<Map<String, dynamic>>({
        'messages': messages,
      });

      final reply = result.data['reply'];

      if (reply is! String || reply.trim().isEmpty) {
        throw const ChatException(
          'The assistant did not return a response. '
          'Please try again.',
        );
      }

      return reply.trim();

    } on ChatException {
      rethrow;

    } on FirebaseFunctionsException catch (error) {
      throw ChatException(
        _friendlyMessage(error),
        isQuotaExceeded:
            error.code == 'resource-exhausted',
      );

    } on TimeoutException {
      throw const ChatException(
        'Connecting to the assistant took too long. '
        'Please try again.',
      );

    } on FirebaseAuthException {
      throw const ChatException(
        'Could not connect your account. '
        'Please try again in a moment.',
      );

    } catch (_) {
      throw const ChatException(
        'Could not reach the Safety Chat Bot. '
        'Check your connection and try again.',
      );
    }
  }

  String _friendlyMessage(
    FirebaseFunctionsException error,
  ) {
    switch (error.code) {
      case 'resource-exhausted':
        return error.message ??
            'You have reached your daily question limit.';

      case 'deadline-exceeded':
        return 'The assistant is taking too long '
            'to respond. Please try again.';

      case 'unavailable':
        return 'The assistant is temporarily unavailable. '
            'Please try again shortly.';

      case 'unauthenticated':
        return 'Still connecting. '
            'Please try again in a moment.';

      case 'permission-denied':
        return 'Access could not be verified. '
            'Please try again.';

      default:
        return 'Something went wrong talking to '
            'the assistant. Please try again.';
    }
  }
}

class ChatException implements Exception {
  final String message;
  final bool isQuotaExceeded;

  const ChatException(
    this.message, {
    this.isQuotaExceeded = false,
  });

  @override
  String toString() => message;
}