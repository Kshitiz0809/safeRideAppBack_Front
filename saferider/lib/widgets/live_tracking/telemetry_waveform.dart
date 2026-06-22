import 'dart:math';
import 'package:flutter/material.dart';

class TelemetryWaveform extends StatefulWidget {
  final double speed;
  final double jerk;
  final bool isDark;
  final Color accentColor;

  const TelemetryWaveform({
    super.key,
    required this.speed,
    required this.jerk,
    required this.isDark,
    required this.accentColor,
  });

  @override
  State<TelemetryWaveform> createState() => _TelemetryWaveformState();
}

class _TelemetryWaveformState extends State<TelemetryWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _WaveformPainter(
            phase: _controller.value,
            amplitude: (widget.speed / 100).clamp(0.15, 0.85),
            noise: (widget.jerk / 40).clamp(0.1, 1.0),
            color: widget.accentColor,
            isDark: widget.isDark,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double phase;
  final double amplitude;
  final double noise;
  final Color color;
  final bool isDark;

  _WaveformPainter({
    required this.phase,
    required this.amplitude,
    required this.noise,
    required this.color,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = size.height * 0.55;
    final path = Path();
    const segments = 48;

    for (var i = 0; i <= segments; i++) {
      final t = i / segments;
      final x = t * size.width;
      final wave = sin((t * pi * 4) + (phase * pi * 2)) * amplitude * 28;
      final ripple = sin((t * pi * 9) + (phase * pi * 4)) * noise * 10;
      final y = baseline + wave + ripple;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: isDark ? 0.22 : 0.18),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    final strokePaint = Paint()
      ..color = color.withValues(alpha: isDark ? 0.85 : 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.noise != noise;
  }
}
