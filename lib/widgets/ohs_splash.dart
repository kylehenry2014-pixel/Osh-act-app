import 'package:flutter/material.dart';

// =====================================================
// OHS ACT & REGULATIONS
// PREMIUM INDUSTRIAL SPLASH SCREEN
// =====================================================

class OhsSplash extends StatefulWidget {
  const OhsSplash({
    super.key,
    required this.onFinished,
  });

  final VoidCallback onFinished;

  @override
  State<OhsSplash> createState() => _OhsSplashState();
}

class _SplashStyle {
  static const ink = Color(0xFF1B1E19);
  static const gold = Color(0xFFDA9B2A);
  static const lightGold = Color(0xFFFFE4A0);
  static const cream = Color(0xFFF7F3E6);

  static const background = RadialGradient(
    center: Alignment(0, -0.2),
    radius: 0.95,
    colors: [
      Color(0xFF393A2C),
      Color(0xFF1B1E19),
      Color(0xFF10120F),
    ],
    stops: [0, 0.55, 1],
  );

  static const metallicGold = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF805014),
      Color(0xFFFFE4A0),
      Color(0xFFD6A044),
      Color(0xFF805014),
      Color(0xFFFFD77A),
    ],
    stops: [0, 0.23, 0.48, 0.76, 1],
  );
}

class _OhsSplashState extends State<OhsSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _exitOpacity;

  bool _started = false;
  bool _finished = false;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _exitOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: ConstantTween<double>(1),
        weight: 1500,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0,
        ).chain(
          CurveTween(curve: Curves.easeInOut),
        ),
        weight: 300,
      ),
    ]).animate(_controller);

    _controller.addStatusListener(_onStatusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _reducedMotion =
        MediaQuery.of(context).disableAnimations;

    if (!_started) {
      _started = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (_reducedMotion) {
          _finish();
        } else {
          _controller.forward();
        }
      });
    } else if (_reducedMotion && !_finished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _finish();
      });
    }
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _finish();
    }
  }

  void _finish() {
    if (_finished || !mounted) return;

    _finished = true;
    _controller.stop();
    widget.onFinished();
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatusChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlockSemantics(
      child: AbsorbPointer(
        child: FadeTransition(
          opacity: _exitOpacity,
          child: Material(
            color: _SplashStyle.ink,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: _SplashStyle.background,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final height = constraints.maxHeight;

                  final cornerWidth =
                      (width * 0.48)
                          .clamp(100.0, 240.0)
                          .toDouble();

                  final cornerHeight =
                      cornerWidth * 0.64;

                  final emblemSize =
                      (width * 0.28)
                          .clamp(76.0, 120.0)
                          .toDouble();

                  return Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.hardEdge,
                    children: [
                      // Top-left animated danger tape.
                      Positioned(
                        top: 0,
                        left: 0,
                        width: cornerWidth,
                        height: cornerHeight,
                        child: ClipPath(
                          clipper:
                              const _CornerClipper(),
                          child: _MovingTape(
                            animation: _controller,
                            reducedMotion:
                                _reducedMotion,
                          ),
                        ),
                      ),

                      // Bottom-right danger tape.
                      // Moves in the opposite direction.
                      Positioned(
                        bottom: 0,
                        right: 0,
                        width: cornerWidth,
                        height: cornerHeight,
                        child: ClipPath(
                          clipper: const _CornerClipper(
                            bottomRight: true,
                          ),
                          child: _MovingTape(
                            animation: _controller,
                            reverse: true,
                            reducedMotion:
                                _reducedMotion,
                          ),
                        ),
                      ),

                      // Stationary branding.
                      SafeArea(
                        child: Align(
                          alignment:
                              const Alignment(0, -0.12),
                          child: Padding(
                            padding:
                                const EdgeInsets.all(24),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize:
                                    MainAxisSize.min,
                                children: [
                                  _MetallicEmblem(
                                    size: emblemSize,
                                    animation:
                                        _controller,
                                    reducedMotion:
                                        _reducedMotion,
                                  ),

                                  const SizedBox(
                                    height: 28,
                                  ),

                                  const Text(
                                    'OHS Act',
                                    textAlign:
                                        TextAlign.center,
                                    style: TextStyle(
                                      color:
                                          _SplashStyle.cream,
                                      fontSize: 39,
                                      fontWeight:
                                          FontWeight.w800,
                                      letterSpacing: 1.2,
                                      height: 1.1,
                                    ),
                                  ),

                                  const SizedBox(
                                    height: 6,
                                  ),

                                  const Text(
                                    '& Regulations',
                                    textAlign:
                                        TextAlign.center,
                                    style: TextStyle(
                                      color:
                                          _SplashStyle.gold,
                                      fontSize: 27,
                                      fontWeight:
                                          FontWeight.w600,
                                      letterSpacing: 0.3,
                                    ),
                                  ),

                                  const SizedBox(
                                    height: 22,
                                  ),

                                  Container(
                                    width: 110,
                                    height: 1,
                                    decoration:
                                        const BoxDecoration(
                                      gradient:
                                          LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          _SplashStyle.gold,
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),

                                  const SizedBox(
                                    height: 20,
                                  ),

                                  const Text(
                                    'YOUR SAFETY COMPANION',
                                    textAlign:
                                        TextAlign.center,
                                    style: TextStyle(
                                      color:
                                          Color(0xFFBCB9AC),
                                      fontSize: 10,
                                      fontWeight:
                                          FontWeight.w500,
                                      letterSpacing: 2.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Decorative loading animation.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: (height * 0.12)
                            .clamp(24.0, 100.0)
                            .toDouble(),
                        child: SafeArea(
                          top: false,
                          child: Center(
                            child: _SplashLoader(
                              animation: _controller,
                              reducedMotion:
                                  _reducedMotion,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================
// STATIONARY METALLIC EMBLEM
// ANIMATED DANGER TAPE INSIDE
// =====================================================

class _MetallicEmblem extends StatelessWidget {
  final double size;
  final Animation<double> animation;
  final bool reducedMotion;

  const _MetallicEmblem({
    required this.size,
    required this.animation,
    required this.reducedMotion,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: _SplashStyle.metallicGold,
        borderRadius: BorderRadius.circular(23),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33DA9B2A),
            blurRadius: 25,
          ),
          BoxShadow(
            color: Color(0x88000000),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _MovingTape(
              animation: animation,
              reducedMotion: reducedMotion,
            ),

            // Fixed glossy reflection.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0x44FFFFFF),
                    Colors.transparent,
                    Color(0x33000000),
                  ],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),

            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0x66FFE4A0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// MOVING DANGER TAPE
// =====================================================

class _MovingTape extends StatelessWidget {
  final Animation<double> animation;
  final bool reverse;
  final bool reducedMotion;

  const _MovingTape({
    required this.animation,
    this.reverse = false,
    this.reducedMotion = false,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _SmoothTapePainter(
          animation: animation,
          reverse: reverse,
          reducedMotion: reducedMotion,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SmoothTapePainter extends CustomPainter {
  final Animation<double> animation;
  final bool reverse;
  final bool reducedMotion;

  _SmoothTapePainter({
    required this.animation,
    required this.reverse,
    required this.reducedMotion,
  }) : super(
          repaint: reducedMotion ? null : animation,
        );

  static const double bandWidth = 20;
  static const double period = bandWidth * 2;

  final Paint _darkPaint = Paint()
    ..color = _SplashStyle.ink;

  final Paint _goldPaint = Paint()
    ..color = const Color(0xFFDCA02E);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.save();
    canvas.clipRect(rect);

    canvas.drawRect(rect, _darkPaint);

    // Linear motion at approximately 13.33 pixels
    // per second. No reset or direction reversal.
    final elapsedSeconds = animation.value * 1.8;

    final distance = reducedMotion
        ? 0.0
        : elapsedSeconds * (period / 3.0);

    final shift =
        reverse ? -distance : distance;

    final start =
        -size.height - period * 2 + shift;

    final end =
        size.width + size.height + period * 2;

    for (
      double x = start;
      x < end;
      x += period
    ) {
      final stripe = Path()
        ..moveTo(x, 0)
        ..lineTo(x + bandWidth, 0)
        ..lineTo(
          x + bandWidth - size.height,
          size.height,
        )
        ..lineTo(
          x - size.height,
          size.height,
        )
        ..close();

      canvas.drawPath(stripe, _goldPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(
    covariant _SmoothTapePainter oldDelegate,
  ) {
    return oldDelegate.animation != animation ||
        oldDelegate.reverse != reverse ||
        oldDelegate.reducedMotion != reducedMotion;
  }
}

// =====================================================
// DIAGONAL CORNER CLIPPING
// =====================================================

class _CornerClipper extends CustomClipper<Path> {
  final bool bottomRight;

  const _CornerClipper({
    this.bottomRight = false,
  });

  @override
  Path getClip(Size size) {
    if (bottomRight) {
      return Path()
        ..moveTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
    }

    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(
    covariant _CornerClipper oldClipper,
  ) => oldClipper.bottomRight != bottomRight;
}

// =====================================================
// SMOOTH GOLD LOADING INDICATOR
// =====================================================

class _SplashLoader extends StatelessWidget {
  final Animation<double> animation;
  final bool reducedMotion;

  const _SplashLoader({
    required this.animation,
    required this.reducedMotion,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 145,
        height: 4,
        child: CustomPaint(
          painter: _LoaderPainter(
            animation: animation,
            reducedMotion: reducedMotion,
          ),
        ),
      ),
    );
  }
}

class _LoaderPainter extends CustomPainter {
  final Animation<double> animation;
  final bool reducedMotion;

  _LoaderPainter({
    required this.animation,
    required this.reducedMotion,
  }) : super(
          repaint: reducedMotion ? null : animation,
        );

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final track = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(4),
    );

    canvas.drawRRect(
      track,
      Paint()..color = const Color(0x18FFFFFF),
    );

    canvas.save();
    canvas.clipRRect(track);

    const double segmentWidth = 48;

    final x = reducedMotion
        ? (size.width - segmentWidth) / 2
        : -segmentWidth +
            animation.value *
                (size.width + segmentWidth);

    final segment = Rect.fromLTWH(
      x,
      0,
      segmentWidth,
      size.height,
    );

    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Colors.transparent,
          _SplashStyle.lightGold,
          _SplashStyle.gold,
          Colors.transparent,
        ],
        stops: [0, 0.4, 0.6, 1],
      ).createShader(segment);

    canvas.drawRect(segment, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(
    covariant _LoaderPainter oldDelegate,
  ) {
    return oldDelegate.animation != animation ||
        oldDelegate.reducedMotion != reducedMotion;
  }
}