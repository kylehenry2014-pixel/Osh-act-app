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
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  return file.path;
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
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
      builder: (context) => _TalkDetailSheet(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final talkOfDay = ToolboxTalksRepository.instance.talkOfTheDay();
    final categories = ToolboxTalksRepository.instance.categories;
    final searching = _query.trim().isNotEmpty;
    final searchResults = searching
        ? ToolboxTalksRepository.instance.search(query: _query)
        : <ToolboxTalkEntry>[];

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text('Toolbox Talks', style: AppText.headline(size: 20)),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: Column(
        children: [
          if (!searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: InkWell(
                onTap: () => _openDetail(talkOfDay),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.amberDeep,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.today_outlined, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Talk of the Day',
                              style:
                                  AppText.label(size: 11, color: Colors.white),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              talkOfDay.title,
                              style: AppText.headline(
                                      size: 15, weight: FontWeight.w600)
                                  .copyWith(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: AppText.body(size: 14),
              decoration: InputDecoration(
                hintText: 'Search all 1000 talks...',
                hintStyle: AppText.body(size: 14, color: AppColors.steel),
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: AppColors.paperRaised,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
            ),
          ),
          if (searching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${searchResults.length} result${searchResults.length == 1 ? '' : 's'}',
                  style: AppText.label(size: 11),
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
                          style: AppText.body(size: 14, color: AppColors.steel),
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
                            color: AppColors.paperRaised,
                            border: Border.all(color: AppColors.line),
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
                                          size: 15, weight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 3),
                                    Text('$count talks',
                                        style: AppText.label(size: 11)),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, color: AppColors.steel),
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

class _CategoryTalksScreen extends StatelessWidget {
  final String category;
  const _CategoryTalksScreen({required this.category});

  void _openDetail(BuildContext context, ToolboxTalkEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.paper,
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
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text(category, style: AppText.headline(size: 18)),
        iconTheme: const IconThemeData(color: AppColors.ink),
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
          color: AppColors.paperRaised,
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: AppText.headline(size: 14, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(entry.category, style: AppText.label(size: 10.5)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.steel),
          ],
        ),
      ),
    );
  }
}

class _TalkDetailSheet extends StatelessWidget {
  final ToolboxTalkEntry entry;
  const _TalkDetailSheet({required this.entry});

  static const _openFeatureKey = 'toolbox_talk_open';
  static const _saveFeatureKey = 'toolbox_talk_save';

  Future<void> _openTalk(BuildContext context) async {
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
      if (confirmed != true) return;

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

    final path = await _extractAssetToTemp(entry.assetPath, entry.fileName);
    final result = await OpenFile.open(path);
    if (context.mounted && result.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not open this document: ${result.message}')),
      );
    }
  }

  Future<void> _saveTalk(BuildContext context) async {
    // Shared daily download allowance (2/day free, 20/day Pro) - checked
    // first so we don't make a free user watch an ad only to find out
    // they were already over their daily download limit.
    try {
      await DownloadAllowanceService.instance.checkAndConsume();
    } on DownloadLimitException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
      return;
    }

    try {
      if (!SubscriptionRepository.instance.isPro) {
        final adCount =
            await AdService.instance.nextRequiredAdCount(_saveFeatureKey);
        if (!context.mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Watch an ad to continue'),
            content: Text(
              adCount == 1
                  ? 'Watch a short ad to save this document.'
                  : 'Watch $adCount ads back-to-back to save this document.',
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
        if (confirmed != true) return;

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
        await AdService.instance.recordUnlockedRequest(_saveFeatureKey);
        if (!context.mounted) return;
      }

      final path = await _extractAssetToTemp(entry.assetPath, entry.fileName);
      await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(sourceFilePath: path),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save this talk: $e')),
        );
      }
      rethrow;
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
              style: AppText.label(size: 11, color: AppColors.amberDeep)),
          const SizedBox(height: 4),
          Text(entry.title, style: AppText.headline(size: 19)),
          const SizedBox(height: 12),
          Text(entry.description,
              style: AppText.body(size: 14, color: AppColors.steel)),
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
