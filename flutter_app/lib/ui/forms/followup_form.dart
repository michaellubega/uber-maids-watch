import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../state/app_state.dart';
import 'form_helpers.dart';

Future<bool> showFollowUpForm(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => const _FollowUpForm(),
  );
  return result == true;
}

class _FollowUpForm extends StatefulWidget {
  const _FollowUpForm();

  @override
  State<_FollowUpForm> createState() => _FollowUpFormState();
}

class _FollowUpFormState extends State<_FollowUpForm> {
  final _formKey = GlobalKey<FormState>();
  final _notes = TextEditingController();
  String? _placementId;
  String? _dueDate;
  String _method = 'PHONE';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dueDate = Fmt.today();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final app = context.read<AppState>();
    final placement = rowById(app.rows('placement'), _placementId);
    if (placement == null) return;
    setState(() => _saving = true);
    await app.createRecord('follow_up', {
      'placement': _placementId,
      'due_date': _dueDate,
      'contact_method': _method,
      'notes': _notes.text.trim(),
      'placement_number': textOf(placement, 'placement_number'),
      'client_name': textOf(placement, 'client_name'),
      'worker_name': textOf(placement, 'worker_name'),
    });
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final placements = app
        .rows('placement')
        .where((row) => row['status'] == 'ACTIVE')
        .toList();

    return Form(
      key: _formKey,
      child: FormDialog(
        title: 'Schedule follow-up',
        saving: _saving,
        submitLabel: 'Schedule',
        onSubmit: _save,
        children: [
          SelectField(
            label: 'Active placement *',
            value: _placementId,
            options: optionsFromRows(placements, [
              'placement_number',
              'client_name',
              'worker_name',
            ]),
            onChanged: (value) => setState(() => _placementId = value),
            validator: (value) => value == null ? 'Choose a placement' : null,
          ),
          DatePickerField(
            label: 'Due date *',
            value: _dueDate,
            required: true,
            onChanged: (value) => setState(() => _dueDate = value),
          ),
          SelectField(
            label: 'Contact method',
            value: _method,
            options: const [
              SelectOption('PHONE', 'Phone'),
              SelectOption('WHATSAPP', 'WhatsApp'),
              SelectOption('SMS', 'SMS'),
              SelectOption('VISIT', 'Visit'),
              SelectOption('EMAIL', 'Email'),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _method = value);
            },
          ),
          TextFormField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes for the call',
              hintText: 'What should the officer check?',
            ),
          ),
        ],
      ),
    );
  }
}
