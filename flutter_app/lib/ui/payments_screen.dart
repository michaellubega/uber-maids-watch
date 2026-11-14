import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../core/models.dart';
import '../state/app_state.dart';
import 'forms/payment_form.dart';
import 'widgets.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  String _query = '';
  String _filter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final padding = pagePadding(context);
    final all = app.rows('payment');
    final rows = all.where((row) {
      if (_filter != 'ALL' && '${row['status']}' != _filter) return false;
      if (_query.isEmpty) return true;
      return [
        row['receipt_reference'],
        row['client_name'],
        row['client_number'],
        row['placement_number'],
        row['booking_number'],
        row['payment_method'],
        row['reference'],
      ].join(' ').toLowerCase().contains(_query.toLowerCase());
    }).toList()
      ..sort((a, b) => '${b['created_at'] ?? ''}'
          .compareTo('${a['created_at'] ?? ''}'));

    final paid = all
        .where((row) => row['status'] == 'PAID')
        .fold<double>(0, (sum, row) => sum + asDouble(row['amount_ugx']));
    final outstanding = all
        .where((row) => const {'PENDING', 'PARTIAL'}.contains(row['status']))
        .fold<double>(0, (sum, row) => sum + asDouble(row['amount_ugx']));

    return ListView(
      padding: EdgeInsets.all(padding),
      children: [
        SectionHeader(
          title: app.user?.role == 'FAMILY' ? 'My payments' : 'Payments',
          subtitle: '${all.length} records · ${Fmt.money(outstanding)} pending',
          action: app.canWrite('payments')
              ? FilledButton.icon(
                  onPressed: () async {
                    if (await showPaymentForm(context)) {
                      if (context.mounted) {
                        showAppMessage(
                          context,
                          'Payment saved locally. The receipt number is '
                          'assigned by the server after syncing.',
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Record payment'),
                )
              : null,
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 640
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: width,
                  child: KpiCard(
                    title: 'Collected',
                    value: Fmt.money(paid, compact: true),
                    subtitle: '${all.where((row) => row['status'] == 'PAID').length} payments marked paid',
                    icon: Icons.account_balance_wallet_outlined,
                    tone: PillTone.success,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: KpiCard(
                    title: 'Outstanding',
                    value: Fmt.money(outstanding, compact: true),
                    subtitle:
                        '${all.where((row) => const {'PENDING', 'PARTIAL'}.contains(row['status'])).length} awaiting settlement',
                    icon: Icons.pending_actions_outlined,
                    tone: PillTone.warning,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        SearchBarField(
          hint: 'Search receipt, client, reference…',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in const {
              'ALL': 'All',
              'PAID': 'Paid',
              'PARTIAL': 'Partial',
              'PENDING': 'Pending',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _filter == entry.key,
                onSelected: (_) => setState(() => _filter = entry.key),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          const EmptyState(
            icon: Icons.payments_outlined,
            title: 'No payments in this view',
            message: 'Payments recorded offline are stored on this device and '
                'uploaded when a connection returns.',
          )
        else
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RecordCard(
                title: '${row['receipt_reference'] ?? 'Payment'} · '
                    '${row['client_name'] ?? 'Client'}',
                subtitle: [
                  Fmt.labelize(row['payment_method']),
                  if ('${row['placement_number'] ?? ''}'.isNotEmpty)
                    '${row['placement_number']}',
                  if ('${row['booking_number'] ?? ''}'.isNotEmpty)
                    '${row['booking_number']}',
                  if ('${row['reference'] ?? ''}'.isNotEmpty)
                    'Ref ${row['reference']}',
                ].where((part) => part.isNotEmpty).join(' · '),
                leading: AvatarCircle(
                  name: '${row['client_name'] ?? 'PA'}',
                  color: const Color(0xFF00695C),
                ),
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Fmt.money(row['amount_ugx']),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 5),
                    StatusPill(label: '${row['status'] ?? ''}'),
                  ],
                ),
                footer: Row(
                  children: [
                    Expanded(
                      child: Text(
                        [
                          'Recorded ${Fmt.dateTime(row['created_at'])}',
                          if ('${row['recorded_by_name'] ?? ''}'.isNotEmpty)
                            'by ${row['recorded_by_name']}',
                        ].join(' '),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    if (app.database
                            ?.find('payment', '${row['id']}')?.dirty ==
                        true)
                      const StatusPill(
                        label: 'PENDING SYNC',
                        tone: PillTone.warning,
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
