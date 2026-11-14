import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../state/app_state.dart';
import '../forms/worker_form.dart';
import '../widgets.dart';

Future<void> showWorkerDetail(BuildContext context, String workerId) {
  return showDialog<void>(
    context: context,
    builder: (_) => _WorkerDetail(workerId: workerId),
  );
}

class _WorkerDetail extends StatelessWidget {
  const _WorkerDetail({required this.workerId});

  final String workerId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final worker = app.row('worker', workerId);
    if (worker == null) {
      return AlertDialog(
        title: const Text('Worker'),
        content: const Text('This record is no longer in the local cache.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }
    final name = '${worker['full_name'] ?? 'Worker'}';
    final canVerify = app.canWrite('workers') &&
        !const {'VERIFIED', 'EXCEPTION'}
            .contains('${worker['verification_status']}');

    return AlertDialog(
      title: Row(
        children: [
          AvatarCircle(name: name, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '${worker['worker_number'] ?? ''}',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(label: '${worker['status'] ?? ''}'),
                  StatusPill(
                    label: '${worker['verification_status'] ?? ''}',
                    tone: toneFor(worker['verification_status']),
                  ),
                  if (app.database?.find('worker', workerId)?.dirty == true)
                    const StatusPill(label: 'PENDING SYNC', tone: PillTone.warning),
                ],
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth >= 520
                      ? (constraints.maxWidth - 16) / 2
                      : constraints.maxWidth;
                  Widget cell(String label, String value) => SizedBox(
                        width: width,
                        child: LabeledValue(label: label, value: value),
                      );
                  return Wrap(
                    spacing: 16,
                    runSpacing: 0,
                    children: [
                      cell('Phone', _value(worker['phone'])),
                      cell('Area', _value(worker['area'])),
                      cell('Experience', '${worker['experience_years'] ?? 0} years'),
                      cell('Expected salary', Fmt.money(worker['expected_salary_ugx'])),
                      cell('Skills', _list(worker['skills'])),
                      cell('Languages', _list(worker['languages'])),
                      cell('Service categories', _list(worker['service_categories'])),
                      cell('Date of birth', Fmt.date(worker['date_of_birth'])),
                      cell('ID type', _value(worker['national_id_type'])),
                      cell('ID number', _value(worker['national_id_number'])),
                      cell('Emergency contact', _value(worker['emergency_contact_name'])),
                      cell('Contact phone', _value(worker['emergency_contact_phone'])),
                      cell('Verified by', _value(worker['verified_by_name'])),
                      cell('Verified at', Fmt.dateTime(worker['verified_at'])),
                    ],
                  );
                },
              ),
              if ('${worker['exception_reason'] ?? ''}'.isNotEmpty)
                LabeledValue(
                  label: 'Verification exception',
                  value: '${worker['exception_reason']}',
                ),
              if ('${worker['notes'] ?? ''}'.isNotEmpty)
                LabeledValue(label: 'Internal notes', value: '${worker['notes']}'),
              const SizedBox(height: 6),
              Text(
                'Identity documents are private. Only authorised staff can open '
                'them, and every download is audited.',
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
        if (app.canWrite('workers'))
          TextButton.icon(
            onPressed: () => showWorkerForm(context, existing: worker),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
        if (canVerify)
          FilledButton.icon(
            onPressed: () => _verify(context, app, worker),
            icon: const Icon(Icons.verified_outlined, size: 18),
            label: Text(app.canReachServer ? 'Verify' : 'Verify (online)'),
          ),
        if (app.canWrite('workers'))
          TextButton.icon(
            onPressed: () => _showDocuments(context, app, workerId),
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: const Text('Documents'),
          ),
      ],
    );
  }

  static String _value(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? '—' : text;
  }

  static String _list(dynamic value) {
    if (value is List && value.isNotEmpty) {
      return value.map((item) => '$item').join(', ');
    }
    return '—';
  }

  Future<void> _verify(
    BuildContext context,
    AppState app,
    Map<String, dynamic> worker,
  ) async {
    if (!app.canReachServer) {
      showAppMessage(
        context,
        'Verification is an administrator action. Reconnect to record it.',
        error: true,
      );
      return;
    }
    final checksComplete = ValueNotifier<bool>(true);
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Record verification'),
        content: SizedBox(
          width: 460,
          child: ValueListenableBuilder<bool>(
            valueListenable: checksComplete,
            builder: (context, complete, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('All required checks completed'),
                  subtitle: const Text(
                    'Identity, references and any required training.',
                  ),
                  value: complete,
                  onChanged: (value) => checksComplete.value = value,
                ),
                if (!complete)
                  TextField(
                    controller: reason,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Exception reason *',
                      helperText: 'Explain why this worker is approved outside the checks.',
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'This calls the live server and is written to the audit trail.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!checksComplete.value && reason.text.trim().isEmpty) return;
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('Record verification'),
          ),
        ],
      ),
    );
    final complete = checksComplete.value;
    checksComplete.dispose();
    if (confirmed != true) {
      reason.dispose();
      return;
    }
    final reasonText = reason.text.trim();
    reason.dispose();
    try {
      await app.action(
        method: 'POST',
        path: '/workers/${worker['id']}/verify/',
        entity: 'worker',
        body: complete
            ? {'checks_complete': true}
            : {
                'checks_complete': false,
                'exception_reason': reasonText,
              },
      );
      if (context.mounted) {
        showAppMessage(context, 'Verification recorded.');
      }
    } on ApiException catch (error) {
      if (context.mounted) showAppMessage(context, error.message, error: true);
    }
  }

  Future<void> _showDocuments(
    BuildContext context,
    AppState app,
    String workerId,
  ) async {
    if (!app.canReachServer) {
      showAppMessage(
        context,
        'Documents are stored privately on the server. Reconnect to view them.',
        error: true,
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Verification documents'),
        content: SizedBox(
          width: 480,
          height: 320,
          child: FutureBuilder<Map<String, dynamic>>(
            future: app.api.get(
              '/worker-documents/',
              query: {'worker': workerId},
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    snapshot.error is ApiException
                        ? (snapshot.error as ApiException).message
                        : 'Could not load documents.',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              final results = snapshot.data?['results'];
              final rows = results is List ? results : const <dynamic>[];
              if (rows.isEmpty) {
                return const Center(child: Text('No documents uploaded.'));
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final row = rows[index] is Map
                      ? Map<String, dynamic>.from(rows[index] as Map)
                      : <String, dynamic>{};
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.description_outlined),
                    title: Text('${row['title'] ?? 'Document'}'),
                    subtitle: Text(
                      '${Fmt.labelize(row['document_type'])} · '
                      '${Fmt.date(row['uploaded_at'])}',
                    ),
                    trailing: StatusPill(
                      label: row['verified'] == true ? 'VERIFIED' : 'PENDING',
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
