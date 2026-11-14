import 'dart:math' as math;

import 'package:intl/intl.dart';

import 'models.dart';

class Fmt {
  static final NumberFormat _number = NumberFormat('#,##0', 'en_US');
  static final DateFormat _date = DateFormat('d MMM yyyy', 'en_US');
  static final DateFormat _dateTime = DateFormat('d MMM yyyy, HH:mm', 'en_US');
  static final DateFormat _month = DateFormat('MMM yyyy', 'en_US');

  static String money(dynamic value, {bool compact = false}) {
    final amount = asDouble(value);
    if (compact) {
      if (amount >= 1000000) {
        return 'UGX ${(amount / 1000000).toStringAsFixed(1)}m';
      }
      if (amount >= 1000) return 'UGX ${(amount / 1000).toStringAsFixed(0)}k';
    }
    return 'UGX ${_number.format(amount)}';
  }

  static String number(dynamic value) => _number.format(asInt(value));

  static DateTime? parseDate(dynamic value) {
    if (value == null) return null;
    final text = '$value'.trim();
    if (text.isEmpty || text == 'null') return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  static String date(dynamic value, {String fallback = '—'}) {
    final parsed = parseDate(value);
    return parsed == null ? fallback : _date.format(parsed);
  }

  static String dateTime(dynamic value, {String fallback = '—'}) {
    final parsed = parseDate(value);
    return parsed == null ? fallback : _dateTime.format(parsed);
  }

  static String month(DateTime value) => _month.format(value);

  static String today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static String relative(DateTime? value) {
    if (value == null) return 'never';
    final difference = DateTime.now().difference(value);
    if (difference.inSeconds < 45) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} h ago';
    return '${difference.inDays} d ago';
  }

  static String labelize(dynamic value, {String fallback = ''}) {
    final text = asString(value).trim();
    if (text.isEmpty) return fallback;
    final words = text.replaceAll('-', '_').split('_');
    final lower = words
        .map((word) => word.isEmpty ? word : word.toLowerCase())
        .join(' ');
    if (lower.isEmpty) return fallback;
    return lower[0].toUpperCase() + lower.substring(1);
  }

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final letters = parts.take(2).map((part) => part[0].toUpperCase()).join();
    return letters;
  }

  static String truncate(String value, int length) {
    if (value.length <= length) return value;
    return '${value.substring(0, math.max(0, length - 1))}…';
  }

  /// Guarantee status calculated from cached data.  The exact policy is still
  /// pending owner confirmation (see docs/BUSINESS_RULES.md).
  static String guaranteeStatus(Map<String, dynamic> placement) {
    final start = parseDate(placement['start_date']);
    final days = asInt(placement['guarantee_days']);
    if (start == null || days <= 0) return 'UNKNOWN';
    final today = DateTime.now();
    final startDay = DateTime(start.year, start.month, start.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    if (todayDay.isBefore(startDay)) return 'NOT_STARTED';
    final end = startDay.add(Duration(days: days));
    return todayDay.isAfter(end) ? 'EXPIRED' : 'IN_GUARANTEE';
  }

  static bool isOpenFollowUp(Map<String, dynamic> followUp) =>
      followUp['completed_at'] == null || '${followUp['completed_at']}' == '';

  static bool isDueToday(Map<String, dynamic> followUp) =>
      isOpenFollowUp(followUp) && '${followUp['due_date']}' == today();

  static bool isOverdue(Map<String, dynamic> followUp) {
    if (!isOpenFollowUp(followUp)) return false;
    final due = parseDate(followUp['due_date']);
    if (due == null) return false;
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(due.year, due.month, due.day);
    return dueDate.isBefore(todayDate);
  }
}
