typedef DateFormatter = String Function(DateTime value);

String friendlyTimeLabel({
  required DateTime occurredAt,
  required DateTime now,
  required DateFormatter formatTime,
  required DateFormatter formatDate,
  required DateFormatter formatWeekday,
}) {
  final event = occurredAt.toLocal();
  final current = now.toLocal();
  final difference = current.difference(event);
  if (difference.isNegative || difference < const Duration(minutes: 1)) {
    return 'Just now';
  }
  if (_sameDate(event, current)) {
    if (difference < const Duration(hours: 1)) {
      final minutes = difference.inMinutes;
      return '$minutes min ago';
    }
    if (difference < const Duration(hours: 6)) {
      final hours = difference.inHours;
      return '$hours ${hours == 1 ? 'hr' : 'hrs'} ago';
    }
    return 'Today, ${formatTime(event)}';
  }

  final currentDay = DateTime(current.year, current.month, current.day);
  final eventDay = DateTime(event.year, event.month, event.day);
  final dayDifference = currentDay.difference(eventDay).inDays;
  if (dayDifference == 1) {
    return 'Yesterday, ${formatTime(event)}';
  }
  if (dayDifference < 7) {
    return '${formatWeekday(event)}, ${formatTime(event)}';
  }
  return formatDate(event);
}

String activitySectionLabel(DateTime occurredAt, DateTime now) {
  final event = occurredAt.toLocal();
  final current = now.toLocal();
  final currentDay = DateTime(current.year, current.month, current.day);
  final eventDay = DateTime(event.year, event.month, event.day);
  final dayDifference = currentDay.difference(eventDay).inDays;
  if (dayDifference <= 0) return 'Today';
  if (dayDifference == 1) return 'Yesterday';
  if (dayDifference < 7) return 'Earlier this week';
  return 'Earlier';
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
