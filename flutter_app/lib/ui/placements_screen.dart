import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../state/app_state.dart';
import 'forms/followup_form.dart';
import 'forms/placement_form.dart';
import 'forms/replacement_form.dart';
import 'widgets.dart';

class PlacementsScreen extends StatefulWidget {
  const PlacementsScreen({super.key});

  @override
  State<PlacementsScreen> createState() => _PlacementsScreenState();
}

class _PlacementsScreenState extends State<PlacementsScreen> {
  String _query = '';
  String _filter = 'ACTIVE';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final padding = pagePadding(context);
    final all = app.rows('placement');
    final rows = all.where((row) {
      if (_filter == 'ACTIVE' && row['status'] != 'ACTIVE') return false;
      if (_filter == 'GUARANTEE' &&
          Fmt.guaranteeStatus(row) != 'IN_GUARANTEE') {
        return false;
      }
      if (_filter == 'ENDED' &&
          !const {'COMPLETED', 'TERMINATED'}.contains(row['status'])) {
        return false;
      }
      if (_query.isEmpty) return true;
      return [
        row['placement_number'],
        row['client_name'],
        row['worker_name'],
        row['terms'],
        row['status'],
      ].join(' ').toLowerCase().contains(_query.toLowerCase());
    }).toList()
      ..sort((a, b) => '${b['start_date'] ?? ''}'
          .compareTo('${a['start_date'] ?? ''}'));

    return ListView(
      padding: EdgeInsets.all(padding),
      children: [
        SectionHeader(
          title: 'Placements',
          subtitle: '${all.where((row) => row['status'] == 'ACTIVE').length} active · '
              '${all.where((row) => Fmt.guaranteeStatus(row) == 'IN_GUARANTEE').length} '
              'inside the guarantee window',
          action: app.canWrite('placements')
              ? FilledButton.icon(
                  onPressed: () async {
                    if (!app.canReachServer) {
                      showAppMessage(
                        context,
                        'Placing a worker needs a connection: the server checks '
                        'availability and verification first.',
                        error: true,
                      );
                      return;
                    }
                    if (await showPlacementForm(context)) {
                      if (context.mounted) {
                        showAppMessage(context, 'Placement created.');
                      }
                    }
                  },
                  icon: const Icon(Icons.handshake_outlined, size: 18),
                  label: const Text('New placement'),
                )
              : null,
        ),
        const SizedBox(height: 14),
        SearchBarField(
          hint: 'Search placement number, client, worker…',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in const {
              'ACTIVE': 'Active',
              'GUARANTEE': 'In guarantee',
              'ENDED': 'Ended',
              'ALL': 'All',
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
            icon: Icons.handshake_outlined,
            title: 'No placements in this view',
            message: 'A placement is created when a verified worker starts with '
                'a family. It carries the guarantee window used for replacement '
                'decisions.',
          )
        else
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RecordCard(
                title: '${row['placement_number'] ?? 'Placement'} · '
                    '${row['worker_name'] ?? 'Worker'}',
                subtitle: [
                  '${row['client_name'] ?? 'Client'}',
                  'Started ${Fmt.date(row['start_date'])}',
                  if ('${row['terms'] ?? ''}'.isNotEmpty)
                    Fmt.truncate('${row['terms']}', 60),
                ].where((part) => part.isNotEmpty).join(' · '),
                leading: AvatarCircle(
                  name: '${row['worker_name'] ?? '?'}',
                  color: const Color(0xFF2E7D32),
                ),
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusPill(label: '${row['status'] ?? ''}'),
                    const SizedBox(height: 5),
                    StatusPill(
                      label: Fmt.guaranteeStatus(row),
                      tone: toneFor(Fmt.guaranteeStatus(row)),
                    ),
                  ],
                ),
                footer: Row(
                  children: [
                    Icon(
                      Icons.event_available_outlined,
                      size: 14,
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Guarantee ${row['guarantee_days'] ?? 0} days · '
                        'ends ${Fmt.date(row['guarantee_end_date'])}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    if (app.canWrite('followups'))
                      TextButton(
                        onPressed: () => showFollowUpForm(context),
                        child: const Text('Follow-up'),
                      ),
                  ],
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _PlacementDetail(placementId: '${row['id']}'),
                ),
              ),
            ),
      ],
    );
  }
}

class _PlacementDetail extends StatelessWidget {
  const _PlacementDetail({required this.placementId});

  final String placementId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final placement = app.row('placement', placementId);
    if (placement == null) {
      return AlertDialog(
        title: const Text('Placement'),
        content: const Text('This record is no longer in the local cache.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }
    final guarantee = Fmt.guaranteeStatus(placement);
    final followUps = app
        .rows('follow_up')
        .where((row) => row['placement'] == placementId)
        .toList()
      ..sort((a, b) => '${a['due_date']}'.compareTo('${b['due_date']}'));
    final openFollowUps = followUps.where(Fmt.isOpenFollowUp).toList();

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${placement['placement_number'] ?? 'Placement'}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '${placement['worker_name'] ?? ''} with '
                  '${placement['client_name'] ?? ''}',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
          StatusPill(label: guarantee, tone: toneFor(guarantee)),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 0,
                children: [
                  _cell('Status', Fmt.labelize(placement['status'])),
                  _cell('Start date', Fmt.date(placement['start_date'])),
                  _cell('Guarantee days', '${placement['guarantee_days'] ?? 0}'),
                  _cell(
                    'Guarantee ends',
                    Fmt.date(placement['guarantee_end_date']),
                  ),
                  _cell('Worker number',
                      '${placement['worker_number'] ?? '—'}'),
                  _cell('Client number',
                      '${placement['client_number'] ?? '—'}'),
                  _cell('Responsible', '${placement['responsible_staff_name'] ?? '—'}'),
                  _cell('Booking', '${placement['booking_number'] ?? '—'}'),
                ],
              ),
              if ('${placement['terms'] ?? ''}'.isNotEmpty)
                LabeledValue(label: 'Terms', value: '${placement['terms']}'),
              if ('${placement['notes'] ?? ''}'.isNotEmpty)
                LabeledValue(label: 'Notes', value: '${placement['notes']}'),
              const SizedBox(height: 4),
              Text(
                'Follow-ups',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 6),
              if (followUps.isEmpty)
                Text(
                  'No follow-ups scheduled.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                )
              else
                for (final followUp in followUps.take(6))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: [
                        Icon(
                          Fmt.isOpenFollowUp(followUp)
                              ? Icons.schedule
                              : Icons.check_circle_outline,
                          size: 15,
                          color: Fmt.isOverdue(followUp)
                              ? const Color(0xFF9B1C1C)
                              : Colors.black45,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            '${Fmt.date(followUp['due_date'])} · '
                            '${Fmt.labelize(followUp['outcome'], fallback: 'Open')}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        StatusPill(
                          label: Fmt.isOverdue(followUp)
                              ? 'OVERDUE'
                              : Fmt.isOpenFollowUp(followUp)
                                  ? 'OPEN'
                                  : 'COMPLETED',
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: 8),
              Text(
                'The guarantee window is a working default (14 days) and is '
                'pending owner confirmation. Replacement eligibility is always '
                'decided by a manager and recorded.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Colors.black.withValues(alpha: 0.5),
                ),
              ),
              if (openFollowUps.isNotEmpty)
                Text(
                  '${openFollowUps.length} follow-up'
                  '${openFollowUps.length == 1 ? '' : 's'} still open.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.black.withValues(alpha: 0.55),
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
        if (app.canWrite('followups'))
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              showFollowUpForm(context);
            },
            icon: const Icon(Icons.add_task, size: 18),
            label: const Text('Follow-up'),
          ),
        if (app.canWrite('replacements') &&
            const {'ACTIVE', 'PAUSED', 'REPLACEMENT_REQUESTED'}
                .contains(placement['status']))
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              showReplacementForm(context);
            },
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Replacement'),
          ),
      ],
    );
  }

  static Widget _cell(String label, String value) => SizedBox(
        width: 280,
        child: LabeledValue(label: label, value: value.isEmpty ? '—' : value),
      );
}
