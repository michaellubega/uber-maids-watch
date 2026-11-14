import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../state/app_state.dart';
import 'form_helpers.dart';

Future<bool> showReplacementForm(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => const _ReplacementForm(),
  );
  return result == true;
}

class _ReplacementForm extends StatefulWidget {
  const _ReplacementForm();

  @override
  State<_ReplacementForm> createState() => _ReplacementFormState();
}

class _ReplacementFormState extends State<_ReplacementForm> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  String? _placementId;
  String? _reportedDate;
  String _category = 'OTHER';
  bool _saving = false;

  static const _categories = [
    'WORKER_LEFT',
    'CONDUCT',
    'SKILLS_MISMATCH',
    'THEFT_ALLEGATION',
    'ATTENDANCE',
    'OTHER',
  ];

  @override
  void initState() {
    super.initState();
    _reportedDate = Fmt.today();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final app = context.read<AppState>();
    final placement = rowById(app.rows('placement'), _placementId);
    if (placement == null) return;
    setState(() => _saving = true);
    await app.createRecord('replacement_case', {
      'placement': _placementId,
      'issue_reported_date': _reportedDate,
      'problem_category': _category,
      'description': _description.text.trim(),
      'placement_number': textOf(placement, 'placement_number'),
      'client_name': textOf(placement, 'client_name'),
      'client_number': textOf(placement, 'client_number'),
      'original_worker_name': textOf(placement, 'worker_name'),
    });
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final placements = app
        .rows('placement')
        .where((row) => const {'ACTIVE', 'PAUSED', 'REPLACEMENT_REQUESTED'}
            .contains(row['status']))
        .toList();
    final family = app.user?.role == 'FAMILY';

    return Form(
      key: _formKey,
      child: FormDialog(
        title: family ? 'Request a replacement' : 'Open replacement case',
        saving: _saving,
        submitLabel: family ? 'Submit request' : 'Open case',
        onSubmit: _save,
        children: [
          SelectField(
            label: 'Placement *',
            value: _placementId,
            options: optionsFromRows(placements, [
              'placement_number',
              'client_name',
              'worker_name',
            ]),
            onChanged: (value) => setState(() => _placementId = value),
            validator: (value) => value == null ? 'Choose a placement' : null,
          ),
          SelectField(
            label: 'Problem',
            value: _category,
            options: [
              for (final category in _categories)
                SelectOption(category, Fmt.labelize(category)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _category = value);
            },
          ),
          DatePickerField(
            label: 'Date reported *',
            value: _reportedDate,
            required: true,
            onChanged: (value) => setState(() => _reportedDate = value),
          ),
          TextFormField(
            controller: _description,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'What happened? *',
              hintText: 'Describe the issue factually. Avoid assumptions.',
            ),
            validator: (value) => (value == null || value.trim().length < 10)
                ? 'Give a short factual description (at least 10 characters)'
                : null,
          ),
          Text(
            'Eligibility is decided by a manager. Guarantee rules are still '
            'pending owner confirmation; the case records the date so the '
            'decision can be reviewed.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: Colors.black.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
