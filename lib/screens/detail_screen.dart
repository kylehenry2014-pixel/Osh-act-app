import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../data/bookmarks_repository.dart';
import '../data/translations_repository.dart';
import '../models/entry.dart';
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

  @override
  void initState() {
    super.initState();
    _index = widget.entries.indexWhere((e) => e.id == widget.initialId);
    if (_index < 0) _index = 0;
    _noteController = TextEditingController(text: _bookmarks.noteFor(_entry.id) ?? '');
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  @override
  void dispose() {
    _tts.stop();
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
    if (_isSpeaking) {
      await _tts.stop();
      setState(() => _isSpeaking = false);
      return;
    }
    setState(() => _isSpeaking = true);
    final (title, body, _) = _displayText;
    final textToRead = '$title. $body';
    final lang = kSupportedLanguages.firstWhere(
      (l) => l.code == _translations.currentLanguage,
      orElse: () => kSupportedLanguages.first,
    );
    final hasVoice = await _tts.isLanguageAvailable(lang.ttsLocale);
    await _tts.setLanguage(hasVoice == true ? lang.ttsLocale : 'en-US');
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.48);
    await _tts.speak(textToRead);
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.entries.length) return;
    _tts.stop();
    setState(() {
      _index = next;
      _noteController.text = _bookmarks.noteFor(_entry.id) ?? '';
      _notesOpen = false;
      _isSpeaking = false;
    });
  }

  Future<void> _toggleBookmark() async {
    await _bookmarks.toggleBookmark(_entry.id);
    setState(() {});
  }

  Future<void> _saveNote(String value) async {
    await _bookmarks.setNote(_entry.id, value);
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    final (displayTitle, displayBody, isTranslated) = _displayText;
    final paragraphs = displayBody.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final bookmarked = _bookmarks.isBookmarked(entry.id);
    final showLanguageNote = _translations.currentLanguage != 'en';

    return Scaffold(
      backgroundColor: AppColors.paper,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.collection, style: AppText.label(size: 12, color: AppColors.amberDeep)),
                  const SizedBox(height: 4),
                  Text('Section / Regulation ${entry.num}', style: AppText.label(size: 11)),
                  const SizedBox(height: 8),
                  Text(displayTitle, style: AppText.headline(size: 22)),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.lineStrong),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
                children: [
                  if (showLanguageNote) _LanguageNote(isTranslated: isTranslated),
                  ...paragraphs.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text(p, style: AppText.body()),
                      )),
                  const SizedBox(height: 8),
                  _NotesSection(
                    open: _notesOpen,
                    onToggle: () => setState(() => _notesOpen = !_notesOpen),
                    controller: _noteController,
                    onChanged: _saveNote,
                  ),
                ],
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
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_back, size: 16, color: AppColors.ink),
                    const SizedBox(width: 8),
                    Text('BACK', style: AppText.label(size: 12, color: AppColors.ink)),
                  ],
                ),
              ),
            ),
          ),
          InkWell(
            onTap: onSpeechTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Icon(
                isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                size: 20,
                color: isSpeaking ? AppColors.amberDeep : AppColors.ink,
              ),
            ),
          ),
          InkWell(
            onTap: onBookmarkTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: Icon(
                bookmarked ? Icons.bookmark : Icons.bookmark_border,
                size: 20,
                color: bookmarked ? AppColors.amberDeep : AppColors.ink,
              ),
            ),
          ),
        ],
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
        color: AppColors.paperRaised,
        border: Border.all(color: AppColors.line),
      ),
      child: Text(
        isTranslated
            ? 'This is an unofficial translation provided for convenience. Only the English text is legally authoritative.'
            : 'Not yet translated into this language - showing the official English text.',
        style: AppText.label(size: 11, color: AppColors.steel),
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
        const Divider(color: AppColors.line),
        const SizedBox(height: 8),
        InkWell(
          onTap: onToggle,
          child: Row(
            children: [
              Icon(Icons.edit_note, size: 18, color: AppColors.steel),
              const SizedBox(width: 6),
              Text(
                hasNote ? 'My note' : 'Add a note',
                style: AppText.label(size: 12, color: AppColors.steel),
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
            style: AppText.body(size: 14),
            decoration: InputDecoration(
              hintText: 'How does this apply to your site or company...',
              hintStyle: AppText.label(size: 12, color: AppColors.steel.withValues(alpha: 0.7)),
              filled: true,
              fillColor: AppColors.paperRaised,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: const BorderSide(color: AppColors.ink, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: const BorderSide(color: AppColors.ink, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: const BorderSide(color: AppColors.amberDeep, width: 1.5),
              ),
            ),
          ),
        ] else if (hasNote) ...[
          const SizedBox(height: 6),
          Text(controller.text, style: AppText.body(size: 13, color: AppColors.steel), maxLines: 2, overflow: TextOverflow.ellipsis),
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
          Expanded(child: _navButton('← PREVIOUS', canPrev, onPrev)),
          const SizedBox(width: 12),
          Expanded(child: _navButton('NEXT →', canNext, onNext)),
        ],
      ),
    );
  }

  Widget _navButton(String label, bool enabled, VoidCallback onTap) {
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.paperRaised,
            border: Border.all(color: AppColors.ink, width: 1.5),
          ),
          child: Text(label, style: AppText.label(size: 12)),
        ),
      ),
    );
  }
}
