import 'package:flutter/material.dart';
import '../data/entries_repository.dart';
import '../data/translations_repository.dart';
import '../theme/app_theme.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  final _repo = TranslationsRepository.instance;

  bool _changingLanguage = false;

  Future<void> _selectLanguage(String code) async {
    if (!mounted ||
        _changingLanguage ||
        _repo.currentLanguage == code) {
      return;
    }

    setState(() => _changingLanguage = true);

    try {
      await _repo.setLanguage(code);
    } catch (error) {
      debugPrint('Language change failed: $error');

      if (!mounted) return;

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to change language. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _changingLanguage = false);
      } else {
        _changingLanguage = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalEntries = EntriesRepository.instance.all.length;

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
              child: Row(
                children: [
                  InkWell(onTap: () => Navigator.of(context).pop(), child: const Icon(Icons.arrow_back, size: 18, color: AppColors.ink)),
                  const SizedBox(width: 14),
                  Text('Language', style: AppText.headline(size: 17, weight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
              child: Text(
                'The English text is taken from the official Act and Regulations. Other languages are unofficial translations provided for convenience. For legal purposes, consult the official Government Gazette.',
                style: AppText.label(size: 11),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: kSupportedLanguages.length,
                itemBuilder: (context, i) {
                  final lang = kSupportedLanguages[i];
                  final selected = _repo.currentLanguage == lang.code;
                  final translatedCount = lang.code == 'en' ? totalEntries : _repo.translatedCount(lang.code);

                  return Opacity(
                    opacity: lang.available ? 1 : 0.5,
                    child: InkWell(
                      onTap: lang.available && !_changingLanguage ? () => _selectLanguage(lang.code) : null,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.paperRaised,
                          border: Border.all(color: selected ? AppColors.amberDeep : AppColors.line, width: selected ? 1.5 : 1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(lang.label, style: AppText.headline(size: 16, weight: FontWeight.w600)),
                                  const SizedBox(height: 3),
                                  Text(
                                    lang.available
                                        ? (lang.code == 'en' ? 'Official text' : '$translatedCount of $totalEntries translated')
                                        : 'Coming soon - pending native-speaker review',
                                    style: AppText.label(size: 11),
                                  ),
                                ],
                              ),
                            ),
                            if (selected) const Icon(Icons.check_circle, size: 20, color: AppColors.amberDeep),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
