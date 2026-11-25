import 'package:flutter/material.dart';
import '../data/connectivity_service.dart';
import '../data/ad_service.dart';
import '../data/subscription_repository.dart';
import '../theme/app_theme.dart';
import '../data/chat_message.dart';
import '../data/chat_repository.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  bool _retryPending = false;
  bool _adSatisfied = false;
  String? _error;
  bool _errorIsQuota = false;

  static const _welcomeText =
      "Tell me about your business or the activities you are doing, and "
      "I will help identify which Act(s) and regulation(s) apply. For "
      "example: I run a small construction company with 15 workers, we "
      "do steel work and occasional confined space inspections.";

  Future<void> _send() async {
    if (!mounted || _sending || _retryPending) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _messages.add(
        ChatMessage(role: 'user', content: text),
      );
      _controller.clear();
      _retryPending = true;
      _adSatisfied = false;
    });

    await _requestReply();
  }

  Future<void> _retry() async {
    if (!mounted || _sending || !_retryPending) return;

    await _requestReply();
  }

  void _editPendingMessage() {
    if (!mounted || _sending || !_retryPending) return;

    if (_messages.isEmpty || !_messages.last.isUser) return;

    setState(() {
      final pending = _messages.removeLast();

      _controller.text = pending.content;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );

      _retryPending = false;
      _adSatisfied = false;
      _error = null;
      _errorIsQuota = false;
    });
  }

  Future<void> _requestReply() async {
    if (!mounted || _sending || !_retryPending) return;

    setState(() {
      _sending = true;
      _error = null;
      _errorIsQuota = false;
    });

    _scrollToBottom();

    final conversation = List<ChatMessage>.unmodifiable(
      _messages,
    );

    try {
      if (ChatRepository.instance.isBusy) {
        throw const ChatException(
          'A response is already being processed. '
          'Please wait a moment.',
        );
      }

      final online = await ConnectivityService.instance
          .isOnline()
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (!online) {
        throw const ChatException(
          'No internet connection. '
          'Reconnect and retry your question.',
        );
      }

      final isPro = SubscriptionRepository.instance.isPro;

      Future<String> requestAnswer() async {
        if (!mounted) {
          throw const ChatException(
            'The conversation was closed.',
          );
        }

        if (!isPro) {
          _adSatisfied = true;
        }

        return ChatRepository.instance.sendMessage(
          conversation,
        );
      }

      final String? reply;

      if (isPro || _adSatisfied) {
        reply = await requestAnswer();
      } else {
        reply = await AdService.instance.runWithAd<String>(
          isPro: false,
          task: requestAnswer,
        );
      }

      if (!mounted) return;

      if (reply == null) {
        setState(() {
          _error =
              'Watch the advertisement through to the end '
              'to receive your answer. You can retry below.';
        });

        return;
      }

      setState(() {
        _messages.add(
          ChatMessage(role: 'assistant', content: reply ?? (throw StateError('No chatbot response received.'))),
        );

        _retryPending = false;
        _adSatisfied = false;
      });
    } on ChatException catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.message;
        _errorIsQuota = error.isQuotaExceeded;
      });
    } catch (error) {
      if (!mounted) return;

      debugPrint('Safety Chat Bot request failed.');

      setState(() {
        _error =
            'Could not complete your question. '
            'Check your connection and try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final position = _scrollController.position;

      if (!position.hasContentDimensions) return;

      final target = position.maxScrollExtent;

      if (MediaQuery.of(context).disableAnimations) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text('Safety Chat Bot', style: AppText.headline(size: 20)),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: Column(
        children: [
          Expanded(
            child: SelectionArea(
              child: _messages.isEmpty
                  ? _WelcomeCard(text: _welcomeText)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index < _messages.length) {
                          return _MessageBubble(message: _messages[index]);
                        }
                        return const _TypingIndicator();
                      },
                    ),
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: (_errorIsQuota ? AppColors.amberDeep : AppColors.red)
                  .withValues(alpha: 0.1),
              child: Row(
                children: [
                  Icon(
                    _errorIsQuota
                        ? Icons.hourglass_bottom
                        : Icons.error_outline,
                    size: 16,
                    color: _errorIsQuota ? AppColors.amberDeep : AppColors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: AppText.label(
                        size: 12,
                        color:
                            _errorIsQuota ? AppColors.amberDeep : AppColors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_retryPending && !_sending)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _editPendingMessage,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit question'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _errorIsQuota ? null : _retry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ),
                ],
              ),
            ),
          _InputBar(
            controller: _controller,
            onSend: _send,
            enabled: !_sending && !_retryPending,
            sending: _sending,
          ),
        ],
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  final String text;
  const _WelcomeCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 40, color: AppColors.steel),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: AppText.body(size: 15, color: AppColors.steel)),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppColors.amberDeep : AppColors.paperRaised,
          border: Border.all(color: AppColors.line),
        ),
        child: Text(
          message.content,
          style: AppText.body(
            size: 14,
            color: isUser ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.paperRaised,
          border: Border.all(color: AppColors.line),
        ),
        child: SizedBox(
          width: 20,
          height: 12,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.steel,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;
  final bool sending;

  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.enabled,
    required this.sending,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              style: AppText.body(size: 14),
              decoration: InputDecoration(
                hintText: sending
                    ? 'Getting your answer...'
                    : 'Describe your business or activities...',
                hintStyle: AppText.body(size: 14, color: AppColors.steel),
                filled: true,
                fillColor: AppColors.paperRaised,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppColors.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppColors.amberDeep),
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          sending
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  onPressed: enabled ? onSend : null,
                  icon: const Icon(Icons.send),
                  color: AppColors.amberDeep,
                  disabledColor: AppColors.steel.withValues(alpha: 0.4),
                ),
        ],
      ),
    );
  }
}
