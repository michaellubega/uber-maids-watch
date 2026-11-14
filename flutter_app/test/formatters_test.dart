import 'package:flutter_test/flutter_test.dart';
import 'package:uber_maids_watch/core/formatters.dart';

void main() {
  group('Fmt', () {
    test('formats money in UGX', () {
      expect(Fmt.money(1500000), 'UGX 1,500,000');
      expect(Fmt.money(1500000, compact: true), 'UGX 1.5m');
      expect(Fmt.money('25000', compact: true), 'UGX 25k');
      expect(Fmt.money(null), 'UGX 0');
    });

    test('formats dates and falls back safely', () {
      expect(Fmt.date('2026-03-09'), '9 Mar 2026');
      expect(Fmt.date('not-a-date'), '—');
      expect(Fmt.date(null), '—');
    });

    test('labelizes status values', () {
      expect(Fmt.labelize('CLIENT_SATISFIED'), 'Client satisfied');
      expect(Fmt.labelize('IN_GUARANTEE'), 'In guarantee');
      expect(Fmt.labelize(''), '');
    });

    test('calculates guarantee status from cached fields', () {
      final today = DateTime.now();
      String iso(DateTime value) =>
          '${value.year.toString().padLeft(4, '0')}-'
          '${value.month.toString().padLeft(2, '0')}-'
          '${value.day.toString().padLeft(2, '0')}';

      expect(
        Fmt.guaranteeStatus({
          'start_date': iso(today),
          'guarantee_days': 14,
        }),
        'IN_GUARANTEE',
      );
      expect(
        Fmt.guaranteeStatus({
          'start_date': iso(today.add(const Duration(days: 2))),
          'guarantee_days': 14,
        }),
        'NOT_STARTED',
      );
      expect(
        Fmt.guaranteeStatus({
          'start_date': iso(today.subtract(const Duration(days: 20))),
          'guarantee_days': 14,
        }),
        'EXPIRED',
      );
      expect(Fmt.guaranteeStatus({'start_date': null}), 'UNKNOWN');
    });

    test('identifies overdue and open follow-ups', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final due = '${yesterday.year.toString().padLeft(4, '0')}-'
          '${yesterday.month.toString().padLeft(2, '0')}-'
          '${yesterday.day.toString().padLeft(2, '0')}';
      expect(Fmt.isOpenFollowUp({'completed_at': null}), isTrue);
      expect(Fmt.isOverdue({'due_date': due, 'completed_at': null}), isTrue);
      expect(
        Fmt.isOverdue({'due_date': due, 'completed_at': '2026-01-01'}),
        isFalse,
      );
    });
  });
}
