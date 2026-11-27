import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppColors {
  static const ink = Color(0xFF1B1E19);
  static const paper = Color(0xFFEFE9D8);
  static const paperRaised = Color(0xFFF7F3E6);
  static const amber = Color(0xFFDA9B2A);
  static const amberDeep = Color(0xFFB87D1A);
  static const red = Color(0xFFA23B2E);
  static const green = Color(0xFF4C6B4F);
  static const steel = Color(0xFF48595D);
  static const line = Color(0x241B1E19);
  static const lineStrong = Color(0x471B1E19);
}

class AppText {
  static const String fontFamily = 'Inter';

  static TextStyle headline({
    double size = 24,
    FontWeight weight = FontWeight.w700,
  }) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        color: AppColors.ink,
        height: 1.08,
      );

  static TextStyle label({
    double size = 11,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.03 * size,
        color: color ?? AppColors.steel,
      );

  static TextStyle body({
    double size = 15,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color ?? AppColors.ink,
      );
}

// =====================================================
// ADAPTIVE APPLICATION PALETTE
// =====================================================

@immutable
class AppPalette {
  final Color background;
  final Color surface;
  final Color text;
  final Color secondaryText;
  final Color accent;
  final Color border;
  final Color strongBorder;
  final Color error;
  final Color success;

  const AppPalette({
    required this.background,
    required this.surface,
    required this.text,
    required this.secondaryText,
    required this.accent,
    required this.border,
    required this.strongBorder,
    required this.error,
    required this.success,
  });

  static const light = AppPalette(
    background: AppColors.paper,
    surface: AppColors.paperRaised,
    text: AppColors.ink,
    secondaryText: AppColors.steel,
    accent: AppColors.amberDeep,
    border: AppColors.line,
    strongBorder: AppColors.lineStrong,
    error: AppColors.red,
    success: AppColors.green,
  );

  static const dark = AppPalette(
    background: Color(0xFF171916),
    surface: Color(0xFF292C26),
    text: Color(0xFFF7F3E6),
    secondaryText: Color(0xFFC5C6BB),
    accent: Color(0xFFDA9B2A),
    border: Color(0xFF55594E),
    strongBorder: Color(0xFF85897D),
    error: Color(0xFFFF9B8E),
    success: Color(0xFF9AC99E),
  );

  static AppPalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? dark
        : light;
  }
}

class OhsPageTransitionsBuilder
    extends PageTransitionsBuilder {
  const OhsPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.of(context).disableAnimations) {
      return child;
    }

    final curved = animation.drive(
      CurveTween(curve: Curves.easeOutCubic),
    );

    final position = curved.drive(
      Tween<Offset>(
        begin: const Offset(0, 0.018),
        end: Offset.zero,
      ),
    );

    final opacity = curved.drive(
      Tween<double>(
        begin: 0,
        end: 1,
      ),
    );

    return FadeTransition(
      opacity: opacity,
      child: SlideTransition(
        position: position,
        child: child,
      ),
    );
  }
}

ThemeData buildAppTheme({
  Brightness brightness = Brightness.light,
}) {
  final palette = brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;

  return ThemeData(
    useMaterial3: true,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android:
            OhsPageTransitionsBuilder(),
      },
    ),
    brightness: brightness,
    scaffoldBackgroundColor: palette.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.amberDeep,
      brightness: brightness,
      surface: palette.background,
    ).copyWith(
      surfaceContainerHigh: brightness == Brightness.dark
          ? palette.surface
          : null,
      onSurface: brightness == Brightness.dark
          ? palette.text
          : null,
      onSurfaceVariant: brightness == Brightness.dark
          ? palette.secondaryText
          : null,
      outline: brightness == Brightness.dark
          ? palette.strongBorder
          : null,
      outlineVariant: brightness == Brightness.dark
          ? palette.border
          : null,
      error: brightness == Brightness.dark
          ? palette.error
          : null,
      inverseSurface: brightness == Brightness.dark
          ? palette.text
          : null,
      onInverseSurface: brightness == Brightness.dark
          ? palette.background
          : null,
    ),
    fontFamily: AppText.fontFamily,
    dividerColor: palette.border,
    splashColor: AppColors.amber.withValues(alpha: 0.3),
  );
}

class HazardStripe extends StatefulWidget {
  final double height;

  const HazardStripe({super.key, this.height = 9});

  @override
  State<HazardStripe> createState() => _HazardStripeState();
}

class _HazardStripeState extends State<HazardStripe>
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
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _HazardStripePainter(_controller),
        ),
      ),
    );
  }
}

class _HazardStripePainter extends CustomPainter {
  final Animation<double> animation;

  _HazardStripePainter(this.animation)
      : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    const stripeWidth = 12.0;
    const period = stripeWidth * 2;
    final shift = animation.value * period;

    final rect = Offset.zero & size;
    final paintAmber = Paint()..color = AppColors.amber;
    final paintInk = Paint()..color = AppColors.ink;

    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(rect, paintAmber);

    for (
      double x = -size.height - period + shift;
      x < size.width + size.height + period;
      x += period
    ) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + size.height, 0)
        ..lineTo(x + size.height + stripeWidth, 0)
        ..lineTo(x + stripeWidth, size.height)
        ..close();

      canvas.drawPath(path, paintInk);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(
    covariant _HazardStripePainter oldDelegate,
  ) => oldDelegate.animation != animation;
}

class PremiumSectionAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;
  final double titleSize;
  final Widget? leading;
  final List<Widget>? actions;
  final bool automaticallyImplyLeading;

  const PremiumSectionAppBar({
    super.key,
    required this.title,
    this.titleSize = 18,
    this.leading,
    this.actions,
    this.automaticallyImplyLeading = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(76);

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFE4A0);

    return AppBar(
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading,
      actions: actions,
      toolbarHeight: 70,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      backgroundColor: AppColors.ink,
      foregroundColor: gold,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: const IconThemeData(color: gold),
      actionsIconTheme: const IconThemeData(color: gold),
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF3B3E35),
              Color(0xFF252820),
              Color(0xFF1B1E19),
            ],
          ),
        ),
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OHS ACT & REGULATIONS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.label(
              size: 10,
              color: AppColors.amber,
            ).copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.headline(
              size: titleSize,
            ).copyWith(
              color: AppColors.paperRaised,
            ),
          ),
        ],
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(6),
        child: HazardStripe(height: 6),
      ),
    );
  }
}

class PremiumHeaderSurface extends StatelessWidget {
  final Widget child;

  const PremiumHeaderSurface({
    super.key,
    required this.child,
  });

  static const gold = Color(0xFFFFE4A0);
  static const muted = Color(0xFFD6D2C5);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF3B3E35),
            Color(0xFF252820),
            Color(0xFF1B1E19),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            type: MaterialType.transparency,
            child: child,
          ),
          const HazardStripe(height: 6),
        ],
      ),
    );
  }
}

class PremiumHeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  const PremiumHeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      style: IconButton.styleFrom(
        foregroundColor: active
            ? AppColors.ink
            : PremiumHeaderSurface.gold,
        backgroundColor: active
            ? AppColors.amber
            : const Color(0xFF30332C),
        overlayColor: active
            ? AppColors.ink.withValues(alpha: 0.16)
            : PremiumHeaderSurface.gold.withValues(alpha: 0.18),
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: active
                ? PremiumHeaderSurface.gold
                : const Color(0xFF66604B),
          ),
        ),
      ),
    );
  }
}
