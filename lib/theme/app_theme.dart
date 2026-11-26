import 'package:flutter/material.dart';

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

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.paper,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.amberDeep,
      brightness: Brightness.light,
      surface: AppColors.paper,
    ),
    fontFamily: AppText.fontFamily,
    dividerColor: AppColors.line,
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
