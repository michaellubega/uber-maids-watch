import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../state/app_state.dart';
import 'forms/followup_form.dart';
import 'widgets.dart';

class FollowUpsScreen extends StatefulWidget {
  const FollowUpsScreen({super.key});

  @override
  State<FollowUpsScreen> createState() => _FollowUpsScreenState();
}

class _FollowUpsScreenState extends State<FollowUpsScreen> {
  String _filter = 'DUE';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final padding = pagePadding(context);
    final all = app.rows('follow_up');
    final open = all.where(Fmt.isOpenFollowUp).toList();
    final rows = all.where((row) {
      switch (_filter) {
        case 'DUE':
          return Fmt.isDueToday(row) || Fmt.isOverdue(row);
        case 'OPEN':
          return Fmt.isOpenFollowUp(row);
        case 'COMPLETED':
          return !Fmt.isOpenFollowUp(row);
        default:
          return true;
      }
    }).toList()
      ..sort((a, b) => '${a['due_date']}'.compareTo('${b['due_date']}'));

    final overdue = all.where(Fmt.isOverdue).length;

    return ListView(
      padding: EdgeInsets.all(padding),
      children: [
        SectionHeader(
          title: 'Follow-ups',
          subtitle: '$overdue overdue · ${open.length} open · '
              '${all.length - open.length} completed',
          action: app.canWrite('followups')
              ? FilledButton.icon(
                  onPressed: () async {
                    if (await showFollowUpForm(context)) {
                      if (context.mounted) {
                        showAppMessage(context, 'Follow-up scheduled locally.');
                      }
                    }
                  },
                  icon: const Icon(Icons.add_task, size: 18),
                  label: const Text('Schedule'),
                )
              : null,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in const {
              'DUE': 'Due & overdue',
              'OPEN': 'All open',
              'COMPLETED': 'Completed',
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
          EmptyState(
            icon: Icons.support_agent_outlined,
            title: 'Nothing here',
            message: _filter == 'DUE'
                ? 'No follow-ups are due today or overdue in the cached data.'
                : 'Follow-ups appear here once they are scheduled against a '
                    'placement.',
          )
        else
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RecordCard(
                title: '${Fmt.date(row['due_date'])} · '
                    '${row['client_name'] ?? 'Client'}',
                subtitle: [
                  '${row['placement_number'] ?? ''}',
                  '${row['worker_name'] ?? ''}',
                  Fmt.labelize(row['contact_method']),
                ].where((part) => part.isNotEmpty).join(' · '),
                leading: AvatarCircle(
                  name: '${row['client_name'] ?? 'FU'}',
                  color: Fmt.isOverdue(row)
                      ? const Color(0xFF9B1C1C)
                      : const Color(0xFF079DA5),
                ),
                trailing: StatusPill(
                  label: Fmt.isOverdue(row)
                      ? 'OVERDUE'
                      : Fmt.isOpenFollowUp(row)
                          ? 'OPEN'
                          : Fmt.labelize(row['outcome'], fallback: 'COMPLETED'),
                ),
                footer: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${row['notes'] ?? ''}'.isEmpty
                            ? Fmt.labelize(row['staff_name'], fallback: 'Unassigned')
                            : Fmt.truncate('${row['notes']}', 100),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    if (Fmt.isOpenFollowUp(row) && app.canWrite('followups'))
                      TextButton(
                        onPressed: () => _complete(context, app, row),
                        child: const Text('Complete'),
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _complete(
    BuildContext context,
    AppState app,
    Map<String, dynamic> followUp,
  ) async {
    if (!app.canReachServer) {
      showAppMessage(
        context,
        'Completing a follow-up is an administrator action. Reconnect to record '
        'the outcome.',
        error: true,
      );
      return;
    }
    final result = await showDialog<_CompletionResult>(
      context: context,
      builder: (_) => _CompleteFollowUpDialog(followUp: followUp),
    );
    if (result == null) return;
    try {
      await app.action(
        method: 'POST',
        path: '/follow-ups/${followUp['id']}/complete/',
        entity: 'follow_up',
        body: result.toBody(),
      );
      if (context.mounted) {
        await app.syncNow(silent: true);
        if (context.mounted) {
          showAppMessage(context, 'Follow-up completed.');
        }
      }
    } on ApiException catch (error) {
      if (context.mounted) showAppMessage(context, error.message, error: true);
    }
  }
}

class _CompletionResult {
  const _CompletionResult({
    required this.outcome,
    required this.contactMethod,
    required this.satisfaction,
    required this.notes,
    required this.nextDate,
  });

  final String outcome;
  final String contactMethod;
  final int? satisfaction;
  final String notes;
  final String? nextDate;

  Map<String, dynamic> toBody() => {
        'outcome': outcome,
        'contact_method': contactMethod,
        'notes': notes,
        if (satisfaction != null) 'satisfaction': satisfaction,
        if (nextDate != null && nextDate!.isNotEmpty)
          'next_follow_up_date': nextDate,
      };
}

class _CompleteFollowUpDialog extends StatefulWidget {
  const _CompleteFollowUpDialog({required this.followUp});

  final Map<String, dynamic> followUp;

  @override
  State<_CompleteFollowUpDialog> createState() =>
      _CompleteFollowUpDialogState();
}

class _CompleteFollowUpDialogState extends State<_CompleteFollowUpDialog> {
  late final TextEditingController _notes;
  String _outcome = 'CLIENT_SATISFIED';
  String _contact = 'PHONE';
  int _satisfaction = 4;
  String? _nextDate;

  static const _outcomes = [
    'CLIENT_SATISFIED',
    'WORKER_SETTLED',
    'CLIENT_REQUESTED_SUPPORT',
    'WORKER_UNAVAILABLE',
    'CONDUCT_CONCERN',
    'REPLACEMENT_REQUESTED',
    'CLIENT_UNREACHABLE',
    'OTHER',
  ];

  @override
  void initState() {
    super.initState();
    _notes = TextEditingController(text: '${widget.followUp['notes'] ?? ''}');
    _contact = '${widget.followUp['contact_method'] ?? 'PHONE'}';
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Complete follow-up'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _outcome,
                decoration: const InputDecoration(labelText: 'Outcome'),
                items: [
                  for (final outcome in _outcomes)
                    DropdownMenuItem(
                      value: outcome,
                      child: Text(Fmt.labelize(outcome)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _outcome = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _contact,
                decoration: const InputDecoration(labelText: 'Contact method'),
                items: const [
                  DropdownMenuItem(value: 'PHONE', child: Text('Phone')),
                  DropdownMenuItem(value: 'WHATSAPP', child: Text('WhatsApp')),
                  DropdownMenuItem(value: 'SMS', child: Text('SMS')),
                  DropdownMenuItem(value: 'VISIT', child: Text('Visit')),
                  DropdownMenuItem(value: 'EMAIL', child: Text('Email')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _contact = value);
                },
              ),
              const SizedBox(height: 14),
              Text(
                'Satisfaction',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
              ),
              Slider(
                value: _satisfaction.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: '$_satisfaction / 5',
                onChanged: (value) =>
                    setState(() => _satisfaction = value.round()),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'What did the family and worker say?',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: now.add(const Duration(days: 7)),
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() {
                      _nextDate = '${picked.year.toString().padLeft(4, '0')}-'
                          '${picked.month.toString().padLeft(2, '0')}-'
                          '${picked.day.toString().padLeft(2, '0')}';
                    });
                  }
                },
                icon: const Icon(Icons.event_repeat, size: 18),
                label: Text(
                  _nextDate == null
                      ? 'Schedule next follow-up'
                      : 'Next follow-up ${Fmt.date(_nextDate)}',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'The server timestamps this completion and creates the next '
                'follow-up when a date is chosen. Every change is audited.',
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _CompletionResult(
              outcome: _outcome,
              contactMethod: _contact,
              satisfaction: _satisfaction,
              notes: _notes.text.trim(),
              nextDate: _nextDate,
            ),
          ),
          child: const Text('Complete'),
        ),
      ],
    );
  }
}
