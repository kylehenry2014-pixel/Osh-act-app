import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../data/bookmarks_repository.dart';
import '../data/translations_repository.dart';
import '../models/entry.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

/// Shows a single entry's full text, with Prev/Next buttons that page
/// through exactly the [entries] list the caller scoped this to (e.g. the
/// current regulation set, or the current search results) - never the
/// whole app's entries. Also lets the user bookmark the entry, keep a
/// personal note, and listen to the text read aloud, all saved or handled
/// locally on the device (text-to-speech uses the phone's own speech
/// engine, no server or account involved). If the app's language is set
/// to something other than English and a translation exists for this
/// entry, that translation is shown instead, with a disclaimer that only
/// the English text is legally authoritative. If no translation exists
/// yet for this specific entry, the English text is shown with a note.
class DetailScreen extends StatefulWidget {
  final List<Entry> entries;
  final String initialId;

  const DetailScreen({super.key, required this.entries, required this.initialId});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late int _index;
  final _bookmarks = BookmarksRepository.instance;
  final _translations = TranslationsRepository.instance;
  late TextEditingController _noteController;
  bool _notesOpen = false;

  final FlutterTts _tts = FlutterTts();

  bool _isSpeaking = false;
  bool _bookmarkBusy = false;
  bool _disposed = false;

  int _speechRevision = 0;

  Future<void> _speechQueue = Future<void>.value();

  bool _speechIsCurrent(int revision) {
    return mounted &&
        !_disposed &&
        revision == _speechRevision;
  }

  Future<void> _enqueueSpeech(
    Future<void> Function() operation,
  ) {
    final next = _speechQueue.then((_) async {
      try {
        await operation();
      } catch (error) {
        debugPrint('Text-to-speech operation failed: $error');
      }
    });

    _speechQueue = next;
    return next;
  }

  void _speechFinished() {
    if (!mounted || _disposed || !_isSpeaking) return;

    setState(() => _isSpeaking = false);
  }

  @override
  void initState() {
    super.initState();
    _index = widget.entries.indexWhere((e) => e.id == widget.initialId);
    if (_index < 0) _index = 0;
    _noteController = TextEditingController(text: _bookmarks.noteFor(_entry.id) ?? '');
    _tts.setCompletionHandler(_speechFinished);
    _tts.setCancelHandler(_speechFinished);

    _tts.setErrorHandler((message) {
      debugPrint('Text-to-speech error: $message');
      _speechFinished();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _speechRevision++;

    _tts.setCompletionHandler(() {});
    _tts.setCancelHandler(() {});
    _tts.setErrorHandler((_) {});

    unawaited(_enqueueSpeech(() async {
      await _tts.stop();
    }));

    _noteController.dispose();
    super.dispose();
  }

  Entry get _entry => widget.entries[_index];

  /// The title/body actually displayed, accounting for the current
  /// language: a translation if one exists for this entry, otherwise the
  /// original English text.
  (String title, String body, bool isTranslated) get _displayText {
    final t = _translations.translationFor(_entry.id);
    if (t != null) return (t.title, t.body, true);
    return (_entry.title, _entry.body, false);
  }

  Future<void> _toggleSpeech() async {
    if (!mounted || _disposed) return;

    final revision = ++_speechRevision;

    if (_isSpeaking) {
      setState(() => _isSpeaking = false);

      await _enqueueSpeech(() async {
        await _tts.stop();
      });

      return;
    }

    final (title, body, _) = _displayText;
    final textToRead = '$title. $body';

    final lang = kSupportedLanguages.firstWhere(
      (l) => l.code == _translations.currentLanguage,
      orElse: () => kSupportedLanguages.first,
    );

    setState(() => _isSpeaking = true);

    await _enqueueSpeech(() async {
      if (!_speechIsCurrent(revision)) return;

      try {
        final hasVoice =
            await _tts.isLanguageAvailable(lang.ttsLocale);

        if (!_speechIsCurrent(revision)) return;

        await _tts.setLanguage(
          hasVoice == true ? lang.ttsLocale : 'en-US',
        );

        if (!_speechIsCurrent(revision)) return;

        await _tts.setPitch(1.0);

        if (!_speechIsCurrent(revision)) return;

        await _tts.setSpeechRate(0.48);

        if (!_speechIsCurrent(revision)) return;

        final result = await _tts.speak(textToRead);

        if (!_speechIsCurrent(revision)) {
          await _tts.stop();
          return;
        }

        if (result != 1) {
          setState(() => _isSpeaking = false);
        }
      } catch (error) {
        debugPrint('Unable to read legislation aloud: $error');

        if (!mounted || !_speechIsCurrent(revision)) return;

        setState(() => _isSpeaking = false);

        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to read this section aloud. Please try again.',
            ),
          ),
        );
      }
    });
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.entries.length) return;
    _speechRevision++;

    unawaited(_enqueueSpeech(() async {
      await _tts.stop();
    }));

    setState(() {
      _index = next;
      _noteController.text = _bookmarks.noteFor(_entry.id) ?? '';
      _notesOpen = false;
      _isSpeaking = false;
    });
  }

  Future<void> _toggleBookmark() async {
    if (!mounted || _bookmarkBusy) return;

    final entryId = _entry.id;
    _bookmarkBusy = true;

    try {
      await _bookmarks.toggleBookmark(entryId);

      if (!mounted) return;

      setState(() {});
    } catch (error) {
      debugPrint('Bookmark update failed: $error');

      if (!mounted) return;

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Unable to update bookmark. Please try again.'),
        ),
      );
    } finally {
      _bookmarkBusy = false;
    }
  }

  Future<void> _saveNote(String value) async {
    if (!mounted || _disposed) return;

    final entryId = _entry.id;

    try {
      await _bookmarks.setNote(entryId, value);
    } catch (error) {
      debugPrint('Unable to save legislation note: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    final (displayTitle, displayBody, isTranslated) = _displayText;
    final paragraphs = displayBody.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final bookmarked = _bookmarks.isBookmarked(entry.id);
    final showLanguageNote = _translations.currentLanguage != 'en';

    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      body: SafeArea(
        child: Column(
          children: [
            _BackBar(
              onTap: () => Navigator.of(context).pop(),
              bookmarked: bookmarked,
              onBookmarkTap: _toggleBookmark,
              isSpeaking: _isSpeaking,
              onSpeechTap: _toggleSpeech,
            ),
            Expanded(
              child: TextSelectionTheme(
                data: TextSelectionTheme.of(context).copyWith(
                  cursorColor: AppPalette.of(context).accent,
                  selectionColor: AppColors.amber.withValues(alpha: 0.35),
                  selectionHandleColor: AppPalette.of(context).accent,
                ),
                child: SelectionArea(
                  key: ValueKey(
                    '${entry.id}:${_translations.currentLanguage}',
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.collection,
                              style: AppText.label(
                                size: 12,
                                color: AppPalette.of(context).accent,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Section / Regulation ${entry.num}',
                              style: AppText.label(size: 11, color: AppPalette.of(context).secondaryText),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              displayTitle,
                              style: AppText.headline(size: 22).copyWith(color: AppPalette.of(context).text),
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: AppPalette.of(context).strongBorder,
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
                          children: [
                            if (showLanguageNote)
                              SelectionContainer.disabled(
                                child: _LanguageNote(
                                  isTranslated: isTranslated,
                                ),
                              ),
                            ...paragraphs.map(
                              (p) => Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Text(
                                  p,
                                  style: AppText.body(color: AppPalette.of(context).text),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectionContainer.disabled(
                              child: _NotesSection(
                                open: _notesOpen,
                                onToggle: () => setState(
                                  () => _notesOpen = !_notesOpen,
                                ),
                                controller: _noteController,
                                onChanged: _saveNote,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _PrevNextBar(
              canPrev: _index > 0,
              canNext: _index < widget.entries.length - 1,
              onPrev: () => _go(-1),
              onNext: () => _go(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackBar extends StatelessWidget {
  final VoidCallback onTap;
  final bool bookmarked;
  final VoidCallback onBookmarkTap;
  final bool isSpeaking;
  final VoidCallback onSpeechTap;

  const _BackBar({
    required this.onTap,
    required this.bookmarked,
    required this.onBookmarkTap,
    required this.isSpeaking,
    required this.onSpeechTap,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumHeaderSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'LEGISLATION READER',
                style: AppText.label(
                  size: 10,
                  color: AppColors.amber,
                ).copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            Row(
              children: [
                PremiumHeaderButton(
                  icon: AppIcons.arrowBackRounded,
                  tooltip: 'Back',
                  onPressed: onTap,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Read legislation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.headline(size: 16).copyWith(
                      color: AppColors.paperRaised,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PremiumHeaderButton(
                  icon: isSpeaking
                      ? AppIcons.stopCircleOutlined
                      : AppIcons.volumeUpRounded,
                  tooltip: isSpeaking
                      ? 'Stop reading'
                      : 'Read aloud',
                  onPressed: onSpeechTap,
                  active: isSpeaking,
                ),
                const SizedBox(width: 8),
                PremiumHeaderButton(
                  icon: bookmarked
                      ? AppIcons.bookmarkRounded
                      : AppIcons.bookmarkBorderRounded,
                  tooltip: bookmarked
                      ? 'Remove bookmark'
                      : 'Save bookmark',
                  onPressed: onBookmarkTap,
                  active: bookmarked,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageNote extends StatelessWidget {
  final bool isTranslated;
  const _LanguageNote({required this.isTranslated});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.of(context).surface,
        border: Border.all(color: AppPalette.of(context).border),
      ),
      child: Text(
        isTranslated
            ? 'This is an unofficial translation provided for convenience. Only the English text is legally authoritative.'
            : 'Not yet translated into this language - showing the official English text.',
        style: AppText.label(size: 11, color: AppPalette.of(context).secondaryText),
      ),
    );
  }
}

class _NotesSection extends StatelessWidget {
  final bool open;
  final VoidCallback onToggle;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _NotesSection({
    required this.open,
    required this.onToggle,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasNote = controller.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: AppPalette.of(context).border),
        const SizedBox(height: 8),
        InkWell(
          onTap: onToggle,
          child: Row(
            children: [
              Icon(AppIcons.editNote, size: 18, color: AppPalette.of(context).secondaryText),
              const SizedBox(width: 6),
              Text(
                hasNote ? 'My note' : 'Add a note',
                style: AppText.label(size: 12, color: AppPalette.of(context).secondaryText),
              ),
            ],
          ),
        ),
        if (open) ...[
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            onChanged: onChanged,
            minLines: 2,
            maxLines: 6,
            style: AppText.body(size: 14, color: AppPalette.of(context).text),
            decoration: InputDecoration(
              hintText: 'How does this apply to your site or company...',
              hintStyle: AppText.label(size: 12, color: AppPalette.of(context).secondaryText.withValues(alpha: 0.7)),
              filled: true,
              fillColor: AppPalette.of(context).surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: BorderSide(color: AppPalette.of(context).text, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: BorderSide(color: AppPalette.of(context).text, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: BorderSide(color: AppPalette.of(context).accent, width: 1.5),
              ),
            ),
          ),
        ] else if (hasNote) ...[
          const SizedBox(height: 6),
          Text(controller.text, style: AppText.body(size: 13, color: AppPalette.of(context).secondaryText), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ],
    );
  }
}

class _PrevNextBar extends StatelessWidget {
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _PrevNextBar({
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
      child: Row(
        children: [
          Expanded(child: _navButton(context, '← PREVIOUS', canPrev, onPrev)),
          const SizedBox(width: 12),
          Expanded(child: _navButton(context, 'NEXT →', canNext, onNext)),
        ],
      ),
    );
  }

  Widget _navButton(BuildContext context, String label, bool enabled, VoidCallback onTap) {
    final palette = AppPalette.of(context);

    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(color: palette.text, width: 1.5),
          ),
          child: InkWell(
            onTap: enabled ? onTap : null,
            splashColor: palette.accent.withValues(alpha: 0.18),
            highlightColor: palette.accent.withValues(alpha: 0.10),
            focusColor: palette.accent.withValues(alpha: 0.14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              child: Text(
                label,
                style: AppText.label(
                  size: 12,
                  color: palette.secondaryText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
