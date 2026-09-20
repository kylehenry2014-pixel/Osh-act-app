import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../data/entries_repository.dart';
import '../data/iso_repository.dart';
import '../data/translations_repository.dart';
import '../models/iso_clause.dart';
import '../theme/app_theme.dart';
import 'detail_screen.dart';

class IsoScreen extends StatefulWidget {
  const IsoScreen({super.key});

  @override
  State<IsoScreen> createState() => _IsoScreenState();
}

class _IsoScreenState extends State<IsoScreen> {
  String? _standardId;
  String? _standardName;
  IsoClause? _openClause;

  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  void _openStandard(String id, String name) {
    _tts.stop();
    setState(() {
      _standardId = id;
      _standardName = name;
      _openClause = null;
      _isSpeaking = false;
    });
  }

  void _back() {
    _tts.stop();
    setState(() {
      if (_openClause != null) {
        _openClause = null;
      } else {
        _standardId = null;
        _standardName = null;
      }
      _isSpeaking = false;
    });
  }

  Future<void> _toggleSpeech() async {
    final clause = _openClause;
    if (clause == null) return;
    if (_isSpeaking) {
      await _tts.stop();
      setState(() => _isSpeaking = false);
      return;
    }
    setState(() => _isSpeaking = true);
    final textToRead = '${clause.title}. ${clause.explanation} '
        '${clause.practicalPoints.join('. ')}';
    final lang = kSupportedLanguages.firstWhere(
      (l) => l.code == TranslationsRepository.instance.currentLanguage,
      orElse: () => kSupportedLanguages.first,
    );
    final hasVoice = await _tts.isLanguageAvailable(lang.ttsLocale);
    await _tts.setLanguage(hasVoice == true ? lang.ttsLocale : 'en-US');
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.48);
    await _tts.speak(textToRead);
  }

  Future<void> _openRelatedReg(String regId) async {
    final entry = EntriesRepository.instance.byId(regId);
    if (entry == null) return;
    final scoped = EntriesRepository.instance.entriesInCollection(entry.collection);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DetailScreen(entries: scoped, initialId: entry.id),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              title: _openClause != null
                  ? '$_standardName ${_openClause!.number}'
                  : (_standardName ?? "International Organization for Standardization"),
              onBack: (_standardId != null) ? _back : () => Navigator.of(context).pop(),
              showSpeech: _openClause != null,
              isSpeaking: _isSpeaking,
              onSpeechTap: _toggleSpeech,
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_openClause != null) return _ClauseDetail(clause: _openClause!, onOpenReg: _openRelatedReg);
    if (_standardId != null) return _ClauseList(standardId: _standardId!, onOpen: (c) => setState(() => _openClause = c));
    return _StandardsList(onOpen: _openStandard);
  }
}

class _Header extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final bool showSpeech;
  final bool isSpeaking;
  final VoidCallback onSpeechTap;
  const _Header({
    required this.title,
    required this.onBack,
    this.showSpeech = false,
    this.isSpeaking = false,
    this.onSpeechTap = _noop,
  });

  static void _noop() {}

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(
        children: [
          InkWell(onTap: onBack, child: const Icon(Icons.arrow_back, size: 18, color: AppColors.ink)),
          const SizedBox(width: 14),
          Expanded(child: Text(title, style: AppText.headline(size: 17, weight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
          if (showSpeech) ...[
            const SizedBox(width: 10),
            InkWell(
              onTap: onSpeechTap,
              child: Icon(
                isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                size: 20,
                color: isSpeaking ? AppColors.amberDeep : AppColors.ink,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StandardsList extends StatelessWidget {
  final void Function(String id, String name) onOpen;
  const _StandardsList({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final standards = IsoRepository.instance.standards();
    if (standards.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('No ISO content loaded yet.', style: AppText.label(size: 13)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: standards.length,
      itemBuilder: (context, i) {
        final (id, name) = standards[i];
        final count = IsoRepository.instance.clausesForStandard(id).length;
        return InkWell(
          onTap: () => onOpen(id, name),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.paperRaised,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: AppText.headline(size: 16, weight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text('$count clauses', style: AppText.label(size: 11)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward, size: 18, color: AppColors.steel),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ClauseList extends StatelessWidget {
  final String standardId;
  final ValueChanged<IsoClause> onOpen;
  const _ClauseList({required this.standardId, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final clauses = IsoRepository.instance.clausesForStandard(standardId);
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: clauses.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.line),
      itemBuilder: (context, i) {
        final c = clauses[i];
        return InkWell(
          onTap: () => onOpen(c),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border.all(color: AppColors.ink, width: 1)),
                  child: Text(c.number, style: AppText.label(size: 11, color: AppColors.ink)),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(c.title, style: AppText.headline(size: 15, weight: FontWeight.w600))),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ClauseDetail extends StatelessWidget {
  final IsoClause clause;
  final ValueChanged<String> onOpenReg;
  const _ClauseDetail({required this.clause, required this.onOpenReg});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
      children: [
        Text(clause.title, style: AppText.headline(size: 20)),
        const SizedBox(height: 14),
        Text(clause.explanation, style: AppText.body()),
        const SizedBox(height: 18),
        Text('IN PRACTICE, THIS USUALLY MEANS', style: AppText.label(size: 11, color: AppColors.amberDeep)),
        const SizedBox(height: 8),
        ...clause.practicalPoints.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: AppText.body()),
                  Expanded(child: Text(p, style: AppText.body())),
                ],
              ),
            )),
        if (clause.relatedRegIds.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('RELATED SA LAW', style: AppText.label(size: 11, color: AppColors.amberDeep)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: clause.relatedRegIds.map((id) {
              final entry = EntriesRepository.instance.byId(id);
              if (entry == null) return const SizedBox.shrink();
              return InkWell(
                onTap: () => onOpenReg(id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.paperRaised,
                    border: Border.all(color: AppColors.ink, width: 1.2),
                  ),
                  child: Text(
                    '${entry.collectionShort} ${entry.num}',
                    style: AppText.label(size: 11, color: AppColors.ink),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
