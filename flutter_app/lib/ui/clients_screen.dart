import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../state/app_state.dart';
import 'forms/client_form.dart';
import 'widgets.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final padding = pagePadding(context);
    final rows = app.rows('client').where((row) {
      if (_query.isEmpty) return true;
      final haystack = [
        row['full_name'],
        row['client_number'],
        row['phone'],
        row['area'],
        row['email'],
      ].join(' ').toLowerCase();
      return haystack.contains(_query.toLowerCase());
    }).toList()
      ..sort((a, b) => '${a['full_name']}'
          .toLowerCase()
          .compareTo('${b['full_name']}'.toLowerCase()));

    return ListView(
      padding: EdgeInsets.all(padding),
      children: [
        SectionHeader(
          title: 'Clients',
          subtitle: '${app.count('client')} households cached on this device.',
          action: app.canWrite('clients')
              ? FilledButton.icon(
                  onPressed: () async {
                    if (await showClientForm(context)) {
                      if (context.mounted) {
                        showAppMessage(context, 'Client saved locally.');
                      }
                    }
                  },
                  icon: const Icon(Icons.add_home_outlined, size: 18),
                  label: const Text('Add client'),
                )
              : null,
        ),
        const SizedBox(height: 14),
        SearchBarField(
          hint: 'Search name, number, phone or area…',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          EmptyState(
            icon: Icons.home_work_outlined,
            title: _query.isEmpty ? 'No clients cached' : 'No matches',
            message: _query.isEmpty
                ? 'Clients appear here after they are added or synchronised.'
                : 'Try a different name, phone number or area.',
          )
        else
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RecordCard(
                title: '${row['full_name'] ?? 'Client'}',
                subtitle: [
                  '${row['client_number'] ?? ''}',
                  if ('${row['phone'] ?? ''}'.isNotEmpty) '${row['phone']}',
                  if ('${row['area'] ?? ''}'.isNotEmpty) '${row['area']}',
                ].where((part) => part.isNotEmpty).join(' · '),
                leading: AvatarCircle(name: '${row['full_name'] ?? '?'}'),
                trailing: StatusPill(label: '${row['status'] ?? ''}'),
                footer: Row(
                  children: [
                    _Counter(
                      icon: Icons.event_note_outlined,
                      value: app
                          .rows('booking')
                          .where((booking) => booking['client'] == row['id'])
                          .length,
                      label: 'bookings',
                    ),
                    const SizedBox(width: 16),
                    _Counter(
                      icon: Icons.handshake_outlined,
                      value: app
                          .rows('placement')
                          .where((placement) => placement['client'] == row['id'])
                          .length,
                      label: 'placements',
                    ),
                    const Spacer(),
                    Text(
                      Fmt.labelize(row['preferred_contact']),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                onTap: () => _showClient(context, '${row['id']}'),
              ),
            ),
      ],
    );
  }

  Future<void> _showClient(BuildContext context, String id) {
    return showDialog<void>(
      context: context,
      builder: (_) => _ClientDetail(clientId: id),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.icon, required this.value, required this.label});

  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.black45),
        const SizedBox(width: 4),
        Text(
          '$value $label',
          style: TextStyle(
            fontSize: 11.5,
            color: Colors.black.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _ClientDetail extends StatelessWidget {
  const _ClientDetail({required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final client = app.row('client', clientId);
    if (client == null) {
      return AlertDialog(
        title: const Text('Client'),
        content: const Text('This record is no longer in the local cache.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }
    final bookings = app
        .rows('booking')
        .where((row) => row['client'] == clientId)
        .toList();
    final placements = app
        .rows('placement')
        .where((row) => row['client'] == clientId)
        .toList();

    return AlertDialog(
      title: Row(
        children: [
          AvatarCircle(name: '${client['full_name'] ?? '?'}', size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${client['full_name'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${client['client_number'] ?? ''}',
                    style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
          StatusPill(label: '${client['status'] ?? ''}'),
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
                  SizedBox(
                    width: 270,
                    child: LabeledValue(
                      label: 'Phone',
                      value: '${client['phone'] ?? '—'}',
                    ),
                  ),
                  SizedBox(
                    width: 270,
                    child: LabeledValue(
                      label: 'Email',
                      value: '${client['email'] ?? ''}'.isEmpty
                          ? '—'
                          : '${client['email']}',
                    ),
                  ),
                  SizedBox(
                    width: 270,
                    child: LabeledValue(
                      label: 'Area',
                      value: '${client['area'] ?? '—'}',
                    ),
                  ),
                  SizedBox(
                    width: 270,
                    child: LabeledValue(
                      label: 'Preferred contact',
                      value: Fmt.labelize(client['preferred_contact'], fallback: '—'),
                    ),
                  ),
                ],
              ),
              if ('${client['notes'] ?? ''}'.isNotEmpty)
                LabeledValue(label: 'Notes', value: '${client['notes']}'),
              const SizedBox(height: 6),
              Text(
                'Activity',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 8),
              if (bookings.isEmpty && placements.isEmpty)
                Text(
                  'No bookings or placements yet.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                ),
              for (final booking in bookings.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.event_note_outlined, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${booking['booking_number']} · '
                          '${Fmt.labelize(booking['status'])}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      Text(
                        Fmt.date(booking['requested_start_date']),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              for (final placement in placements.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.handshake_outlined, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${placement['placement_number']} · '
                          '${placement['worker_name'] ?? ''}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      StatusPill(
                        label: Fmt.guaranteeStatus(placement),
                        tone: toneFor(Fmt.guaranteeStatus(placement)),
                      ),
                    ],
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
        if (app.canWrite('clients'))
          FilledButton.icon(
            onPressed: () => showClientForm(context, existing: client),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
      ],
    );
  }
}
