import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  static TextStyle headline(
          {double size = 24, FontWeight weight = FontWeight.w700}) =>
      GoogleFonts.inter(
          fontSize: size,
          fontWeight: weight,
          color: AppColors.ink,
          height: 1.08);

  static TextStyle label({double size = 11, Color? color}) =>
      GoogleFonts.ibmPlexMono(
        fontSize: size,
        letterSpacing: 0.03 * size,
        color: color ?? AppColors.steel,
      );

  static TextStyle body({double size = 15, Color? color}) => GoogleFonts.inter(
        fontSize: size,
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
    textTheme: GoogleFonts.interTextTheme(),
    dividerColor: AppColors.line,
    splashColor: AppColors.amber.withValues(alpha: 0.3),
  );
}

class HazardStripe extends StatelessWidget {
  final double height;
  const HazardStripe({super.key, this.height = 9});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _HazardStripePainter()),
    );
  }
}

class _HazardStripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const stripeWidth = 12.0;
    final paintAmber = Paint()..color = AppColors.amber;
    final paintInk = Paint()..color = AppColors.ink;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paintAmber);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final diag = size.width + size.height;
    for (double x = -size.height; x < diag; x += stripeWidth * 2) {
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
