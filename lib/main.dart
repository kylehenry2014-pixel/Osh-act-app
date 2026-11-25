import 'dart:async';

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
import 'data/saved_documents_repository.dart';
import 'data/subscription_repository.dart';
import 'data/toolbox_talks_repository.dart';
import 'data/translations_repository.dart';
import 'theme/app_theme.dart';
import 'screens/explore_screen.dart';
import 'screens/more_screen.dart';
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
    return MaterialApp(
      title: 'OHS Act & Regulations',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const _SplashGate(child: RootShell()),
    );
  }
}

/// Shows the animated OHS splash on top of the app, then removes it.
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
            child: OhsSplash(
              onFinished: () {
                if (mounted) {
                  setState(() => _showSplash = false);
                }
              },
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

  void _onTabTapped(int index) {
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 48,
                  color: AppColors.amberDeep,
                ),
                const SizedBox(height: 16),
                Text(
                  _loadError!,
                  style: AppText.body(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _loadInProgress ? null : _loadData,
                  icon: const Icon(Icons.refresh_rounded),
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

  static const metallicBorder = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF805014),
      Color(0xFFFFE4A0),
      Color(0xFF95621C),
      Color(0xFFDA9B2A),
      Color(0xFFFFD77A),
    ],
  );

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
      duration: const Duration(milliseconds: 280),
      value: 1,
    );

    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _opacity = Tween<double>(
      begin: 0.55,
      end: 1,
    ).animate(_curve);

    _offset = Tween<Offset>(
      begin: const Offset(0, 0.012),
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
// FLOATING GLOSSY NAVIGATION BAR
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
        : const Duration(milliseconds: 280);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 7, 12, 10),
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          gradient: _NavStyle.metallicBorder,
          borderRadius: BorderRadius.circular(27),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
            BoxShadow(
              color: Color(0x22DA9B2A),
              blurRadius: 7,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: _NavStyle.glossyCharcoal,
            borderRadius: BorderRadius.circular(25.5),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 7, 5, 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tabWidth =
                    constraints.maxWidth / 3;

                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      left: currentIndex * tabWidth + 2,
                      top: 0,
                      bottom: 0,
                      width: tabWidth - 4,
                      child: const _GoldSelectionIndicator(),
                    ),

                    Row(
                      children: [
                        Expanded(
                          child: _PremiumNavTab(
                            icon: Icons.home_outlined,
                            label: 'Home',
                            active: currentIndex == 0,
                            onTap: () => onTap(0),
                          ),
                        ),
                        Expanded(
                          child: _PremiumNavTab(
                            icon: Icons.search_rounded,
                            label: 'Search',
                            active: currentIndex == 1,
                            onTap: () => onTap(1),
                          ),
                        ),
                        Expanded(
                          child: _PremiumNavTab(
                            icon: Icons.grid_view_rounded,
                            label: 'More',
                            active: currentIndex == 2,
                            onTap: () => onTap(2),
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
        : const Duration(milliseconds: 220);

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
                  scale: active ? 1.08 : 1,
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
                    maxLines: 1,
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

class _NavTapeAccent extends StatelessWidget {
  final bool reverse;

  const _NavTapeAccent({
    this.reverse = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 3,
      child: CustomPaint(
        painter: _NavTapePainter(reverse),
      ),
    );
  }
}

class _NavTapePainter extends CustomPainter {
  final bool reverse;

  const _NavTapePainter(this.reverse);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

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
      double x = -8;
      x < size.width + 8;
      x += 10
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
  ) => oldDelegate.reverse != reverse;
}
