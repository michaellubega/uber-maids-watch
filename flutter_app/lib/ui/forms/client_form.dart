import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import 'form_helpers.dart';

Future<bool> showClientForm(
  BuildContext context, {
  Map<String, dynamic>? existing,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _ClientForm(existing: existing),
  );
  return result == true;
}

class _ClientForm extends StatefulWidget {
  const _ClientForm({this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<_ClientForm> createState() => _ClientFormState();
}

class _ClientFormState extends State<_ClientForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _area;
  late final TextEditingController _notes;
  late String _contact;
  late String _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final row = widget.existing;
    _name = TextEditingController(text: textOf(row, 'full_name'));
    _phone = TextEditingController(text: textOf(row, 'phone'));
    _email = TextEditingController(text: textOf(row, 'email'));
    _area = TextEditingController(text: textOf(row, 'area'));
    _notes = TextEditingController(text: textOf(row, 'notes'));
    _contact =
        textOf(row, 'preferred_contact').isEmpty ? 'PHONE' : textOf(row, 'preferred_contact');
    _status = textOf(row, 'status').isEmpty ? 'ACTIVE' : textOf(row, 'status');
  }

  @override
  void dispose() {
    for (final controller in [_name, _phone, _email, _area, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final app = context.read<AppState>();
    final data = <String, dynamic>{
      'full_name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'area': _area.text.trim(),
      'preferred_contact': _contact,
      'status': _status,
      'notes': _notes.text.trim(),
    };
    if (widget.existing == null) {
      await app.createRecord('client', data);
    } else {
      await app.updateRecord('client', textOf(widget.existing, 'id'), data);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: FormDialog(
        title: widget.existing == null ? 'Add client' : 'Edit client',
        saving: _saving,
        onSubmit: _save,
        children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Household / client name *'),
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? 'Enter the client name' : null,
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Phone *'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Enter a phone number' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _area,
                  decoration: const InputDecoration(labelText: 'Area *'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Enter the area' : null,
                ),
              ),
            ],
          ),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          Row(
            children: [
              Expanded(
                child: SelectField(
                  label: 'Preferred contact',
                  value: _contact,
                  options: const [
                    SelectOption('PHONE', 'Phone call'),
                    SelectOption('WHATSAPP', 'WhatsApp'),
                    SelectOption('SMS', 'SMS'),
                    SelectOption('EMAIL', 'Email'),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _contact = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SelectField(
                  label: 'Status',
                  value: _status,
                  options: const [
                    SelectOption('ACTIVE', 'Active'),
                    SelectOption('INACTIVE', 'Inactive'),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _status = value);
                  },
                ),
              ),
            ],
          ),
          TextFormField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          if (widget.existing == null)
            Text(
              'The client number is generated by the server and appears after '
              'the next sync.',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
  }
}
