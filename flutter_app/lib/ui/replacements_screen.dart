import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../state/app_state.dart';
import 'details/replacement_detail.dart';
import 'forms/replacement_form.dart';
import 'widgets.dart';

class ReplacementsScreen extends StatefulWidget {
  const ReplacementsScreen({super.key});

  @override
  State<ReplacementsScreen> createState() => _ReplacementsScreenState();
}

class _ReplacementsScreenState extends State<ReplacementsScreen> {
  String _filter = 'OPEN';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final padding = pagePadding(context);
    final all = app.rows('replacement_case');
    final rows = all.where((row) {
      final status = '${row['status']}';
      if (_filter == 'OPEN') {
        return const {'OPEN', 'REVIEWING', 'APPROVED'}.contains(status);
      }
      if (_filter == 'RESOLVED') {
        return const {'RESOLVED', 'REJECTED'}.contains(status);
      }
      return true;
    }).toList()
      ..sort((a, b) => '${b['created_at'] ?? ''}'
          .compareTo('${a['created_at'] ?? ''}'));

    return ListView(
      padding: EdgeInsets.all(padding),
      children: [
        SectionHeader(
          title: app.user?.role == 'FAMILY' ? 'Replacement requests' : 'Replacements',
          subtitle: '${all.where((row) => const {'OPEN', 'REVIEWING'}.contains(row['status'])).length} '
              'awaiting a decision · ${all.length} total',
          action: app.canWrite('replacements')
              ? FilledButton.icon(
                  onPressed: () async {
                    if (await showReplacementForm(context)) {
                      if (context.mounted) {
                        showAppMessage(
                          context,
                          'Replacement case opened. A manager will review '
                          'eligibility.',
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: Text(
                    app.user?.role == 'FAMILY' ? 'Request replacement' : 'Open case',
                  ),
                )
              : null,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in const {
              'OPEN': 'Open',
              'RESOLVED': 'Closed',
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
            icon: Icons.swap_horiz_outlined,
            title: 'No replacement cases',
            message: 'Cases open when a family reports a problem with a '
                'placement. Eligibility is decided by a manager and recorded '
                'with a reason.',
          )
        else
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RecordCard(
                title: '${row['case_number'] ?? 'Case'} · '
                    '${Fmt.labelize(row['problem_category'])}',
                subtitle: [
                  '${row['client_name'] ?? 'Client'}',
                  '${row['placement_number'] ?? ''}',
                  'Reported ${Fmt.date(row['issue_reported_date'])}',
                ].where((part) => part.isNotEmpty).join(' · '),
                leading: AvatarCircle(
                  name: '${row['client_name'] ?? 'RC'}',
                  color: const Color(0xFF8E24AA),
                ),
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusPill(label: '${row['status'] ?? ''}'),
                    const SizedBox(height: 5),
                    StatusPill(
                      label: '${row['eligibility_decision'] ?? 'PENDING'}',
                      tone: toneFor(row['eligibility_decision']),
                    ),
                  ],
                ),
                footer: Row(
                  children: [
                    Expanded(
                      child: Text(
                        Fmt.truncate('${row['description'] ?? ''}', 110),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    if (row['replacement_worker_name'] != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        'Backup: ${row['replacement_worker_name']}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
                onTap: () => showReplacementDetail(context, '${row['id']}'),
              ),
            ),
      ],
    );
  }
}
