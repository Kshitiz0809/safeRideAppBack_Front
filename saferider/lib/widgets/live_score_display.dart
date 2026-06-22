import 'package:flutter/material.dart';

class LiveScoreDisplay extends StatelessWidget {
  final double score;

  const LiveScoreDisplay({required this.score, Key? key}) : super(key: key);

  Color _getScoreColor() {
    if (score >= 80) {
      return Colors.greenAccent;
    } else if (score >= 60) {
      return Colors.orangeAccent;
    } else {
      return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getScoreColor();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withOpacity(0.2),
              width: 12,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Progress indicator ring
              SizedBox(
                width: 180,
                height: 180,
                child: CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 8,
                  color: color,
                  backgroundColor: Colors.transparent,
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    score.toInt().toString(),
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const Text(
                    'SCORE',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
