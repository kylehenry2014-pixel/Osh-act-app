import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import '../data/ad_service.dart';
import '../data/download_allowance_service.dart';
import '../data/subscription_repository.dart';
import '../data/toolbox_talks_repository.dart';
import '../models/toolbox_talk_entry.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_download_button.dart';

Future<String> _extractAssetToTemp(String assetPath, String fileName) async {
  final data = await rootBundle.load(assetPath);
  final tempDir = await getTemporaryDirectory();
  final folder = await tempDir.createTemp('ohs_talk_');

  try {
    final safeName = fileName
        .replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');

    final name = safeName.isEmpty ||
            safeName == '.' ||
            safeName == '..'
        ? 'toolbox_talk.docx'
        : safeName;

    final file = File('${folder.path}/$name');

    await file.writeAsBytes(
      data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      ),
      flush: true,
    );

    if (await file.length() == 0) {
      throw StateError('The toolbox talk is empty.');
    }

    return file.path;
  } catch (error) {
    try {
      await folder.delete(recursive: true);
    } catch (cleanupError) {
      debugPrint('Toolbox cleanup failed: $cleanupError');
    }

    rethrow;
  }
}

class ToolboxTalksScreen extends StatefulWidget {
  const ToolboxTalksScreen({super.key});

  @override
  State<ToolboxTalksScreen> createState() => _ToolboxTalksScreenState();
}

class _ToolboxTalksScreenState extends State<ToolboxTalksScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openDetail(ToolboxTalkEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppPalette.of(context).background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
      builder: (context) => _TalkDetailSheet(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ToolboxTalksRepository.instance.categories;
    final talkOfDay = categories.isEmpty
        ? null
        : ToolboxTalksRepository.instance.talkOfTheDay();
    final searching = _query.trim().isNotEmpty;
    final searchResults = searching
        ? ToolboxTalksRepository.instance.search(query: _query)
        : <ToolboxTalkEntry>[];

    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: PremiumSectionAppBar(
        title: 'Toolbox Talks',
        titleSize: 20,
      ),
      body: Column(
        children: [
          if (!searching && talkOfDay != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _PremiumDailyTalkCard(
                entry: talkOfDay,
                onTap: () => _openDetail(talkOfDay),
              ),
            ),
          if (!searching && talkOfDay == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Toolbox Talks are currently unavailable.',
                style: AppText.body(
                  size: 13,
                  color: AppPalette.of(context).secondaryText,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: AppText.body(size: 14, color: AppPalette.of(context).text),
              decoration: InputDecoration(
                hintText: 'Search all 1000 talks...',
                hintStyle: AppText.body(size: 14, color: AppPalette.of(context).secondaryText),
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: AppPalette.of(context).surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppPalette.of(context).border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppPalette.of(context).border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: AppPalette.of(context).accent),
                ),
              ),
            ),
          ),
          if (searching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${searchResults.length} result${searchResults.length == 1 ? '' : 's'}',
                  style: AppText.label(size: 11, color: AppPalette.of(context).secondaryText),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: searching
                ? (searchResults.isEmpty
                    ? Center(
                        child: Text(
                          'No talks match your search.',
                          style: AppText.body(size: 14, color: AppPalette.of(context).secondaryText),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: searchResults.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final entry = searchResults[index];
                          return _TalkListTile(
                              entry: entry, onTap: () => _openDetail(entry));
                        },
                      ))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      final count = ToolboxTalksRepository.instance
                          .search(category: category)
                          .length;
                      return InkWell(
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) =>
                                _CategoryTalksScreen(category: category),
                          ));
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppPalette.of(context).surface,
                            border: Border.all(color: AppPalette.of(context).border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      category,
                                      style: AppText.headline(
                                          size: 15, weight: FontWeight.w600).copyWith(color: AppPalette.of(context).text),
                                    ),
                                    const SizedBox(height: 3),
                                    Text('$count talks',
                                        style: AppText.label(size: 11, color: AppPalette.of(context).secondaryText)),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, color: AppPalette.of(context).secondaryText),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PremiumDailyTalkCard extends StatelessWidget {
  final ToolboxTalkEntry entry;
  final VoidCallback onTap;

  const _PremiumDailyTalkCard({
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateLabel = MaterialLocalizations.of(context)
        .formatShortMonthDay(now)
        .toUpperCase();

    final compact =
        MediaQuery.sizeOf(context).height < 650 ||
        MediaQuery.textScalerOf(context).scale(14) > 18;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.amberDeep,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF353930),
                Color(0xFF141611),
              ],
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const HazardStripe(height: 6),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.today_outlined,
                            color: AppColors.amber,
                            size: 17,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'DAILY SAFETY BRIEFING',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label(
                                size: 10,
                                color: AppColors.amber,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.amber.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.amber.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                            child: Text(
                              dateLabel,
                              style: AppText.label(
                                size: 10,
                                color: AppColors.amber,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Toolbox Talk of the Day',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.headline(
                          size: 21,
                          weight: FontWeight.w700,
                        ).copyWith(
                          color: AppColors.paperRaised,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.amber.withValues(alpha: 0.65),
                              AppColors.amber.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        entry.category.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label(
                          size: 10,
                          color: AppColors.amber,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.headline(
                          size: 18,
                          weight: FontWeight.w600,
                        ).copyWith(
                          color: AppColors.paperRaised,
                          height: 1.25,
                        ),
                      ),
                      if (!compact &&
                          entry.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          entry.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(
                            size: 12,
                            color: const Color(0xFFC3C5BB),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Container(
                        constraints: const BoxConstraints(
                          minHeight: 46,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFE8B84F),
                              Color(0xFFC18A24),
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                "View today's toolbox talk",
                                style: AppText.headline(
                                  size: 12,
                                  weight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: AppColors.ink,
                              size: 19,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const HazardStripe(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _CategoryTalksScreen extends StatelessWidget {
  final String category;
  const _CategoryTalksScreen({required this.category});

  void _openDetail(BuildContext context, ToolboxTalkEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppPalette.of(context).background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
      builder: (context) => _TalkDetailSheet(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final talks = ToolboxTalksRepository.instance.search(category: category);
    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: PremiumSectionAppBar(
        title: category,
        titleSize: 18,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: talks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final entry = talks[index];
          return _TalkListTile(
              entry: entry, onTap: () => _openDetail(context, entry));
        },
      ),
    );
  }
}

class _TalkListTile extends StatelessWidget {
  final ToolboxTalkEntry entry;
  final VoidCallback onTap;
  const _TalkListTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppPalette.of(context).surface,
          border: Border.all(color: AppPalette.of(context).border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: AppText.headline(size: 14, weight: FontWeight.w600).copyWith(color: AppPalette.of(context).text),
                  ),
                  const SizedBox(height: 3),
                  Text(entry.category, style: AppText.label(size: 10.5, color: AppPalette.of(context).secondaryText)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppPalette.of(context).secondaryText),
          ],
        ),
      ),
    );
  }
}

class _TalkDetailSheet extends StatelessWidget {
  final ToolboxTalkEntry entry;
  const _TalkDetailSheet({required this.entry});

  static bool _documentBusy = false;

  static const _openFeatureKey = 'toolbox_talk_open';
  static const _saveFeatureKey = 'toolbox_talk_save';

  Future<void> _openTalk(BuildContext context) async {
    if (!context.mounted || _documentBusy) return;

    _documentBusy = true;

    try {
      await _performOpenTalk(context);
    } catch (error) {
      debugPrint('Toolbox talk opening failed: $error');

      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open this toolbox talk. Please try again.',
            ),
          ),
        );
      }
    } finally {
      _documentBusy = false;
    }
  }

  Future<void> _performOpenTalk(BuildContext context) async {
    if (!SubscriptionRepository.instance.isPro) {
      final adCount =
          await AdService.instance.nextRequiredAdCount(_openFeatureKey);
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Watch an ad to continue'),
          content: Text(
            adCount == 1
                ? 'Watch a short ad to open this document.'
                : 'Watch $adCount ads back-to-back to open this document.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Watch'),
            ),
          ],
        ),
      );
      if (!context.mounted || confirmed != true) return;

      final earned = await AdService.instance.watchAds(adCount);
      if (!context.mounted) return;
      if (!earned) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              adCount == 1
                  ? "You'll need to watch the ad through to the end to unlock this."
                  : "You'll need to watch all $adCount ads through to the end to unlock this.",
            ),
          ),
        );
        return;
      }
      await AdService.instance.recordUnlockedRequest(_openFeatureKey);
      if (!context.mounted) return;
    }

    final path = await _extractAssetToTemp(
      entry.assetPath,
      entry.fileName,
    );

    if (!context.mounted ||
        ModalRoute.of(context)?.isCurrent != true) {
      await _cleanupTalkFile(path);
      return;
    }

    final result = await OpenFile.open(path);

    if (result.type != ResultType.done) {
      await _cleanupTalkFile(path);
    }
    if (context.mounted && result.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not open this document: ${result.message}')),
      );
    }
  }

  Future<void> _cleanupTalkFile(String path) async {
    try {
      final folder = File(path).parent;

      if (folder.uri.pathSegments.any(
        (part) => part.startsWith('ohs_talk_'),
      )) {
        await folder.delete(recursive: true);
      }
    } catch (error) {
      debugPrint('Toolbox temporary cleanup failed: $error');
    }
  }

  void _showMessage(BuildContext context, String message) {
    if (!context.mounted) return;

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _saveTalk(BuildContext context) async {
    if (!context.mounted || _documentBusy) {
      throw StateError('Another document operation is active.');
    }

    _documentBusy = true;

    String? temporaryPath;

    try {
      // Prepare the document and complete the required ad
      // before consuming a download allowance.

      if (!context.mounted) {
        throw const _TalkSaveCancelled();
      }

      if (!SubscriptionRepository.instance.isPro) {
        final adCount = await AdService.instance
            .nextRequiredAdCount(_saveFeatureKey);

        if (!context.mounted ||
            ModalRoute.of(context)?.isCurrent != true) {
          throw const _TalkSaveCancelled();
        }

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Watch an ad to continue'),
            content: Text(
              adCount == 1
                  ? 'Watch a short ad to save this document.'
                  : 'Watch $adCount ads back-to-back to save this document.',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(true),
                child: const Text('Watch'),
              ),
            ],
          ),
        );

        if (!context.mounted || confirmed != true) {
          throw const _TalkSaveCancelled();
        }

        final earned =
            await AdService.instance.watchAds(adCount);

        if (!context.mounted) {
          throw const _TalkSaveCancelled();
        }

        if (!earned) {
          _showMessage(
            context,
            'Complete the required ads to save this document.',
          );

          throw const _TalkSaveCancelled();
        }

        await AdService.instance
            .recordUnlockedRequest(_saveFeatureKey);
      }

      if (!context.mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        throw const _TalkSaveCancelled();
      }

      temporaryPath = await _extractAssetToTemp(
        entry.assetPath,
        entry.fileName,
      );

      if (!context.mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        throw const _TalkSaveCancelled();
      }

      final preparedFile = File(temporaryPath);

      if (!await preparedFile.exists() ||
          await preparedFile.length() == 0) {
        throw StateError('The prepared document is unavailable.');
      }

      if (!context.mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        throw const _TalkSaveCancelled();
      }

      // The document and advertisement requirements are complete.
      await DownloadAllowanceService.instance.checkAndConsume();

      if (!context.mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        throw const _TalkSaveCancelled();
      }

      final savedPath = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: temporaryPath,
        ),
      );

      if (savedPath == null || savedPath.isEmpty) {
        _showMessage(
          context,
          'Save cancelled. Your download allowance was already used.',
        );
        throw const _TalkSaveCancelled();
      }

      _showMessage(context, 'Toolbox talk saved successfully.');
    } on _TalkSaveCancelled {
      // Reset the animated button without reporting success.
      rethrow;
    } on DownloadLimitException catch (error) {
      _showMessage(context, error.message);
      rethrow;
    } catch (error) {
      debugPrint('Toolbox talk save failed: $error');

      _showMessage(
        context,
        'Could not save this talk. Please try again.',
      );

      rethrow;
    } finally {
      if (temporaryPath != null) {
        await _cleanupTalkFile(temporaryPath);
      }

      _documentBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + bottomInset + bottomSafeArea,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.category,
              style: AppText.label(size: 11, color: AppPalette.of(context).accent)),
          const SizedBox(height: 4),
          Text(entry.title, style: AppText.headline(size: 19).copyWith(color: AppPalette.of(context).text)),
          const SizedBox(height: 12),
          Text(entry.description,
              style: AppText.body(size: 14, color: AppPalette.of(context).secondaryText)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openTalk(context),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Open'),
                ),
              ),
              const SizedBox(width: 12),
              AnimatedDownloadButton(
                onDownload: () => _saveTalk(context),
                idleLabel: 'Save',
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class _TalkSaveCancelled implements Exception {
  const _TalkSaveCancelled();

  @override
  String toString() => 'Toolbox talk save cancelled.';
}