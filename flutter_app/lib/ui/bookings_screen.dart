import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../state/app_state.dart';
import 'forms/booking_form.dart';
import 'forms/placement_form.dart';
import 'widgets.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  String _query = '';
  String _filter = 'OPEN';

  static const _filters = {
    'OPEN': 'Open',
    'ALL': 'All',
    'NEW': 'New',
    'CONFIRMED': 'Confirmed',
    'CLOSED': 'Closed / converted',
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final padding = pagePadding(context);
    final all = app.rows('booking');
    final rows = all.where((row) {
      final status = '${row['status']}';
      if (_filter == 'OPEN' &&
          const {'CANCELLED', 'CONVERTED', 'CLOSED'}.contains(status)) {
        return false;
      }
      if (_filter == 'CLOSED' &&
          !const {'CANCELLED', 'CONVERTED', 'CLOSED'}.contains(status)) {
        return false;
      }
      if (_filter != 'OPEN' && _filter != 'ALL' && _filter != 'CLOSED' && status != _filter) {
        return false;
      }
      if (_query.isEmpty) return true;
      return [
        row['booking_number'],
        row['client_name'],
        row['service_name'],
        row['location'],
        row['status'],
        row['requirements'],
      ].join(' ').toLowerCase().contains(_query.toLowerCase());
    }).toList()
      ..sort((a, b) => '${b['created_at'] ?? ''}'
          .compareTo('${a['created_at'] ?? ''}'));

    return ListView(
      padding: EdgeInsets.all(padding),
      children: [
        SectionHeader(
          title: app.user?.role == 'FAMILY' ? 'My requests' : 'Bookings',
          subtitle: '${all.length} requests cached · '
              '${all.where((row) => row['status'] == 'NEW').length} new',
          action: app.canWrite('bookings')
              ? FilledButton.icon(
                  onPressed: () async {
                    if (await showBookingForm(context)) {
                      if (context.mounted) {
                        showAppMessage(
                          context,
                          app.user?.role == 'FAMILY'
                              ? 'Request submitted. Customer care will review it.'
                              : 'Booking saved locally.',
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(
                    app.user?.role == 'FAMILY' ? 'Request worker' : 'New booking',
                  ),
                )
              : null,
        ),
        const SizedBox(height: 14),
        SearchBarField(
          hint: 'Search booking number, client, service or area…',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in _filters.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _filter == entry.key,
                onSelected: (_) => setState(() => _filter = entry.key),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          EmptyState(
            icon: Icons.event_note_outlined,
            title: _query.isEmpty ? 'No bookings in this view' : 'No matches',
            message: _query.isEmpty
                ? 'New requests appear here as soon as they are created, even '
                    'while offline.'
                : 'Try a different number, client or service.',
          )
        else
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RecordCard(
                title: '${row['booking_number'] ?? 'Booking'} · '
                    '${row['client_name'] ?? 'Client'}',
                subtitle: [
                  '${row['service_name'] ?? 'Service'}',
                  if ('${row['location'] ?? ''}'.isNotEmpty) '${row['location']}',
                  'Start ${Fmt.date(row['requested_start_date'])}',
                ].where((part) => part.isNotEmpty).join(' · '),
                leading: AvatarCircle(
                  name: '${row['client_name'] ?? '?'}',
                  color: const Color(0xFF1E4F8C),
                ),
                trailing: StatusPill(label: '${row['status'] ?? ''}'),
                footer: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${row['requirements'] ?? ''}'.isEmpty
                            ? 'No requirements recorded'
                            : Fmt.truncate('${row['requirements']}', 100),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    if (row['budget_ugx'] != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        Fmt.money(row['budget_ugx'], compact: true),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ],
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _BookingDetail(bookingId: '${row['id']}'),
                ),
              ),
            ),
      ],
    );
  }
}

class _BookingDetail extends StatelessWidget {
  const _BookingDetail({required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final booking = app.row('booking', bookingId);
    if (booking == null) {
      return AlertDialog(
        title: const Text('Booking'),
        content: const Text('This record is no longer in the local cache.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }
    final status = '${booking['status']}';
    final canConfirm = app.canWrite('bookings') &&
        !const {'CANCELLED', 'CLOSED', 'CONVERTED', 'CONFIRMED'}.contains(status);
    final canPlace = app.canWrite('placements') &&
        const {'CONFIRMED', 'REQUIREMENTS_CONFIRMED'}.contains(status);

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${booking['booking_number'] ?? 'Booking'}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${booking['client_name'] ?? ''}',
                    style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
          StatusPill(label: status),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 0,
                children: [
                  _cell('Service', '${booking['service_name'] ?? '—'}'),
                  _cell('Requested start', Fmt.date(booking['requested_start_date'])),
                  _cell('Location', '${booking['location'] ?? '—'}'),
                  _cell('Schedule', '${booking['schedule'] ?? '—'}'),
                  _cell('Budget', Fmt.money(booking['budget_ugx'])),
                  _cell('Assigned to', '${booking['assigned_staff_name'] ?? '—'}'),
                  _cell('Confirmed', Fmt.dateTime(booking['confirmed_at'])),
                  _cell('Created by', '${booking['created_by_name'] ?? '—'}'),
                ],
              ),
              if ('${booking['requirements'] ?? ''}'.isNotEmpty)
                LabeledValue(
                  label: 'Requirements',
                  value: '${booking['requirements']}',
                ),
              if ('${booking['special_instructions'] ?? ''}'.isNotEmpty)
                LabeledValue(
                  label: 'Special instructions',
                  value: '${booking['special_instructions']}',
                ),
              const SizedBox(height: 4),
              Text(
                'Confirming a booking is an administrator action and needs a '
                'connection. Creating and editing requests works offline.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Colors.black.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (canPlace)
          OutlinedButton.icon(
            onPressed: () async {
              if (!app.canReachServer) {
                showAppMessage(
                  context,
                  'Placements need a connection so the server can check the '
                  'worker is still available.',
                  error: true,
                );
                return;
              }
              Navigator.of(context).pop();
              await showPlacementForm(context);
            },
            icon: const Icon(Icons.handshake_outlined, size: 18),
            label: const Text('Create placement'),
          ),
        if (canConfirm)
          FilledButton.icon(
            onPressed: () => _confirm(context, app, booking),
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Confirm booking'),
          ),
      ],
    );
  }

  static Widget _cell(String label, String value) => SizedBox(
        width: 270,
        child: LabeledValue(label: label, value: value),
      );

  Future<void> _confirm(
    BuildContext context,
    AppState app,
    Map<String, dynamic> booking,
  ) async {
    if (!app.canReachServer) {
      showAppMessage(
        context,
        'Confirming a booking requires a connection to the office server.',
        error: true,
      );
      return;
    }
    final confirmed = await confirmAction(
      context,
      title: 'Confirm booking?',
      message: 'This records the confirmation, timestamps it and writes an '
          'audit entry. The family is told their request is accepted.',
      confirmLabel: 'Confirm',
    );
    if (!confirmed) return;
    try {
      await app.action(
        method: 'POST',
        path: '/bookings/${booking['id']}/confirm/',
        entity: 'booking',
        body: {'assigned_staff_name': app.user?.displayName},
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        showAppMessage(context, 'Booking confirmed.');
      }
    } on ApiException catch (error) {
      if (context.mounted) showAppMessage(context, error.message, error: true);
    }
  }
}

