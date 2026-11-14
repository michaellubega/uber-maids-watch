import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../state/app_state.dart';
import 'details/worker_detail.dart';
import 'forms/worker_form.dart';
import 'widgets.dart';

class WorkersScreen extends StatefulWidget {
  const WorkersScreen({super.key});

  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final padding = pagePadding(context);
    final rows = app.rows('worker').where((row) {
      if (_query.isEmpty) return true;
      final haystack = [
        row['full_name'],
        row['worker_number'],
        row['phone'],
        row['area'],
        row['status'],
        row['verification_status'],
        if (row['skills'] is List) ...(row['skills'] as List),
        if (row['languages'] is List) ...(row['languages'] as List),
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
          title: app.user?.role == 'MAID' ? 'My profile' : 'Workers',
          subtitle: app.user?.role == 'MAID'
              ? 'Your registration and verification status.'
              : '${app.count('worker')} registered · '
                  '${app.count('worker', where: (row) => row['status'] == 'AVAILABLE')} available',
          action: app.canWrite('workers')
              ? FilledButton.icon(
                  onPressed: () async {
                    if (await showWorkerForm(context)) {
                      if (context.mounted) {
                        showAppMessage(context, 'Worker saved locally.');
                      }
                    }
                  },
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('Register'),
                )
              : null,
        ),
        const SizedBox(height: 14),
        SearchBarField(
          hint: 'Search name, number, area, skill…',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          EmptyState(
            icon: Icons.badge_outlined,
            title: _query.isEmpty ? 'No workers cached' : 'No matches',
            message: _query.isEmpty
                ? 'Register a worker while online or offline. Records sync when a connection returns.'
                : 'Try a different name, number or skill.',
          )
        else
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RecordCard(
                title: '${row['full_name'] ?? 'Worker'}',
                subtitle: [
                  '${row['worker_number'] ?? ''}',
                  if ('${row['area'] ?? ''}'.isNotEmpty) '${row['area']}',
                  if ('${row['phone'] ?? ''}'.isNotEmpty) '${row['phone']}',
                ].where((part) => part.isNotEmpty).join(' · '),
                leading: AvatarCircle(name: '${row['full_name'] ?? '?'}'),
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusPill(label: '${row['status'] ?? ''}'),
                    const SizedBox(height: 5),
                    StatusPill(label: '${row['verification_status'] ?? ''}'),
                  ],
                ),
                footer: _WorkerFooter(row: row),
                onTap: () => showWorkerDetail(context, '${row['id']}'),
              ),
            ),
      ],
    );
  }
}

class _WorkerFooter extends StatelessWidget {
  const _WorkerFooter({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final skills = row['skills'];
    final label = skills is List && skills.isNotEmpty
        ? skills.take(4).join(' · ')
        : 'No skills recorded';
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (row['experience_years'] != null)
          Text(
            '${row['experience_years']} yrs',
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ),
        if (row['expected_salary_ugx'] != null) ...[
          const SizedBox(width: 12),
          Text(
            Fmt.money(row['expected_salary_ugx'], compact: true),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Colors.black.withValues(alpha: 0.65),
            ),
          ),
        ],
      ],
    );
  }
}
