import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'data/ad_service.dart';
import 'data/bookmarks_repository.dart';
import 'data/certificates_repository.dart';
import 'data/connectivity_service.dart';
import 'data/entries_repository.dart';
import 'data/iso_repository.dart';
import 'data/notification_service.dart';
import 'data/saved_documents_repository.dart';
import 'data/subscription_repository.dart';
import 'data/toolbox_talks_repository.dart';
import 'data/translations_repository.dart';
import 'theme/app_theme.dart';
import 'screens/explore_screen.dart';
import 'screens/more_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint(
        'Firebase not configured yet - Safety Chat Bot will be unavailable: $e');
  }
  await AdService.instance.init();
  await SubscriptionRepository.instance.init();
  try {
    await NotificationService.instance.init();
  } catch (e) {
    debugPrint('Local notifications unavailable on this device: $e');
  }
  runApp(const OhsApp());
}

class OhsApp extends StatelessWidget {
  const OhsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OHS Act & Regulations',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const _ConnectivityGate(child: RootShell()),
    );
  }
}

/// Wraps the whole app: this app requires an internet connection to work
/// at all times, not just for specific features. Blocks with a full-screen
/// message the moment connectivity drops (including before the app has
/// even finished loading), and unblocks automatically the instant it's
/// back, without needing the user to do anything.
class _ConnectivityGate extends StatefulWidget {
  final Widget child;
  const _ConnectivityGate({required this.child});

  @override
  State<_ConnectivityGate> createState() => _ConnectivityGateState();
}

class _ConnectivityGateState extends State<_ConnectivityGate> {
  bool? _online;

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.isOnline().then((online) {
      if (mounted) setState(() => _online = online);
    });
    ConnectivityService.instance.onStatusChanged.listen((online) {
      if (mounted) setState(() => _online = online);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_online == false) {
      return Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off, size: 48, color: AppColors.steel),
                const SizedBox(height: 20),
                Text('No internet connection',
                    style: AppText.headline(size: 20),
                    textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(
                  'This app requires an internet connection to work. Please check your connection and try again.',
                  style: AppText.body(size: 14, color: AppColors.steel),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    // _online == null means the very first check hasn't returned yet -
    // show a brief loading state rather than flashing the offline screen.
    if (_online == null) {
      return const Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(
            child: CircularProgressIndicator(color: AppColors.amberDeep)),
      );
    }
    return widget.child;
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tabIndex = 0;
  bool _loading = true;
  String? _loadError;

  final GlobalKey<ExploreScreenState> _homeKey =
      GlobalKey<ExploreScreenState>();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      await EntriesRepository.instance.load();
      await BookmarksRepository.instance.load();
      await IsoRepository.instance.load();
      await TranslationsRepository.instance.load();
      await ToolboxTalksRepository.instance.load();
      await CertificatesRepository.instance.load();
      await SavedDocumentsRepository.instance.load();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _loadError = 'Could not load regulation data: $e';
      });
    }
  }

  void _onTabTapped(int index) {
    if (index == 0 && _tabIndex == 0) {
      _homeKey.currentState?.resetToTop();
    }
    setState(() => _tabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(
            child: CircularProgressIndicator(color: AppColors.amberDeep)),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_loadError!,
                style: AppText.body(), textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final tabs = [
      ExploreScreen(key: _homeKey, autoFocusSearch: false),
      const ExploreScreen(autoFocusSearch: true),
      const MoreScreen(),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_tabIndex == 0) {
          final handledInHome = _homeKey.currentState?.handleBack() ?? false;
          if (handledInHome) return;
          SystemNavigator.pop();
        } else {
          setState(() => _tabIndex = 0);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.paper,
        body: IndexedStack(index: _tabIndex, children: tabs),
        bottomNavigationBar:
            _BottomNav(currentIndex: _tabIndex, onTap: _onTabTapped),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.paperRaised,
          border: Border(top: BorderSide(color: AppColors.ink, width: 1.5)),
        ),
        child: Row(
          children: [
            _AnimatedNavTab(
              icon: Icons.home_outlined,
              label: 'Home',
              index: 0,
              active: currentIndex == 0,
              onTap: onTap,
            ),
            _AnimatedNavTab(
              icon: Icons.search,
              label: 'Search',
              index: 1,
              active: currentIndex == 1,
              onTap: onTap,
            ),
            _AnimatedNavTab(
              icon: Icons.more_horiz,
              label: 'More',
              index: 2,
              active: currentIndex == 2,
              onTap: onTap,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single bottom-nav tab that plays a quick scale-bounce on its icon
/// whenever it's tapped, so switching tabs feels more responsive than a
/// plain instant swap.
class _AnimatedNavTab extends StatefulWidget {
  final IconData icon;
  final String label;
  final int index;
  final bool active;
  final ValueChanged<int> onTap;

  const _AnimatedNavTab({
    required this.icon,
    required this.label,
    required this.index,
    required this.active,
    required this.onTap,
  });

  @override
  State<_AnimatedNavTab> createState() => _AnimatedNavTabState();
}

class _AnimatedNavTabState extends State<_AnimatedNavTab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.3)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 45),
      TweenSequenceItem(
          tween: Tween(begin: 1.3, end: 1.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 55),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onTap(widget.index);
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: _handleTap,
        child: Container(
          padding: const EdgeInsets.only(top: 9, bottom: 8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: widget.active ? AppColors.amberDeep : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _scale,
                child: Icon(
                  widget.icon,
                  size: 20,
                  color: widget.active
                      ? AppColors.ink
                      : AppColors.steel.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.label,
                style: AppText.label(
                    size: 10.5,
                    color: widget.active ? AppColors.ink : AppColors.steel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
