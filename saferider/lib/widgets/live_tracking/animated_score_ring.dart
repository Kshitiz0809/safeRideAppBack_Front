import 'package:flutter/material.dart';

class AnimatedScoreRing extends StatelessWidget {
  final double score;
  final Color color;
  final double size;
  final double pulse;

  const AnimatedScoreRing({
    super.key,
    required this.score,
    required this.color,
    required this.size,
    this.pulse = 1.0,
  });

  String get _label {
    if (score >= 75) return 'SAFE';
    if (score >= 50) return 'WARN';
    return 'RISK';
  }

  @override
  Widget build(BuildContext context) {
    final ringSize = size * pulse;
    final strokeWidth = ringSize * 0.06;

    return SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow
          Container(
            width: ringSize,
            height: ringSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.20),
                  blurRadius: 28 * pulse,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          // Track
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: strokeWidth,
              color: color.withValues(alpha: 0.10),
              strokeCap: StrokeCap.round,
            ),
          ),
          // Progress
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: (score / 100).clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => CircularProgressIndicator(
                value: value,
                strokeWidth: strokeWidth,
                color: color,
                strokeCap: StrokeCap.round,
              ),
            ),
          ),
          // Score text
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: score, end: score),
                duration: const Duration(milliseconds: 400),
                builder: (context, v, _) => Text(
                  score.toInt().toString(),
                  style: TextStyle(
                    fontSize: ringSize * 0.295,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1.0,
                    letterSpacing: -1,
                  ),
                ),
              ),
              SizedBox(height: ringSize * 0.02),
              Text(
                _label,
                style: TextStyle(
                  fontSize: ringSize * 0.09,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.w700,
                  color: color.withValues(alpha: 0.70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
