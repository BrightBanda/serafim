import 'package:flutter/material.dart';

/// Compact timestamp for the chat list: time today, "Yesterday", then date.
String formatChatListTime(BuildContext context, DateTime timestamp) {
  final local = timestamp.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;

  if (days <= 0) return TimeOfDay.fromDateTime(local).format(context);
  if (days == 1) return 'Yesterday';
  if (days < 7) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[local.weekday - 1];
  }
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  return '$d/$m/${local.year % 100}';
}
