import 'package:flutter/material.dart';
import '../data/bookmarks_repository.dart';
import '../data/entries_repository.dart';
import '../models/entry.dart';
import '../theme/app_theme.dart';
import 'detail_screen.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

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
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DetailScreen(entries: list, initialId: entry.id),
    ));
    // Refresh in case a bookmark was removed from within the detail screen.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = _bookmarkedEntries();

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.arrow_back, size: 18, color: AppColors.ink),
                  ),
                  const SizedBox(width: 14),
                  Text('Bookmarks', style: AppText.headline(size: 18, weight: FontWeight.w600)),
                ],
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
                          style: AppText.label(size: 13),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.line),
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
                                  decoration: BoxDecoration(border: Border.all(color: AppColors.ink, width: 1)),
                                  child: Text(entry.num, style: AppText.label(size: 11, color: AppColors.ink)),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(entry.collection, style: AppText.label(size: 10.5, color: AppColors.amberDeep)),
                                      const SizedBox(height: 2),
                                      Text(entry.title, style: AppText.headline(size: 15, weight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.bookmark, size: 18, color: AppColors.amberDeep),
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
