import 'package:flutter/material.dart';

import '../data/legislation_access_service.dart';
import '../data/bookmarks_repository.dart';
import '../data/entries_repository.dart';
import '../models/entry.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'detail_screen.dart';

class BookmarksScreen extends StatefulWidget {
  final bool embedded;

  const BookmarksScreen({
    super.key,
    this.embedded = false,
  });

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  List<Entry> _bookmarkedEntries() {
    final ids = BookmarksRepository.instance.bookmarkedIds;
    final all = EntriesRepository.instance.all;
    final items = all.where((e) => ids.contains(e.id)).toList();
    return EntriesRepository.instance.sortResults(items);
  }

  Future<void> _openEntry(Entry entry, List<Entry> list) async {
    final entries = List<Entry>.unmodifiable(list);

    await LegislationAccessService.instance.open(
      context: context,
      onOpen: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DetailScreen(
            entries: entries,
            initialId: entry.id,
          ),
        ));

        // Refresh after returning from the legislation reader.
        if (!mounted) return;
        setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _bookmarkedEntries();

    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      body: SafeArea(
        child: Column(
          children: [
            PremiumHeaderSurface(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (!widget.embedded) ...[
                      PremiumHeaderButton(
                        icon: AppIcons.arrowBackRounded,
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'OHS ACT & REGULATIONS',
                            style: AppText.label(
                              size: 10,
                              color: AppColors.amber,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Bookmarks',
                            style: AppText.headline(size: 18).copyWith(
                              color: AppColors.paperRaised,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No bookmarks yet.\nTap the bookmark icon on any section to save it here.',
                          textAlign: TextAlign.center,
                          style: AppText.label(size: 13, color: AppPalette.of(context).secondaryText),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: AppPalette.of(context).border),
                      itemBuilder: (context, i) {
                        final entry = items[i];
                        return InkWell(
                          onTap: () => _openEntry(entry, items),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40,
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(border: Border.all(color: AppPalette.of(context).text, width: 1)),
                                  child: Text(entry.num, style: AppText.label(size: 11, color: AppPalette.of(context).text)),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(entry.collection, style: AppText.label(size: 10.5, color: AppPalette.of(context).accent)),
                                      const SizedBox(height: 2),
                                      Text(entry.title, style: AppText.headline(size: 15, weight: FontWeight.w600).copyWith(color: AppPalette.of(context).text)),
                                    ],
                                  ),
                                ),
                                Icon(AppIcons.bookmark, size: 18, color: AppPalette.of(context).accent),
                              ],
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
