import 'dart:math' as math;
import 'package:flutter/material.dart';

class OhsSplash extends StatefulWidget {
  const OhsSplash({
    super.key,
    required this.onFinished,
  });

  final VoidCallback onFinished;

  @override
  State<OhsSplash> createState() => _OhsSplashState();
}

class _OhsSplashState extends State<OhsSplash>
    with SingleTickerProviderStateMixin {
  static const Color _amber = Color(0xFFDA9B2A);
  static const Color _ink = Color(0xFF1B1E19);
  static const Color _plate = Color(0xFFF7F3E6);
  static const Color _steel = Color(0xFF48595D);

  late final AnimationController _controller;

  bool _reducedMotion = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3350),
    );

    _controller.addStatusListener(_onStatusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final bool reduced =
        MediaQuery.of(context).disableAnimations;

    if (reduced != _reducedMotion ||
        !_controller.isAnimating &&
            _controller.value == 0.0) {
      _reducedMotion = reduced;

      if (_controller.value == 0.0) {
        _controller.forward();
      }
    }
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_finished) {
      _finished = true;
      widget.onFinished();
    }
  }

  double _progress(
    double startMs,
    double endMs,
    Curve curve,
  ) {
    final double currentMs = _controller.value * 3350.0;

    final double t = ((currentMs - startMs) /
            (endMs - startMs))
        .clamp(0.0, 1.0);

    return curve.transform(t);
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatusChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double screenWidth = constraints.maxWidth;

        final double titleSize =
            (screenWidth * 0.11).clamp(36.0, 120.0).toDouble();

        final double subtitleSize =
            (screenWidth * 0.07).clamp(23.0, 76.0).toDouble();

        return AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            final double currentMs =
                _controller.value * 3350.0;

            final bool exiting = currentMs >= 3000.0;

            final double stripeProgress = _reducedMotion
                ? 1.0
                : _progress(0.0, 3000.0, Curves.linear);

            final double plateProgress = _reducedMotion
                ? 1.0
                : _progress(600.0, 1300.0, Curves.easeOut);

            final double titleProgress = _reducedMotion
                ? 1.0
                : _progress(1100.0, 1700.0, Curves.ease);

            final double subtitleProgress = _reducedMotion
                ? 1.0
                : _progress(1500.0, 2100.0, Curves.ease);

            final double exitProgress =
                _progress(3000.0, 3350.0, Curves.ease);

            return IgnorePointer(
              ignoring: exiting,
              child: Opacity(
                opacity: 1.0 - exitProgress,
                child: SizedBox.expand(
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.hardEdge,
                    children: <Widget>[
                      const Positioned.fill(
                        child: ColoredBox(color: _amber),
                      ),

                      Positioned.fill(
                        child: ClipRect(
                          child: OverflowBox(
                            minWidth: constraints.maxWidth + 500.0,
                            maxWidth: constraints.maxWidth + 500.0,
                            minHeight: constraints.maxHeight + 500.0,
                            maxHeight: constraints.maxHeight + 500.0,
                            alignment: Alignment.center,
                            child: Transform.translate(
                              offset: Offset(
                                160.0 * stripeProgress,
                                0.0,
                              ),
                              child: CustomPaint(
                                painter: const _HazardStripePainter(
                                  ink: _ink,
                                  amber: _amber,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                      ),

                      Center(
                        child: Opacity(
                          opacity: plateProgress,
                          child: Transform.scale(
                            scale: 0.85 + 0.15 * plateProgress,
                            child: Container(
                              width: screenWidth * 0.8333,
                              padding: const EdgeInsets.symmetric(
                                vertical: 50.0,
                                horizontal: 8.0,
                              ),
                              decoration: BoxDecoration(
                                color: _plate,
                                border: Border.all(
                                  color: _ink,
                                  width: 5.0,
                                ),
                                borderRadius:
                                    BorderRadius.circular(16.0),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  _AnimatedSplashText(
                                    text: 'OHS Act',
                                    fontSize: titleSize,
                                    color: _ink,
                                    progress: titleProgress,
                                  ),
                                  _AnimatedSplashText(
                                    text: '& Regulations',
                                    fontSize: subtitleSize,
                                    color: _steel,
                                    progress: subtitleProgress,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AnimatedSplashText extends StatelessWidget {
  const _AnimatedSplashText({
    required this.text,
    required this.fontSize,
    required this.color,
    required this.progress,
  });

  final String text;
  final double fontSize;
  final Color color;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: progress,
      child: Transform.translate(
        offset: Offset(
          0.0,
          12.0 * (1.0 - progress),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          softWrap: false,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: 'Georgia',
            fontFamilyFallback: const <String>[
              'serif',
            ],
            fontWeight: FontWeight.w700,
            fontSize: fontSize,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _HazardStripePainter extends CustomPainter {
  const _HazardStripePainter({
    required this.ink,
    required this.amber,
  });

  final Color ink;
  final Color amber;

  static const double _bandWidth = 80.0;
  static const double _period = 160.0;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint amberPaint = Paint()
      ..color = amber
      ..style = PaintingStyle.fill;

    final Paint inkPaint = Paint()
      ..color = ink
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Offset.zero & size,
      amberPaint,
    );

    final double diagonal = math.sqrt(2.0);

    final double horizontalBand = _bandWidth * diagonal;
    final double horizontalPeriod = _period * diagonal;

    final double start = -size.height - horizontalPeriod;
    final double end =
        size.width + size.height + horizontalPeriod;

    for (double x = start;
        x < end;
        x += horizontalPeriod) {
      final Path stripe = Path()
        ..moveTo(x, 0.0)
        ..lineTo(x + horizontalBand, 0.0)
        ..lineTo(
          x + horizontalBand - size.height,
          size.height,
        )
        ..lineTo(
          x - size.height,
          size.height,
        )
        ..close();

      canvas.drawPath(stripe, inkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HazardStripePainter oldDelegate) {
    return oldDelegate.ink != ink ||
        oldDelegate.amber != amber;
  }
}

/*
Parent usage example:

bool showSplash = true;

Stack(
  children: [
    HomeScreen(),
    if (showSplash)
      OhsSplash(
        onFinished: () =>
            setState(() => showSplash = false),
      ),
  ],
)
*/
