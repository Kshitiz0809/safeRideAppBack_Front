import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final String status;

  const StatusBadge({required this.status, Key? key}) : super(key: key);

  Color _getStatusColor() {
    if (status.contains('Aggressive')) {
      return Colors.orangeAccent;
    } else if (status.contains('High Speed')) {
      return Colors.deepOrange;
    } else if (status.contains('Idle') || status.contains('Calibrating')) {
      return Colors.blueGrey;
    } else if (status.contains('Rapid braking') || status.contains('Unsafe')) {
      return Colors.redAccent;
    } else {
      return Colors.green.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color, blurRadius: 4, spreadRadius: 1),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
