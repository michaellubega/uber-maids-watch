import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../state/app_state.dart';
import 'forms/service_form.dart';
import 'widgets.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final padding = pagePadding(context);
    final rows = app.rows('service').where((row) {
      if (_query.isEmpty) return true;
      return [
        row['name'],
        row['category'],
        row['pricing_type'],
        row['description'],
      ].join(' ').toLowerCase().contains(_query.toLowerCase());
    }).toList()
      ..sort((a, b) => '${a['name']}'
          .toLowerCase()
          .compareTo('${b['name']}'.toLowerCase()));

    final active = rows.where((row) => row['active'] != false).length;

    return ListView(
      padding: EdgeInsets.all(padding),
      children: [
        SectionHeader(
          title: 'Service catalogue',
          subtitle: '${app.count('service')} services · $active active. '
              'Prices remain pending owner confirmation.',
          action: app.canWrite('services')
              ? FilledButton.icon(
                  onPressed: () async {
                    if (await showServiceForm(context)) {
                      if (context.mounted) {
                        showAppMessage(context, 'Service saved locally.');
                      }
                    }
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add service'),
                )
              : null,
        ),
        const SizedBox(height: 14),
        SearchBarField(
          hint: 'Search service, category or pricing…',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 14),
        if (rows.isEmpty)
          const EmptyState(
            icon: Icons.cleaning_services_outlined,
            title: 'No services yet',
            message: 'Add the services the agency offers so bookings can refer '
                'to them. Keep pricing in ranges until the owner confirms the '
                'final amounts.',
          )
        else
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RecordCard(
                title: '${row['name'] ?? 'Service'}',
                subtitle: [
                  Fmt.labelize(row['category']),
                  Fmt.labelize(row['pricing_type']),
                  if ('${row['description'] ?? ''}'.isNotEmpty)
                    Fmt.truncate('${row['description']}', 90),
                ].where((part) => part.isNotEmpty).join(' · '),
                leading: AvatarCircle(
                  name: '${row['name'] ?? '?'}',
                  color: const Color(0xFF2E7D6B),
                ),
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusPill(
                      label: row['active'] == false ? 'INACTIVE' : 'ACTIVE',
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _price(row),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
                footer: Row(
                  children: [
                    if (row['public_visibility'] == true)
                      const Padding(
                        padding: EdgeInsets.only(right: 10),
                        child: Icon(Icons.public, size: 14, color: Colors.black45),
                      ),
                    Expanded(
                      child: Text(
                        '${row['requirements'] ?? ''}'.isEmpty
                            ? 'No requirements recorded'
                            : '${row['requirements']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    if (app.canDelete('services'))
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Remove service',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => _delete(context, app, row),
                      ),
                    if (app.canWrite('services'))
                      TextButton(
                        onPressed: () => showServiceForm(context, existing: row),
                        child: const Text('Edit'),
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  static String _price(Map<String, dynamic> row) {
    final min = row['price_min_ugx'];
    final max = row['price_max_ugx'];
    if (min == null && max == null) return 'Price on quote';
    if (min != null && max != null) {
      return '${Fmt.money(min, compact: true)} – ${Fmt.money(max, compact: true)}';
    }
    return Fmt.money(min ?? max, compact: true);
  }

  Future<void> _delete(
    BuildContext context,
    AppState app,
    Map<String, dynamic> row,
  ) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove service?',
      message:
          'The service will be hidden from new bookings. Existing bookings '
          'keep their reference to it.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed) return;
    await app.deleteRecord('service', '${row['id']}');
    if (context.mounted) {
      showAppMessage(context, 'Service removed. The change will sync.');
    }
  }
}
