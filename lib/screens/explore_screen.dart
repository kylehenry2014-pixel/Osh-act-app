import 'package:flutter/material.dart';

import '../data/legislation_access_service.dart';
import '../data/entries_repository.dart';
import '../models/entry.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/appearance_controller.dart';
import 'notifications_screen.dart';
import 'detail_screen.dart';

class ExploreScreen extends StatefulWidget {
  final bool autoFocusSearch;
  const ExploreScreen({super.key, required this.autoFocusSearch});

  @override
  State<ExploreScreen> createState() => ExploreScreenState();
}

class ExploreScreenState extends State<ExploreScreen> {

  final _repo = EntriesRepository.instance;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  static bool _openingEntry = false;

  String? _browseCategory;
  String? _browseCollection;

  /// Rating prompts are permitted only on the top-level Home screen.
  bool get canShowRatingPrompt =>
      mounted &&
      !_openingEntry &&
      _browseCategory == null &&
      _browseCollection == null &&
      _searchController.text.trim().isEmpty &&
      !_searchFocus.hasFocus;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Called by the Home tab when tapped while already active, to jump
  /// back to the top-level category cards.
  void resetToTop() {
    if (!mounted) return;
    setState(() {
      _browseCategory = null;
      _browseCollection = null;
      _searchController.clear();
    });
  }

  /// Handles the phone's physical/gesture back button. Steps up one level
  /// of the drill-down (section list -> category menu -> home grid)
  /// instead of letting the system pop the whole app. Returns true if it
  /// handled the back press, false if already at the top level (meaning
  /// the caller should fall through to normal exit/tab-switch behaviour).
  bool handleBack() {
    if (!mounted) return false;
    if (_browseCollection != null) {
      setState(() => _browseCollection = null);
      return true;
    }
    if (_browseCategory != null) {
      setState(() => _browseCategory = null);
      return true;
    }
    return false;
  }

  Future<void> _openEntry(
    Entry entry,
    List<Entry> pagingList,
  ) async {
    if (!mounted || _openingEntry) return;

    _openingEntry = true;

    final entries = List<Entry>.unmodifiable(pagingList);

    try {
      await LegislationAccessService.instance.open(
        context: context,
        onOpen: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailScreen(
                entries: entries,
                initialId: entry.id,
              ),
            ),
          );
        },
      );
    } finally {
      _openingEntry = false;
    }
  }

  void _onSearchChanged(String q) {
    final trimmed = q.trim();
    if (trimmed.isEmpty) {
      setState(() {});
      return;
    }
    final jump = _repo.tryCodeJump(trimmed);
    if (jump != null && !_openingEntry) {
      _searchController.clear();
      _searchFocus.unfocus();
      final scoped = _repo.entriesInCollection(jump.collection);
      _openEntry(jump, scoped);
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _Masthead(showBreadcrumb: query.isEmpty),
          _SearchField(
            controller: _searchController,
            focusNode: _searchFocus,
            autoFocus: widget.autoFocusSearch,
            onChanged: _onSearchChanged,
            onClear: () {
              _searchController.clear();
              setState(() {});
            },
          ),
          if (query.isEmpty) _buildBreadcrumb(),
          Expanded(
            child: _buildAnimatedBody(query),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    final crumbs = <Widget>[
      _crumb(
          'All',
          () => setState(() {
                _browseCategory = null;
                _browseCollection = null;
              }),
          isLink: _browseCategory != null),
    ];
    if (_browseCategory != null) {
      crumbs.add(_arrow());
      crumbs.add(_crumb(
        kCategoryLabel[_browseCategory] ?? _browseCategory!,
        () => setState(() => _browseCollection = null),
        isLink: _browseCollection != null,
      ));
    }
    if (_browseCollection != null) {
      crumbs.add(_arrow());
      crumbs.add(_crumb(_browseCollection!, null, isLink: false));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
      child:
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: crumbs),
    );
  }

  Widget _arrow() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text('›', style: AppText.label(size: 12, color: AppPalette.of(context).secondaryText)),
      );

  Widget _crumb(String text, VoidCallback? onTap, {required bool isLink}) {
    final style = AppText.label(
        size: 12, color: isLink ? AppPalette.of(context).accent : AppPalette.of(context).secondaryText);
    if (!isLink || onTap == null) return Text(text, style: style);
    return InkWell(onTap: onTap, child: Text(text, style: style));
  }

  Widget _buildAnimatedBody(String query) {
    final reducedMotion =
        MediaQuery.of(context).disableAnimations;

    final Object pageIdentity = query.isNotEmpty
        ? const ('search',)
        : ('browse', _browseCategory, _browseCollection);

    final duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return ClipRect(
      child: AnimatedSwitcher(
        duration: duration,
        reverseDuration: Duration.zero,
        switchInCurve: Curves.easeOutCubic,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            fit: StackFit.expand,
            children: [
              for (final child in previousChildren)
                IgnorePointer(
                  child: ExcludeSemantics(child: child),
                ),
              if (currentChild != null) currentChild,
            ],
          );
        },
        transitionBuilder: (child, animation) {
          if (reducedMotion) return child;

          return FadeTransition(
            opacity: animation.drive(
              Tween<double>(begin: 0.85, end: 1),
            ),
            child: SlideTransition(
              position: animation.drive(
                Tween<Offset>(
                  begin: const Offset(0, 0.008),
                  end: Offset.zero,
                ),
              ),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: PageStorageKey<Object>(pageIdentity),
          child: _buildBody(query),
        ),
      ),
    );
  }

  Widget _buildBody(String query) {
    if (query.isNotEmpty) {
      final results = _repo.search(query);
      return _SearchResultsList(
        results: results,
        query: query,
        onTap: (entry) => _openEntry(entry, results),
      );
    }
    if (_browseCategory == null) {
      return _HomeGrid(
        onSelectOhsAct: () => setState(() {
          _browseCategory = 'Act';
          _browseCollection = null;
        }),
        onSelectAct: (category, collection) => setState(() {
          _browseCategory = category;
          _browseCollection = collection;
        }),
      );
    }
    if (_browseCollection == null) {
      if (_browseCategory == 'Act') {
        return _OhsActMenu(
          onSelectTheAct: () => setState(() {
            _browseCollection = 'Occupational Health and Safety Act 85 of 1993';
          }),
          onSelectCategory: (cat) => setState(() => _browseCategory = cat),
        );
      }
      return _CollectionGrid(
        category: _browseCategory!,
        onSelect: (coll) => setState(() => _browseCollection = coll),
      );
    }
    final items = _repo.entriesInCollection(_browseCollection!);
    return _SectionList(items: items, onTap: (e) => _openEntry(e, items));
  }
}

class _Masthead extends StatelessWidget {
  final bool showBreadcrumb;
  const _Masthead({required this.showBreadcrumb});

  @override
  Widget build(BuildContext context) {
    final total = EntriesRepository.instance.all.length;

    return PremiumHeaderSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'REPUBLIC OF SOUTH AFRICA',
                    style: AppText.label(
                      size: 10,
                      color: AppColors.amber,
                    ).copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (kEnableAdaptiveAppearance) ...[
                  ListenableBuilder(
                    listenable: AppearanceController.instance,
                    builder: (context, child) {
                      final appearance =
                          AppearanceController.instance;
                      final isDark =
                          appearance.mode == ThemeMode.dark;

                      return PremiumHeaderButton(
                        icon: isDark
                            ? AppIcons.darkModeOutlined
                            : AppIcons.lightModeOutlined,
                        tooltip: isDark
                            ? 'Switch to Light mode'
                            : 'Switch to Dark mode',
                        onPressed: () async {
                          if (!appearance.isLoaded ||
                              appearance.isSaving) {
                            return;
                          }

                          final saved = await appearance.setMode(
                            isDark
                                ? ThemeMode.light
                                : ThemeMode.dark,
                          );

                          if (!context.mounted) return;

                          if (!saved) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not save appearance. '
                                  'Please try again.',
                                ),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                PremiumHeaderButton(
                  icon: AppIcons.notificationsActiveOutlined,
                  tooltip: 'Notifications',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const NotificationsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                style: AppText.headline(size: 26).copyWith(
                  color: AppColors.paperRaised,
                ),
                children: const [
                  TextSpan(text: 'OHS Act '),
                  TextSpan(
                    text: '&',
                    style: TextStyle(
                      color: PremiumHeaderSurface.gold,
                    ),
                  ),
                  TextSpan(text: ' Regulations'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$total sections & regulations',
              style: AppText.label(
                size: 12,
                color: PremiumHeaderSurface.muted,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Search or browse below',
              style: AppText.label(
                size: 11,
                color: PremiumHeaderSurface.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autoFocus;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.autoFocus,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppPalette.of(context).background,
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.of(context).surface,
          border: Border.all(color: AppPalette.of(context).text, width: 1.5),
          borderRadius: BorderRadius.circular(2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(AppIcons.search, size: 18, color: AppPalette.of(context).secondaryText),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: autoFocus,
                onChanged: onChanged,
                style: AppText.label(size: 15, color: AppPalette.of(context).text),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  hintText: 'Search a topic, or jump with a code like "CR 8"',
                  hintStyle: AppText.label(
                      size: 13, color: AppPalette.of(context).secondaryText.withValues(alpha: 0.7)),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                if (controller.text.isEmpty) return const SizedBox.shrink();
                return TextButton(
                  onPressed: onClear,
                  child: Text('CLEAR', style: AppText.label(size: 11, color: AppPalette.of(context).secondaryText)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeGrid extends StatelessWidget {
  final VoidCallback onSelectOhsAct;
  final void Function(String category, String collection) onSelectAct;
  const _HomeGrid({required this.onSelectOhsAct, required this.onSelectAct});

  // The full set of Acts this app covers. Each one not yet built shows as
  // a disabled "Coming soon" card rather than being hidden, so the scope
  // of the app is always visible up front. Subtitles show a live count,
  // not "so far" language - completeness is tracked as ongoing content
  // work, not surfaced as a caveat to the person browsing.
  static const List<(String label, String? collection)> _otherActs = [
    ('Mine Health and Safety Act', 'Mine Health and Safety Act 29 of 1996'),
    (
      'Compensation for Occupational Injuries and Diseases Act',
      'Compensation for Occupational Injuries and Diseases Act 130 of 1993'
    ),
    (
      'National Environmental Management Act',
      'National Environmental Management Act 107 of 1998'
    ),
    (
      'Basic Conditions of Employment Act',
      'Basic Conditions of Employment Act 75 of 1997'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final repo = EntriesRepository.instance;
    final ohsActCount = repo.all
        .where((e) =>
            e.collection == 'Occupational Health and Safety Act 85 of 1993')
        .length;
    final regCategories = repo
        .categoriesPresent()
        .where((c) => c != 'Act' && c != 'OtherActs')
        .toList();
    final regCount =
        regCategories.fold<int>(0, (sum, c) => sum + repo.countInCategory(c));
    // Every Act in the data that is not in the fixed list above (for example
    // POPIA, the CPA and the Constitution) is shown automatically.
    final List<(String, String?)> acts = [
      ..._otherActs,
      for (final c in repo.collectionsInCategory('OtherActs'))
        if (!_otherActs.any((a) => a.$2 == c)) (c, c),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
          child: Text('ACTS',
              style: AppText.label(size: 11, color: AppPalette.of(context).accent)),
        ),
        _BrowseCard(
          title: 'Occupational Health and Safety Act',
          subtitle: '$ohsActCount sections, plus $regCount regulations',
          onTap: onSelectOhsAct,
        ),
        ...acts.map((act) {
          final (label, collection) = act;
          final count =
              repo.all.where((e) => e.collection == collection).length;
          final available = count > 0;
          return Opacity(
            opacity: available ? 1 : 0.5,
            child: _BrowseCard(
              title: label,
              subtitle: available ? '$count sections' : 'Coming soon',
              onTap: available
                  ? () => onSelectAct('OtherActs', collection!)
                  : null,
            ),
          );
        }),
      ],
    );
  }
}

/// Shown after tapping the OHS Act card: lets the user go straight into
/// the Act itself, or browse its regulations by category (General,
/// Health, Mechanical, Electrical).
class _OhsActMenu extends StatelessWidget {
  final VoidCallback onSelectTheAct;
  final ValueChanged<String> onSelectCategory;
  const _OhsActMenu(
      {required this.onSelectTheAct, required this.onSelectCategory});

  @override
  Widget build(BuildContext context) {
    final repo = EntriesRepository.instance;
    final ohsActCount = repo.all
        .where((e) =>
            e.collection == 'Occupational Health and Safety Act 85 of 1993')
        .length;
    final regCategories = repo
        .categoriesPresent()
        .where((c) => c != 'Act' && c != 'OtherActs')
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _BrowseCard(
          title: 'The Act',
          subtitle: '$ohsActCount sections',
          onTap: onSelectTheAct,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 20, 6, 4),
          child: Text('REGULATIONS',
              style: AppText.label(size: 11, color: AppPalette.of(context).accent)),
        ),
        ...regCategories.map((cat) {
          final count = repo.countInCategory(cat);
          final setCount = repo.collectionsInCategory(cat).length;
          return _BrowseCard(
            title: kCategoryLabel[cat] ?? cat,
            subtitle:
                '$setCount regulation set${setCount == 1 ? '' : 's'} \u00b7 $count regulations',
            onTap: () => onSelectCategory(cat),
          );
        }),
      ],
    );
  }
}

class _CollectionGrid extends StatelessWidget {
  final String category;
  final ValueChanged<String> onSelect;
  const _CollectionGrid({required this.category, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final repo = EntriesRepository.instance;
    final collections = repo.collectionsInCategory(category);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: collections.length,
      itemBuilder: (context, i) {
        final coll = collections[i];
        final count = repo.all.where((e) => e.collection == coll).length;
        final unit = category == 'Act' ? 'sections' : 'regulations';
        return _BrowseCard(
          title: coll,
          subtitle: '$count $unit',
          onTap: () => onSelect(coll),
        );
      },
    );
  }
}

class _BrowseCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _BrowseCard(
      {required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final radius = BorderRadius.circular(2);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border.all(color: palette.border),
            borderRadius: radius,
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            splashColor: palette.accent.withValues(alpha: 0.18),
            highlightColor: palette.accent.withValues(alpha: 0.10),
            focusColor: palette.accent.withValues(alpha: 0.14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          AppText.headline(size: 16, weight: FontWeight.w600).copyWith(color: AppPalette.of(context).text)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: AppText.label(size: 11, color: AppPalette.of(context).secondaryText)),
                ],
              ),
            ),
            Icon(AppIcons.arrowForward, size: 18, color: AppPalette.of(context).secondaryText),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionList extends StatelessWidget {
  final List<Entry> items;
  final ValueChanged<Entry> onTap;
  const _SectionList({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _EmptyState();
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: AppPalette.of(context).border),
      itemBuilder: (context, i) =>
          _SectionRow(entry: items[i], onTap: () => onTap(items[i])),
    );
  }
}

class _SearchResultsList extends StatelessWidget {
  final List<Entry> results;
  final String query;
  final ValueChanged<Entry> onTap;
  const _SearchResultsList(
      {required this.results, required this.query, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const _EmptyState();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final entry = results[i];
        final showCategoryHeader =
            i == 0 || results[i - 1].category != entry.category;
        final showCollectionHeader =
            i == 0 || results[i - 1].collection != entry.collection;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showCategoryHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 4),
                child: Text(kCategoryLabel[entry.category] ?? entry.category,
                    style: AppText.label(size: 11, color: AppPalette.of(context).accent)),
              ),
            if (showCollectionHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 2, 22, 6),
                child: Text(entry.collection,
                    style: AppText.headline(size: 14, weight: FontWeight.w600).copyWith(color: AppPalette.of(context).text)),
              ),
            _SectionRow(entry: entry, onTap: () => onTap(entry)),
          ],
        );
      },
    );
  }
}

class _SectionRow extends StatelessWidget {
  final Entry entry;
  final VoidCallback onTap;
  const _SectionRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final snippet = entry.body.replaceAll('\n', ' ').trim();
    final trimmed =
        snippet.length > 140 ? '${snippet.substring(0, 140)}…' : snippet;
    return InkWell(
      onTap: onTap,
      splashColor: AppPalette.of(context).accent.withValues(alpha: 0.18),
      highlightColor: AppPalette.of(context).accent.withValues(alpha: 0.10),
      focusColor: AppPalette.of(context).accent.withValues(alpha: 0.14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              padding: const EdgeInsets.symmetric(vertical: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: AppPalette.of(context).text, width: 1),
              ),
              child: Text(entry.num,
                  style: AppText.label(size: 11, color: AppPalette.of(context).text)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title,
                      style: AppText.headline(
                          size: 15.5, weight: FontWeight.w600).copyWith(color: AppPalette.of(context).text)),
                  const SizedBox(height: 3),
                  Text(trimmed,
                      style: AppText.body(size: 13, color: AppPalette.of(context).secondaryText),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'No sections match that search.\nTry a different word, or a section number.',
          textAlign: TextAlign.center,
          style: AppText.label(size: 13, color: AppPalette.of(context).secondaryText),
        ),
      ),
    );
  }
}
