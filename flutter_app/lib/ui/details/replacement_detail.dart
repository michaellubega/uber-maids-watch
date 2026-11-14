import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

Future<void> showReplacementDetail(BuildContext context, String caseId) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ReplacementDetail(caseId: caseId),
  );
}

class _ReplacementDetail extends StatelessWidget {
  const _ReplacementDetail({required this.caseId});

  final String caseId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final row = app.row('replacement_case', caseId);
    if (row == null) {
      return AlertDialog(
        title: const Text('Replacement case'),
        content: const Text('This record is no longer in the local cache.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }

    final status = '${row['status']}';
    final decision = '${row['eligibility_decision']}';
    final isFamily = app.user?.role == 'FAMILY';
    final canReview = app.canWrite('replacements') &&
        !isFamily &&
        const {'OPEN', 'REVIEWING'}.contains(status) &&
        decision == 'PENDING';
    final canAssign = app.canWrite('placements') &&
        !isFamily &&
        decision == 'ELIGIBLE' &&
        const {'APPROVED', 'REVIEWING', 'OPEN'}.contains(status);
    final canResolve = app.canWrite('replacements') &&
        !isFamily &&
        const {'APPROVED', 'ASSIGNED'}.contains(status);

    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${row['case_number'] ?? 'Case'}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '${row['client_name'] ?? ''} · ${row['placement_number'] ?? ''}',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusPill(label: status),
              const SizedBox(height: 5),
              StatusPill(
                label: decision,
                tone: toneFor(decision),
              ),
            ],
          ),
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
                  _cell('Problem', Fmt.labelize(row['problem_category'])),
                  _cell('Reported', Fmt.date(row['issue_reported_date'])),
                  _cell('Original worker',
                      '${row['original_worker_name'] ?? '—'}'),
                  _cell(
                    'Guarantee eligible',
                    row['guarantee_eligible'] == null
                        ? 'Pending review'
                        : row['guarantee_eligible'] == true
                            ? 'Yes'
                            : 'No',
                  ),
                  _cell('Decided by', '${row['approved_by_name'] ?? '—'}'),
                  _cell('Backup worker',
                      '${row['replacement_worker_name'] ?? '—'}'),
                  _cell('Replacement date',
                      Fmt.date(row['replacement_date'])),
                  _cell('Client confirmed',
                      row['client_confirmed'] == true ? 'Yes' : 'No'),
                ],
              ),
              LabeledValue(
                label: 'Description',
                value: '${row['description'] ?? ''}'.isEmpty
                    ? '—'
                    : '${row['description']}',
              ),
              if ('${row['decision_reason'] ?? ''}'.isNotEmpty)
                LabeledValue(
                  label: 'Decision reason',
                  value: '${row['decision_reason']}',
                ),
              if ('${row['resolution_notes'] ?? ''}'.isNotEmpty)
                LabeledValue(
                  label: 'Resolution notes',
                  value: '${row['resolution_notes']}',
                ),
              const SizedBox(height: 4),
              Text(
                'Guarantee rules are pending owner confirmation. A manager '
                'reviews each case; the decision and reason are audited. '
                'Assigning a backup worker needs a connection.',
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
        if (canReview)
          FilledButton.icon(
            onPressed: () => _review(context, app, row),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Review eligibility'),
          ),
        if (canAssign)
          FilledButton.icon(
            onPressed: () => _assign(context, app, row),
            icon: const Icon(Icons.person_search_outlined, size: 18),
            label: const Text('Assign backup'),
          ),
        if (canResolve)
          OutlinedButton.icon(
            onPressed: () => _resolve(context, app, row),
            icon: const Icon(Icons.task_alt, size: 18),
            label: const Text('Mark resolved'),
          ),
      ],
    );
  }

  static Widget _cell(String label, String value) => SizedBox(
        width: 280,
        child: LabeledValue(label: label, value: value.isEmpty ? '—' : value),
      );

  Future<void> _review(
    BuildContext context,
    AppState app,
    Map<String, dynamic> row,
  ) async {
    if (!app.canReachServer) {
      showAppMessage(context,
          'Reviewing eligibility needs a connection to the office server.',
          error: true);
      return;
    }
    final result = await showDialog<_ReviewResult>(
      context: context,
      builder: (_) => const _ReviewDialog(),
    );
    if (result == null) return;
    try {
      await app.action(
        method: 'POST',
        path: '/replacement-cases/${row['id']}/review/',
        entity: 'replacement_case',
        body: result.toBody(),
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        showAppMessage(context, 'Decision recorded.');
      }
    } on ApiException catch (error) {
      if (context.mounted) showAppMessage(context, error.message, error: true);
    }
  }

  Future<void> _assign(
    BuildContext context,
    AppState app,
    Map<String, dynamic> row,
  ) async {
    if (!app.canReachServer) {
      showAppMessage(
        context,
        'Assigning a backup worker needs a connection so the server can verify '
        'availability.',
        error: true,
      );
      return;
    }
    final result = await showDialog<_AssignResult>(
      context: context,
      builder: (_) => _AssignDialog(originalWorkerId: '${row['original_worker']}'),
    );
    if (result == null) return;
    try {
      await app.action(
        method: 'POST',
        path: '/replacement-cases/${row['id']}/assign/',
        entity: 'replacement_case',
        body: result.toBody(),
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        await app.syncNow(silent: true);
        if (context.mounted) {
          showAppMessage(context, 'Backup worker assigned and placement created.');
        }
      }
    } on ApiException catch (error) {
      if (context.mounted) showAppMessage(context, error.message, error: true);
    }
  }

  Future<void> _resolve(
    BuildContext context,
    AppState app,
    Map<String, dynamic> row,
  ) async {
    if (!app.canReachServer) {
      showAppMessage(context, 'Resolving a case needs a connection.', error: true);
      return;
    }
    final notes = TextEditingController(
      text: '${row['resolution_notes'] ?? ''}',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolve case'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: notes,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Resolution notes'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
    final text = notes.text.trim();
    notes.dispose();
    if (confirmed != true) return;
    try {
      await app.action(
        method: 'POST',
        path: '/replacement-cases/${row['id']}/resolve/',
        entity: 'replacement_case',
        body: {'resolution_notes': text, 'client_confirmed': true},
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        showAppMessage(context, 'Case resolved.');
      }
    } on ApiException catch (error) {
      if (context.mounted) showAppMessage(context, error.message, error: true);
    }
  }
}

class _ReviewResult {
  const _ReviewResult({
    required this.decision,
    required this.reason,
    required this.guaranteeConfirmed,
  });

  final String decision;
  final String reason;
  final bool guaranteeConfirmed;

  Map<String, dynamic> toBody() => {
        'decision': decision,
        'decision_reason': reason,
        'guarantee_confirmed': guaranteeConfirmed,
      };
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog();

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _reason = TextEditingController();
  String _decision = 'ELIGIBLE';
  bool _guarantee = true;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Review eligibility'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ELIGIBLE', label: Text('Eligible')),
                  ButtonSegment(
                    value: 'NOT_ELIGIBLE',
                    label: Text('Not eligible'),
                  ),
                ],
                selected: {_decision},
                onSelectionChanged: (value) =>
                    setState(() => _decision = value.first),
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Within the guarantee window'),
                subtitle: const Text(
                  'Confirm the dates manually — the guarantee policy is still '
                  'pending owner confirmation.',
                ),
                value: _guarantee,
                onChanged: (value) => setState(() => _guarantee = value),
              ),
              TextField(
                controller: _reason,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: _decision == 'NOT_ELIGIBLE'
                      ? 'Reason (required) *'
                      : 'Decision notes',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The decision, your name and the reason are written to the '
                'audit trail.',
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
          onPressed: () {
            if (_decision == 'NOT_ELIGIBLE' && _reason.text.trim().isEmpty) {
              return;
            }
            Navigator.of(context).pop(
              _ReviewResult(
                decision: _decision,
                reason: _reason.text.trim(),
                guaranteeConfirmed: _guarantee,
              ),
            );
          },
          child: const Text('Record decision'),
        ),
      ],
    );
  }
}

class _AssignResult {
  const _AssignResult({
    required this.workerId,
    required this.date,
    required this.notes,
  });

  final String workerId;
  final String date;
  final String notes;

  Map<String, dynamic> toBody() => {
        'replacement_worker': workerId,
        'replacement_date': date,
        if (notes.isNotEmpty) 'notes': notes,
      };
}

class _AssignDialog extends StatefulWidget {
  const _AssignDialog({required this.originalWorkerId});

  final String originalWorkerId;

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  final _notes = TextEditingController();
  String? _workerId;
  late String _date;

  @override
  void initState() {
    super.initState();
    _date = Fmt.today();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final workers = app
        .rows('worker')
        .where((row) =>
            '${row['id']}' != widget.originalWorkerId &&
            const {'VERIFIED', 'EXCEPTION'}
                .contains('${row['verification_status']}') &&
            !const {'PLACED', 'SUSPENDED', 'INACTIVE'}
                .contains('${row['status']}'))
        .toList()
      ..sort((a, b) => '${a['full_name']}'
          .toLowerCase()
          .compareTo('${b['full_name']}'.toLowerCase()));

    return AlertDialog(
      title: const Text('Assign backup worker'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _workerId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Verified backup worker *',
                ),
                items: [
                  for (final worker in workers)
                    DropdownMenuItem(
                      value: '${worker['id']}',
                      child: Text(
                        '${worker['full_name']} · '
                        '${worker['area'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _workerId = value),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: now,
                    firstDate: now.subtract(const Duration(days: 30)),
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() {
                      _date = '${picked.year.toString().padLeft(4, '0')}-'
                          '${picked.month.toString().padLeft(2, '0')}-'
                          '${picked.day.toString().padLeft(2, '0')}';
                    });
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Replacement start date',
                    suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                  ),
                  child: Text(Fmt.date(_date)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const SizedBox(height: 10),
              Text(
                workers.isEmpty
                    ? 'No other verified, available workers are cached. Sync '
                        'after registering or verifying a backup worker.'
                    : 'Only verified workers who are not already placed are '
                        'listed. The server re-checks this before assigning.',
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
          onPressed: _workerId == null
              ? null
              : () => Navigator.of(context).pop(
                    _AssignResult(
                      workerId: _workerId!,
                      date: _date,
                      notes: _notes.text.trim(),
                    ),
                  ),
          child: const Text('Assign'),
        ),
      ],
    );
  }
}
