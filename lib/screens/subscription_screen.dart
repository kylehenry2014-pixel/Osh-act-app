import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../data/subscription_repository.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {


  List<ProductDetails> _products = [];
  bool _loading = true;
  bool _purchasing = false;
  bool _restoreRequestInFlight = false;
  String? _error;
  String? _purchaseMessage;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  void _retry() {
    setState(() {
      _loading = true;
      _products = [];
      _error = null;
      _purchaseMessage = null;
    });
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await SubscriptionRepository.instance
          .queryProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _error = null;
        _loading = false;
        if (products.isEmpty) {
          _error =
              'Subscriptions aren\'t available yet. Please try again later.';
        }
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'The Play Store took too long to respond. Check your connection and try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load subscription options. Please try again later.';
      });
    }
  }

  Future<void> _buy(ProductDetails product) async {
    if (_purchasing || _restoreRequestInFlight) return;
    if (SubscriptionRepository.instance.isPro) return;

    setState(() {
      _purchasing = true;
      _error = null;
      _purchaseMessage = 'Opening secure Google Play checkout...';
    });

    try {
      await SubscriptionRepository.instance.buy(product);

      if (!mounted) return;

      setState(() {
        _purchaseMessage =
            'Follow the Google Play instructions. Premium benefits '
            'will activate after successful purchase verification.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _purchaseMessage = null;
          _error =
              'Something went wrong starting the purchase. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _restore() async {
    if (_purchasing || _restoreRequestInFlight) return;

    setState(() {
      _purchasing = true;
      _restoreRequestInFlight = true;
      _error = null;
      _purchaseMessage = 'Checking Google Play for existing purchases...';
    });

    try {
      final request = SubscriptionRepository.instance
          .restorePurchases()
          .whenComplete(() {
        if (mounted) {
          setState(() => _restoreRequestInFlight = false);
        }
      });

      await request.timeout(const Duration(seconds: 30));

      if (!mounted) return;

      setState(() {
        _purchaseMessage =
            'Restore request completed. Eligible purchases will '
            'activate after verification.';
      });
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _purchaseMessage =
              'Google Play is taking longer than expected. '
              'Your restore request may still be processing.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _purchaseMessage = null;
          _error = 'Could not restore purchases. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: AppBar(
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        backgroundColor: _PremiumColors.ink,
        foregroundColor: _PremiumColors.cream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'OHS ACT',
          style: AppText.headline(
            size: 21,
            weight: FontWeight.w800,
          ).copyWith(
            color: _PremiumColors.gold,
            letterSpacing: 2,
          ),
        ),
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: SubscriptionRepository.instance.isProNotifier,
        builder: (context, isPro, _) {
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PremiumHeader(isPro: isPro),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _BenefitCard(
                          icon: AppIcons.verifiedUserOutlined,
                          title: 'Ad-free experience',
                          subtitle: 'Work without advertising interruptions.',
                        ),
                        const SizedBox(height: 10),
                        const _BenefitCard(
                          icon: AppIcons.chatBubbleOutline,
                          title: 'Safety Chat Bot',
                          subtitle: '20 uses per day.',
                        ),
                        const SizedBox(height: 10),
                        const _BenefitCard(
                          icon: AppIcons.scienceOutlined,
                          title: 'SDS Finder',
                          subtitle: '20 uses per day.',
                        ),
                        const SizedBox(height: 10),
                        const _BenefitCard(
                          icon: AppIcons.folderCopyOutlined,
                          title: 'Documents & Certificates',
                          subtitle: '20 saves per day.',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'and more',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFDA9B2A),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 24),

                        if (isPro)
                          const _ActiveMembership()
                        else if (_loading)
                          const _BillingLoading()
                        else if (_products.isEmpty)
                          _BillingUnavailable(
                            enabled: !_purchasing,
                            onRetry: _retry,
                          )
                        else
                          for (final product in _products)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _PlanCard(
                                product: product,
                                enabled: !_purchasing &&
                                    !_restoreRequestInFlight,
                                onTap: () => _buy(product),
                              ),
                            ),

                        if (!isPro && _purchaseMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppPalette.of(context).surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppPalette.of(context).border,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  AppIcons.infoOutline,
                                  size: 20,
                                  color: AppPalette.of(context).accent,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _purchaseMessage!,
                                    style: AppText.body(
                                      size: 13,
                                      color: AppPalette.of(context).text,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        if (!isPro && _error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppPalette.of(context).error.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppPalette.of(context).error.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              _error!,
                              style: AppText.body(
                                size: 13,
                                color: AppPalette.of(context).error,
                              ),
                            ),
                          ),
                        ],

                        if (!isPro &&
                            kShowPaywallDiagnostics &&
                            !_loading &&
                            _products.isEmpty &&
                            SubscriptionRepository.instance
                                .lastQueryDiagnostic != null) ...[
                          const SizedBox(height: 12),
                          SelectableText(
                            'Details: ${SubscriptionRepository.instance.lastQueryDiagnostic}',
                            style: AppText.label(
                              size: 11,
                              color: AppPalette.of(context).secondaryText,
                            ),
                          ),
                        ],

                        const SizedBox(height: 18),

                        if (_purchasing)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppPalette.of(context).accent,
                              ),
                            ),
                          ),

                        OutlinedButton.icon(
                          onPressed:
                              _purchasing || _restoreRequestInFlight
                                  ? null
                                  : _restore,
                          icon: const Icon(AppIcons.restore, size: 21),
                          label: const Text('Restore Purchases'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppPalette.of(context).text,
                            side: BorderSide(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? _PremiumColors.lightGold
                                  : _PremiumColors.bronze,
                              width: 1.3,
                            ),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        Text(
                          'Manage or cancel your subscription through Google Play.',
                          textAlign: TextAlign.center,
                          style: AppText.label(
                            size: 11,
                            color: AppPalette.of(context).secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =====================================================
// PREMIUM INDUSTRIAL DESIGN SYSTEM
// =====================================================

class _PremiumColors {
  static const ink = Color(0xFF171916);
  static const gold = Color(0xFFDA9B2A);
  static const lightGold = Color(0xFFFFE4A0);
  static const bronze = Color(0xFF95621C);
  static const cream = Color(0xFFF7F3E6);

  static const darkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF41443D),
      Color(0xFF20231E),
      Color(0xFF10120F),
      Color(0xFF292B25),
    ],
    stops: [0, 0.28, 0.72, 1],
  );

  static const goldGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFFFF0B8),
      Color(0xFFF1BC50),
      Color(0xFFDA9B2A),
      Color(0xFFAD7115),
    ],
    stops: [0, 0.28, 0.65, 1],
  );

  static const metallicBorder = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF95621C),
      Color(0xFFFFE4A0),
      Color(0xFFDA9B2A),
      Color(0xFF805014),
      Color(0xFFFFD77A),
    ],
  );
}

// =====================================================
// METALLIC PANEL
// =====================================================

class _MetallicPanel extends StatelessWidget {
  final Widget child;

  const _MetallicPanel({
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        gradient: _PremiumColors.metallicBorder,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: _PremiumColors.darkGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0x55FFFFFF),
          ),
        ),
        child: child,
      ),
    );
  }
}

// =====================================================
// ANIMATED DANGER TAPE
// =====================================================

class _IndustrialTape extends StatefulWidget {
  final bool reverse;

  const _IndustrialTape({this.reverse = false});

  @override
  State<_IndustrialTape> createState() => _IndustrialTapeState();
}

class _IndustrialTapeState extends State<_IndustrialTape>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
      _controller.value = 0;
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
        height: 9,
        width: double.infinity,
        child: CustomPaint(
          painter: _TapePainter(
            animation: _controller,
            reverse: widget.reverse,
          ),
        ),
      ),
    );
  }
}

class _TapePainter extends CustomPainter {
  final Animation<double> animation;
  final bool reverse;

  _TapePainter({
    required this.animation,
    required this.reverse,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.save();
    canvas.clipRect(rect);

    canvas.drawRect(
      rect,
      Paint()..color = _PremiumColors.ink,
    );

    final stripePaint = Paint()
      ..shader = _PremiumColors.goldGradient.createShader(rect);

    const double stripeWidth = 18;
    const double period = stripeWidth * 2;

    final shift =
        animation.value * period * (reverse ? -1 : 1);

    for (
      double x = -period * 2 + shift;
      x < size.width + period * 2;
      x += period
    ) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + stripeWidth, size.height)
        ..lineTo(x + stripeWidth + size.height, 0)
        ..lineTo(x + size.height, 0)
        ..close();

      canvas.drawPath(path, stripePaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TapePainter oldDelegate) {
    return oldDelegate.reverse != reverse ||
        oldDelegate.animation != animation;
  }
}

// =====================================================
// PREMIUM HEADER
// =====================================================

class _PremiumHeader extends StatelessWidget {
  final bool isPro;

  const _PremiumHeader({required this.isPro});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: _PremiumColors.darkGradient,
      ),
      child: Column(
        children: [
          const _IndustrialTape(),
          Stack(
            children: [
              const Positioned.fill(
                child: CustomPaint(
                  painter: _IndustrialSkylinePainter(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 26,
                ),
                child: Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) =>
                          _PremiumColors.goldGradient.createShader(bounds),
                      child: const Icon(
                        AppIcons.workspacePremium,
                        size: 54,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPro
                                ? 'Premium Active'
                                : 'Premium Membership',
                            style: AppText.headline(
                              size: 23,
                              weight: FontWeight.w700,
                            ).copyWith(
                              color: _PremiumColors.cream,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            isPro
                                ? 'Enjoy the full OHS ACT experience.'
                                : 'Unlock the full OHS ACT experience.',
                            style: AppText.body(
                              size: 13,
                              color: const Color(0xFFD6D2C5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const _IndustrialTape(reverse: true),
        ],
      ),
    );
  }
}

class _IndustrialSkylinePainter extends CustomPainter {
  const _IndustrialSkylinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x33000000);

    final w = size.width;
    final h = size.height;

    for (int i = 0; i < 9; i++) {
      final x = w * (0.04 + i * 0.115);
      final towerHeight = h * (0.18 + (i % 4) * 0.10);
      final towerWidth = w * 0.035;

      canvas.drawRect(
        Rect.fromLTWH(
          x,
          h - towerHeight,
          towerWidth,
          towerHeight,
        ),
        paint,
      );

      canvas.drawRect(
        Rect.fromLTWH(
          x + towerWidth * 0.35,
          h - towerHeight - 14,
          towerWidth * 0.3,
          14,
        ),
        paint,
      );

      canvas.drawRect(
        Rect.fromLTWH(
          x - 4,
          h - towerHeight + 12,
          towerWidth + 8,
          4,
        ),
        paint,
      );
    }

    canvas.drawRect(
      Rect.fromLTWH(0, h - 12, w, 12),
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _IndustrialSkylinePainter oldDelegate,
  ) => false;
}

// =====================================================
// BENEFIT CARDS
// =====================================================

class _BenefitCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _BenefitCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1.3),
      decoration: BoxDecoration(
        gradient: _PremiumColors.metallicBorder,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: Theme.of(context).brightness == Brightness.dark
              ? _PremiumColors.darkGradient
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFFCF3),
                    Color(0xFFF7F3E6),
                    Color(0xFFECE0C5),
                  ],
                ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: _PremiumColors.darkGradient,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _PremiumColors.gold,
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon,
                color: _PremiumColors.lightGold,
                size: 25,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppText.headline(
                      size: 15,
                      weight: FontWeight.w700,
                    ).copyWith(
                      color: AppPalette.of(context).text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppText.body(
                      size: 12,
                      color: AppPalette.of(context).secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              AppIcons.checkRounded,
              color: Theme.of(context).brightness == Brightness.dark
                  ? _PremiumColors.lightGold
                  : _PremiumColors.bronze,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// GLOSSY GOLD ACTION BUTTON
// =====================================================

class _GoldButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _GoldButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: _PremiumColors.goldGradient,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _PremiumColors.lightGold,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x44DA9B2A),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
              child: Row(
                children: [
                  const SizedBox(width: 24),
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: AppText.headline(
                        size: 17,
                        weight: FontWeight.w800,
                      ).copyWith(
                        color: _PremiumColors.ink,
                      ),
                    ),
                  ),
                  const Icon(
                    AppIcons.chevronRight,
                    color: _PremiumColors.ink,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================
// SUBSCRIPTION PLAN
// =====================================================

class _PlanCard extends StatelessWidget {
  final ProductDetails product;
  final bool enabled;
  final VoidCallback onTap;

  const _PlanCard({
    required this.product,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _MetallicPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                AppIcons.workspacePremium,
                color: _PremiumColors.gold,
                size: 42,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OHS ACT Pro',
                      style: AppText.headline(
                        size: 21,
                        weight: FontWeight.w800,
                      ).copyWith(
                        color: _PremiumColors.cream,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Monthly Membership',
                      style: AppText.body(
                        size: 13,
                        color: const Color(0xFFD6D2C5),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                AppIcons.shopOutlined,
                color: _PremiumColors.lightGold,
                size: 26,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '${product.price} / month',
            textAlign: TextAlign.center,
            style: AppText.headline(
              size: 27,
              weight: FontWeight.w800,
            ).copyWith(
              color: _PremiumColors.lightGold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Automatically renews monthly until cancelled.',
            textAlign: TextAlign.center,
            style: AppText.body(
              size: 12,
              color: const Color(0xFFD6D2C5),
            ),
          ),
          const SizedBox(height: 18),
          _GoldButton(
            label: 'Subscribe Now',
            onPressed: enabled ? onTap : null,
          ),
          const SizedBox(height: 14),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                AppIcons.lockOutline,
                size: 14,
                color: Color(0xFFD6D2C5),
              ),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Secure billing through Google Play',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFFD6D2C5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =====================================================
// BILLING LOADING STATE
// =====================================================

class _BillingLoading extends StatelessWidget {
  const _BillingLoading();

  @override
  Widget build(BuildContext context) {
    return const _MetallicPanel(
      child: Column(
        children: [
          CircularProgressIndicator(
            color: _PremiumColors.gold,
          ),
          SizedBox(height: 18),
          Text(
            'Connecting to Google Play',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _PremiumColors.cream,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Retrieving your subscription options...',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFD6D2C5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// BILLING UNAVAILABLE STATE
// =====================================================

class _BillingUnavailable extends StatelessWidget {
  final VoidCallback onRetry;
  final bool enabled;

  const _BillingUnavailable({
    required this.onRetry,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return _MetallicPanel(
      child: Column(
        children: [
          const Icon(
            AppIcons.cloudOffOutlined,
            color: _PremiumColors.gold,
            size: 36,
          ),
          const SizedBox(height: 12),
          const Text(
            'Subscription temporarily unavailable',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _PremiumColors.cream,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Google Play could not provide subscription options. Please try again.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFD6D2C5),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),
          _GoldButton(
            label: 'Try Again',
            onPressed: enabled ? onRetry : null,
          ),
        ],
      ),
    );
  }
}

// =====================================================
// ACTIVE PREMIUM MEMBERSHIP
// =====================================================

class _ActiveMembership extends StatelessWidget {
  const _ActiveMembership();

  @override
  Widget build(BuildContext context) {
    return const _MetallicPanel(
      child: Column(
        children: [
          Icon(
            AppIcons.verified,
            color: _PremiumColors.gold,
            size: 52,
          ),
          SizedBox(height: 14),
          Text(
            'Premium Membership Active',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _PremiumColors.lightGold,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Your premium benefits are unlocked.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _PremiumColors.cream,
              fontSize: 14,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Thank you for supporting OHS ACT.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFD6D2C5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
