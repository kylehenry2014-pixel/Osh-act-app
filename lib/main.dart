import 'dart:async';

import 'data/app_rating_service.dart';
import 'data/app_update_service.dart';
import 'widgets/app_rating_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'data/ad_service.dart';
import 'data/bookmarks_repository.dart';
import 'data/certificates_repository.dart';
import 'data/daily_citation_service.dart';
import 'data/entries_repository.dart';
import 'data/iso_repository.dart';
import 'data/notification_service.dart';
import 'data/notification_schedule_repository.dart';
import 'data/saved_documents_repository.dart';
import 'data/subscription_repository.dart';
import 'data/toolbox_talks_repository.dart';
import 'data/translations_repository.dart';
import 'theme/app_icons.dart';
import 'theme/app_theme.dart';
import 'theme/appearance_controller.dart';
import 'screens/explore_screen.dart';
import 'screens/more_screen.dart';
import 'screens/bookmarks_screen.dart';
import 'screens/toolbox_talks_screen.dart';
import 'screens/chat_screen.dart';
import 'data/connectivity_service.dart';
import 'screens/notifications_screen.dart';
import 'widgets/ohs_splash.dart';

Future<void> _initialiseOptionalService(
  String name,
  Future<void> Function() initialise,
) async {
  try {
    await initialise().timeout(
      const Duration(seconds: 12),
    );
  } catch (error) {
    debugPrint('$name initialisation unavailable: $error');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initialiseOptionalService(
    'Firebase',
    () async {
      await Firebase.initializeApp();
    },
  );

  await Future.wait<void>([
    _initialiseOptionalService(
      'Appearance',
      AppearanceController.instance.load,
    ),
    _initialiseOptionalService(
      'Advertisements',
      AdService.instance.init,
    ),
    _initialiseOptionalService(
      'Subscriptions',
      SubscriptionRepository.instance.init,
    ),
    _initialiseOptionalService(
      'Notifications',
      NotificationService.instance.init,
    ),
  ]);

  runApp(const OhsApp());
}

class OhsApp extends StatelessWidget {
  const OhsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceController.instance;

    return ListenableBuilder(
      listenable: appearance,
      builder: (context, child) {
        return MaterialApp(
          title: 'OHS Act & Regulations',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          darkTheme: buildAppTheme(
            brightness: Brightness.dark,
          ),
          themeMode: kEnableAdaptiveAppearance
              ? appearance.mode
              : ThemeMode.light,
          themeAnimationDuration:
              MediaQueryData.fromView(View.of(context))
                      .disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
          themeAnimationCurve: Curves.easeInOut,
          builder: (context, child) {
            final dark =
                Theme.of(context).brightness == Brightness.dark;

            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness:
                    dark ? Brightness.light : Brightness.dark,
                statusBarBrightness:
                    dark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor:
                    const Color(0xFF10120F),
                systemNavigationBarIconBrightness:
                    Brightness.light,
                systemNavigationBarDividerColor:
                    Colors.transparent,
                systemNavigationBarContrastEnforced: false,
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: child,
        );
      },
      child: const _SplashGate(child: RootShell()),
    );
  }
}

/// Shows the animated OHS splash on top of the app, then removes it.
final ValueNotifier<bool> _ratingSplashReady =
    ValueNotifier<bool>(false);

class _SplashGate extends StatefulWidget {
  final Widget child;
  const _SplashGate({required this.child});

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        widget.child,
        if (_showSplash)
          Positioned.fill(
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              ),
              child: OhsSplash(
                onFinished: () {
                  if (mounted) {
                    setState(() => _showSplash = false);
                    _ratingSplashReady.value = true;
                  }
                },
              ),
            ),
          ),
      ],
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell>
    with WidgetsBindingObserver {
  int _tabIndex = 0;
  bool _openingAssistantTab = false;
  bool _assistantTabCreated = false;
  bool _loading = true;
  String? _loadError;

  final GlobalKey<ExploreScreenState> _homeKey =
      GlobalKey<ExploreScreenState>();

  final _ratingService = AppRatingService.instance;

  Timer? _ratingTimer;
  Timer? _notificationReconcileTimer;
  Timer? _notificationNavigationTimer;
  bool _notificationNavigationBusy = false;
  bool _notificationReconcileBusy = false;
  bool _ratingCheckBusy = false;
  int _ratingSaveTicks = 0;

  bool get _ratingForeground =>
      WidgetsBinding.instance.lifecycleState ==
      AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _loadData();
    unawaited(_initialiseRating());
    unawaited(_checkInstalledUpdate());

    _startNotificationNavigation();

    _startNotificationReconciliation();
  }

  void _startNotificationNavigation() {
    _notificationNavigationTimer?.cancel();
    _notificationNavigationTimer = null;

    if (!mounted || !_ratingForeground) return;

    _notificationNavigationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_dispatchNotificationTap()),
    );
  }

  Future<void> _dispatchNotificationTap() async {
    if (!mounted ||
        _openingAssistantTab ||
        _notificationNavigationBusy ||
        !_ratingSplashReady.value ||
        !_ratingForeground ||
        _loading ||
        _loadError != null ||
        _ratingCheckBusy ||
        AdService.instance.isBusy) {
      return;
    }

    final service = NotificationService.instance;
    final payload = service.pendingNotificationPayload;

    if (payload == null) return;

    // Do not interrupt an existing route or modal.
    final currentRoute = ModalRoute.of(context);

    if (currentRoute?.isCurrent != true ||
        !TickerMode.of(context)) {
      return;
    }

    final animation = currentRoute?.animation;
    final secondary = currentRoute?.secondaryAnimation;

    if ((animation != null &&
            animation.status != AnimationStatus.completed) ||
        (secondary != null &&
            secondary.status != AnimationStatus.dismissed)) {
      return;
    }

    _notificationNavigationBusy = true;

    try {
      final route = MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(
          initialPayload: payload,
        ),
      );

      final navigation =
          Navigator.of(context).push<void>(route);

      service.clearPendingNotification(payload);

      await navigation;
    } catch (error) {
      debugPrint(
        'Notification navigation unavailable: '
        '${error.runtimeType}',
      );
    } finally {
      _notificationNavigationBusy = false;
    }
  }

  void _startNotificationReconciliation() {
    _notificationReconcileTimer?.cancel();

    if (!mounted ||
        WidgetsBinding.instance.lifecycleState !=
            AppLifecycleState.resumed) {
      return;
    }

    unawaited(_reconcileNotifications());

    _notificationReconcileTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_reconcileNotifications()),
    );
  }

  Future<void> _reconcileNotifications() async {
    if (!mounted ||
        _notificationReconcileBusy ||
        WidgetsBinding.instance.lifecycleState !=
            AppLifecycleState.resumed) {
      return;
    }

    _notificationReconcileBusy = true;

    try {
      await NotificationScheduleRepository.instance
          .reconcileDue();
    } catch (error) {
      debugPrint(
        'Notification reconciliation unavailable: $error',
      );
    } finally {
      _notificationReconcileBusy = false;
    }
  }

  Future<void> _checkInstalledUpdate() async {
    try {
      await AppUpdateService.instance.checkInstalledVersion();
    } catch (_) {
      debugPrint('Application update check unavailable.');
    }
  }

  Future<void> _initialiseRating() async {
    try {
      await _ratingService.init();

      if (!mounted) return;

      _ratingTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_checkRatingPrompt()),
      );
    } catch (_) {
      debugPrint('App rating service unavailable.');
    }
  }

  Future<void> _pauseRatingUsage() async {
    try {
      await _ratingService.pauseUsage();
    } catch (_) {
      debugPrint('App rating usage could not be saved.');
    }
  }

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_pauseRatingUsage());

      _notificationReconcileTimer?.cancel();
      _notificationReconcileTimer = null;

      _notificationNavigationTimer?.cancel();
      _notificationNavigationTimer = null;
    } else {
      _startNotificationReconciliation();
      _startNotificationNavigation();
    }
  }

  Future<void> _checkRatingPrompt() async {
    if (!mounted || _ratingCheckBusy) return;

    _ratingCheckBusy = true;

    try {
      if (!_ratingSplashReady.value ||
          !_ratingForeground ||
          _loading ||
          _loadError != null ||
          AdService.instance.isBusy) {
        await _pauseRatingUsage();
        return;
      }

      if (_ratingService.automaticPromptDisabled) {
        _ratingTimer?.cancel();
        await _pauseRatingUsage();
        return;
      }

      _ratingService.resumeUsage();

      _ratingSaveTicks++;

      if (_ratingSaveTicks >= 15) {
        _ratingSaveTicks = 0;
        await _ratingService.saveUsage();
      }

      if (!mounted ||
          !_ratingSplashReady.value ||
          !_ratingForeground ||
          _loading ||
          _loadError != null ||
          !_ratingService.shouldPrompt ||
          _openingAssistantTab ||
        _notificationNavigationBusy ||
          NotificationService.instance
                  .pendingNotificationPayload != null ||
          AdService.instance.isBusy ||
          _tabIndex != 0 ||
          ModalRoute.of(context)?.isCurrent != true ||
          _homeKey.currentState?.canShowRatingPrompt != true) {
        return;
      }

      if (!_ratingService.beginPrompt()) return;

      try {
        final action = await AppRatingDialog.show(context);

        if (action == null) {
          await _ratingService.remindLater();
        }
      } finally {
        _ratingService.endPrompt();
      }
    } catch (_) {
      debugPrint('App rating prompt unavailable.');

      // Avoid repeatedly opening a prompt when
      // storage or presentation fails.
      _ratingTimer?.cancel();
      await _pauseRatingUsage();
    } finally {
      _ratingCheckBusy = false;
    }
  }

  @override
  void dispose() {
    _ratingTimer?.cancel();
    _notificationReconcileTimer?.cancel();
    _notificationNavigationTimer?.cancel();

    WidgetsBinding.instance.removeObserver(this);

    unawaited(_pauseRatingUsage());

    super.dispose();
  }

  bool _loadInProgress = false;

  Future<bool> _loadOptionalRepository(
    String name,
    Future<void> Function() load,
  ) async {
    try {
      await load();
      return true;
    } catch (error) {
      debugPrint('$name loading failed: $error');
      return false;
    }
  }

  Future<void> _restoreCertificateReminders() async {
    try {
      await NotificationService.instance.reconcileCertificates(
        CertificatesRepository.instance.all,
      );
    } catch (error) {
      debugPrint(
        'Certificate reminder reconciliation failed: $error',
      );
    }
  }

  Future<void> _refreshDailyCitations() async {
    try {
      await DailyCitationService.instance.refresh();
    } catch (error) {
      debugPrint('Daily citation refresh failed: $error');
    }
  }

  Future<void> _loadData() async {
    if (!mounted || _loadInProgress) return;

    _loadInProgress = true;

    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      // Legislation is the essential application catalogue.
      await EntriesRepository.instance.load();

      final results = await Future.wait<bool>([
        _loadOptionalRepository(
          'Bookmarks',
          BookmarksRepository.instance.load,
        ),
        _loadOptionalRepository(
          'ISO standards',
          IsoRepository.instance.load,
        ),
        _loadOptionalRepository(
          'Translations',
          TranslationsRepository.instance.load,
        ),
        _loadOptionalRepository(
          'Toolbox Talks',
          ToolboxTalksRepository.instance.load,
        ),
        _loadOptionalRepository(
          'Certificates',
          CertificatesRepository.instance.load,
        ),
        _loadOptionalRepository(
          'Saved documents',
          SavedDocumentsRepository.instance.load,
        ),
      ]);

      // Never reconcile reminders against an empty or
      // damaged certificate repository.
      if (results[4]) {
        unawaited(_restoreCertificateReminders());
      }

      unawaited(_refreshDailyCitations());

      if (!mounted) return;

      setState(() => _loading = false);

      if (results.contains(false) ||
          BookmarksRepository.instance.hasStorageDamage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Some libraries or saved records could not '
                'be loaded. Your stored data has not been reset.',
              ),
            ),
          );
        });
      }
    } catch (error) {
      debugPrint('Essential catalogue loading failed: $error');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _loadError =
            'The legislation library could not be loaded. '
            'Please try again.';
      });
    } finally {
      _loadInProgress = false;
    }
  }

  static const _chatFeatureKey = 'chat';

  bool _canContinueFeatureOpen() {
    return mounted &&
        _ratingForeground &&
        ModalRoute.of(context)?.isCurrent == true &&
        TickerMode.of(context);
  }

  void _activateAssistantTab() {
    if (!_canContinueFeatureOpen()) return;

    setState(() {
      _assistantTabCreated = true;
      _tabIndex = 3;
    });
  }

  Future<bool?> _confirmWatchAds(int adCount, String actionLabel) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Watch an ad to continue'),
        content: Text(
          adCount == 1
              ? 'Watch a short ad to $actionLabel.'
              : 'Watch $adCount ads back-to-back to $actionLabel.',
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
  }

  Future<bool> _checkOnlineOrWarn(String actionLabel) async {
    final online = await ConnectivityService.instance.isOnline();
    if (!online && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('You need an internet connection to $actionLabel.')),
      );
    }
    return online;
  }

  Future<void> _openChat() async {
    if (_openingAssistantTab ||
        !_canContinueFeatureOpen()) {
      return;
    }

    _openingAssistantTab = true;

    try {
      await _openChatInternal();
    } catch (error) {
      debugPrint(
        'AI Assistant opening failed: ${error.runtimeType}',
      );

      if (mounted && _canContinueFeatureOpen()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to open AI Assistant. Please try again.',
            ),
          ),
        );
      }
    } finally {
      _openingAssistantTab = false;
    }
  }

  Future<void> _openChatInternal() async {
    if (!await _checkOnlineOrWarn('use the Safety Chat Bot')) return;
    if (!mounted || !_canContinueFeatureOpen()) return;
    if (SubscriptionRepository.instance.isPro) {
      _activateAssistantTab();
      return;
    }
    final adCount =
        await AdService.instance.nextRequiredAdCount(_chatFeatureKey);
    if (!mounted || !_canContinueFeatureOpen()) return;
    final confirmed = await _confirmWatchAds(adCount, 'ask a question');
    if (!mounted || confirmed != true || !_canContinueFeatureOpen()) return;

    final earned = await AdService.instance.watchAds(adCount);
    if (!mounted || !_canContinueFeatureOpen()) return;

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
    await AdService.instance.recordUnlockedRequest(_chatFeatureKey);
    if (!mounted || !_canContinueFeatureOpen()) return;

    _activateAssistantTab();
  }

  void _onTabTapped(int index) {
    if (_openingAssistantTab || AdService.instance.isBusy) {
      return;
    }

    if (index == 3 && index != _tabIndex) {
      HapticFeedback.selectionClick();
      FocusManager.instance.primaryFocus?.unfocus();
      unawaited(_openChat());
      return;
    }
    if (index == _tabIndex) {
      if (index == 0) {
        _homeKey.currentState?.resetToTop();
      }
      return;
    }

    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _tabIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppPalette.of(context).background,
        body: Center(
            child: CircularProgressIndicator(color: AppPalette.of(context).accent)),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: AppPalette.of(context).background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  AppIcons.warningAmberRounded,
                  size: 48,
                  color: AppPalette.of(context).accent,
                ),
                const SizedBox(height: 16),
                Text(
                  _loadError!,
                  style: AppText.body(color: AppPalette.of(context).text),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _loadInProgress ? null : _loadData,
                  icon: const Icon(AppIcons.refreshRounded),
                  label: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final tabs = [
      ExploreScreen(key: _homeKey, autoFocusSearch: false),
      const BookmarksScreen(embedded: true),
      const ToolboxTalksScreen(embedded: true),
      if (_assistantTabCreated)
        const ChatScreen(embedded: true)
      else
        const SizedBox.shrink(),
      const MoreScreen(),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _openingAssistantTab) return;
        if (_tabIndex == 0) {
          final handledInHome = _homeKey.currentState?.handleBack() ?? false;
          if (handledInHome) return;
          SystemNavigator.pop();
        } else {
          setState(() => _tabIndex = 0);
        }
      },
      child: Scaffold(
        backgroundColor: AppPalette.of(context).background,
        body: _PremiumTabStack(index: _tabIndex, children: tabs),
        bottomNavigationBar:
            _BottomNav(currentIndex: _tabIndex, onTap: _onTabTapped),
      ),
    );
  }
}

// =====================================================
// PREMIUM INDUSTRIAL NAVIGATION
// =====================================================

class _NavStyle {
  static const ink = Color(0xFF171916);
  static const gold = Color(0xFFDA9B2A);
  static const lightGold = Color(0xFFFFE4A0);
  static const inactive = Color(0xFFC5C6BB);



  static const glossyCharcoal = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF484B43),
      Color(0xFF292C26),
      Color(0xFF20231E),
      Color(0xFF10120F),
    ],
    stops: [0, 0.35, 0.65, 1],
  );
}

// =====================================================
// STATE-PRESERVING PAGE TRANSITIONS
// =====================================================

class _PremiumTabStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const _PremiumTabStack({
    required this.index,
    required this.children,
  });

  @override
  State<_PremiumTabStack> createState() =>
      _PremiumTabStackState();
}

class _PremiumTabStackState extends State<_PremiumTabStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );

    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _opacity = Tween<double>(
      begin: 0.85,
      end: 1,
    ).animate(_curve);

    _offset = Tween<Offset>(
      begin: const Offset(0, 0.006),
      end: Offset.zero,
    ).animate(_curve);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _reducedMotion =
        MediaQuery.of(context).disableAnimations;

    if (_reducedMotion) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(
    covariant _PremiumTabStack oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.index != widget.index) {
      if (_reducedMotion) {
        _controller.value = 1;
      } else {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _offset,
          child: IndexedStack(
            index: widget.index,
            children: [
              for (int i = 0;
                  i < widget.children.length;
                  i++)
                TickerMode(
                  enabled: i == widget.index,
                  child: widget.children[i],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================
// INTEGRATED GLOSSY NAVIGATION BAR
// =====================================================

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.of(context).disableAnimations;

    final duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Color(0xFF10120F),
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: _NavStyle.glossyCharcoal,
          border: Border(
            top: BorderSide(
              color: _NavStyle.gold,
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tabWidth = constraints.maxWidth / 5;

                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      left: currentIndex * tabWidth + 3,
                      top: 0,
                      bottom: 0,
                      width: tabWidth - 6,
                      child: const _GoldSelectionIndicator(),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _PremiumNavTab(
                            icon: AppIcons.homeOutlined,
                            label: 'Home',
                            active: currentIndex == 0,
                            onTap: () => onTap(0),
                          ),
                        ),
                        Expanded(
                          child: _PremiumNavTab(
                            icon: AppIcons.bookmarkBorderRounded,
                            label: 'Bookmarks',
                            active: currentIndex == 1,
                            onTap: () => onTap(1),
                          ),
                        ),
                        Expanded(
                          child: _PremiumNavTab(
                            icon: AppIcons.assignmentIndOutlined,
                            label: 'Toolbox Talks',
                            active: currentIndex == 2,
                            onTap: () => onTap(2),
                          ),
                        ),
                        Expanded(
                          child: _PremiumNavTab(
                            icon: AppIcons.chatBubbleOutline,
                            label: 'AI Assistant',
                            active: currentIndex == 3,
                            onTap: () => onTap(3),
                          ),
                        ),
                        Expanded(
                          child: _PremiumNavTab(
                            icon: AppIcons.gridViewRounded,
                            label: 'More',
                            active: currentIndex == 4,
                            onTap: () => onTap(4),
                          ),
                        ),
                      ],
                    ),
                    const Positioned(
                      left: 9,
                      bottom: 0,
                      child: IgnorePointer(
                        child: _NavTapeAccent(),
                      ),
                    ),
                    const Positioned(
                      right: 9,
                      bottom: 0,
                      child: IgnorePointer(
                        child: _NavTapeAccent(reverse: true),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================
// SLIDING GOLD SELECTION INDICATOR
// =====================================================

class _GoldSelectionIndicator extends StatelessWidget {
  const _GoldSelectionIndicator();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: _NavStyle.gold,
          width: 1.1,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x33DA9B2A),
            Color(0x16DA9B2A),
            Color(0x05DA9B2A),
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22DA9B2A),
            blurRadius: 7,
          ),
        ],
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 1),
          width: 30,
          height: 2,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: _NavStyle.lightGold,
            boxShadow: const [
              BoxShadow(
                color: Color(0x66DA9B2A),
                blurRadius: 5,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================
// PREMIUM NAVIGATION TAB
// =====================================================

class _PremiumNavTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PremiumNavTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.of(context).disableAnimations;

    final duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);

    final color = active
        ? _NavStyle.lightGold
        : _NavStyle.inactive;

    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(19),
          splashColor: const Color(0x22DA9B2A),
          highlightColor: const Color(0x11DA9B2A),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 4,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: active ? 1.04 : 1,
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: color),
                    duration: duration,
                    builder: (context, value, child) {
                      return Icon(
                        icon,
                        size: 25,
                        color: value ?? color,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 5),
                AnimatedDefaultTextStyle(
                  duration: duration,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: active
                        ? FontWeight.w700
                        : FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================
// SUBTLE INDUSTRIAL DANGER TAPE ACCENTS
// =====================================================

class _NavTapeAccent extends StatefulWidget {
  final bool reverse;

  const _NavTapeAccent({
    this.reverse = false,
  });

  @override
  State<_NavTapeAccent> createState() =>
      _NavTapeAccentState();
}

class _NavTapeAccentState extends State<_NavTapeAccent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final reducedMotion =
        MediaQuery.of(context).disableAnimations;
    final tickerEnabled = TickerMode.of(context);

    if (reducedMotion) {
      _controller.stop();
      _controller.value = 0;
    } else if (!tickerEnabled) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 30,
        height: 3,
        child: CustomPaint(
          painter: _NavTapePainter(
            animation: _controller,
            reverse: widget.reverse,
          ),
        ),
      ),
    );
  }
}

class _NavTapePainter extends CustomPainter {
  final Animation<double> animation;
  final bool reverse;

  _NavTapePainter({
    required this.animation,
    required this.reverse,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const period = 10.0;
    final shift = animation.value * period;

    canvas.save();
    canvas.clipRect(rect);

    if (reverse) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }

    canvas.drawRect(
      rect,
      Paint()..color = _NavStyle.ink,
    );

    final paint = Paint()
      ..color = _NavStyle.gold;

    for (
      double x = -18 + shift;
      x < size.width + 18;
      x += period
    ) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + 5, size.height)
        ..lineTo(x + 8, 0)
        ..lineTo(x + 3, 0)
        ..close();

      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(
    covariant _NavTapePainter oldDelegate,
  ) =>
      oldDelegate.reverse != reverse ||
      oldDelegate.animation != animation;
}
