import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final String result;

  const StatusBadge({Key? key, required this.result}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    IconData iconData;
    String label;

    switch (result) {
      case 'present':
        label = 'Present';
        bgColor = Colors.green.shade50;
        textColor = Colors.green.shade600;
        iconData = Icons.check_circle;
        break;
      case 'duplicate':
        label = 'Late'; // Maps to 'Late' in React app mock
        bgColor = Colors.amber.shade50;
        textColor = Colors.amber.shade600;
        iconData = Icons.access_time_filled;
        break;
      case 'unknown':
      default:
        label = 'Absent';
        bgColor = Colors.red.shade50;
        textColor = Colors.red.shade600;
        iconData = Icons.cancel;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
