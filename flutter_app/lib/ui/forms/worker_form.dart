import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../state/app_state.dart';
import 'form_helpers.dart';

Future<bool> showWorkerForm(
  BuildContext context, {
  Map<String, dynamic>? existing,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _WorkerForm(existing: existing),
  );
  return result == true;
}

class _WorkerForm extends StatefulWidget {
  const _WorkerForm({this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<_WorkerForm> createState() => _WorkerFormState();
}

class _WorkerFormState extends State<_WorkerForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _area;
  late final TextEditingController _experience;
  late final TextEditingController _salary;
  late final TextEditingController _skills;
  late final TextEditingController _languages;
  late final TextEditingController _categories;
  late final TextEditingController _notes;
  late final TextEditingController _idType;
  late final TextEditingController _idNumber;
  late final TextEditingController _ecName;
  late final TextEditingController _ecPhone;
  late String _status;
  late String _verification;
  String? _dob;
  bool _saving = false;

  static const _statuses = [
    'APPLICANT',
    'DOCUMENTS_PENDING',
    'UNDER_VERIFICATION',
    'VERIFIED',
    'TRAINING',
    'AVAILABLE',
    'RESERVED',
    'PLACED',
    'ON_LEAVE',
    'SUSPENDED',
    'INACTIVE',
  ];

  static const _verifications = [
    'PENDING',
    'IN_PROGRESS',
    'VERIFIED',
    'EXCEPTION',
    'REJECTED',
  ];

  @override
  void initState() {
    super.initState();
    final row = widget.existing;
    _name = TextEditingController(text: textOf(row, 'full_name'));
    _phone = TextEditingController(text: textOf(row, 'phone'));
    _area = TextEditingController(text: textOf(row, 'area'));
    _experience = TextEditingController(
      text: textOf(row, 'experience_years').isEmpty
          ? '0'
          : textOf(row, 'experience_years'),
    );
    _salary = TextEditingController(text: textOf(row, 'expected_salary_ugx'));
    _skills = TextEditingController(text: joinList(row?['skills']));
    _languages = TextEditingController(text: joinList(row?['languages']));
    _categories = TextEditingController(text: joinList(row?['service_categories']));
    _notes = TextEditingController(text: textOf(row, 'notes'));
    _idType = TextEditingController(text: textOf(row, 'national_id_type'));
    _idNumber = TextEditingController(text: textOf(row, 'national_id_number'));
    _ecName = TextEditingController(text: textOf(row, 'emergency_contact_name'));
    _ecPhone = TextEditingController(text: textOf(row, 'emergency_contact_phone'));
    _status = textOf(row, 'status').isEmpty ? 'APPLICANT' : textOf(row, 'status');
    _verification = textOf(row, 'verification_status').isEmpty
        ? 'PENDING'
        : textOf(row, 'verification_status');
    _dob = textOf(row, 'date_of_birth').isEmpty ? null : textOf(row, 'date_of_birth');
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _phone,
      _area,
      _experience,
      _salary,
      _skills,
      _languages,
      _categories,
      _notes,
      _idType,
      _idNumber,
      _ecName,
      _ecPhone,
    ]) {
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
      'area': _area.text.trim(),
      'status': _status,
      'verification_status': _verification,
      'experience_years': int.tryParse(_experience.text.trim()) ?? 0,
      'skills': splitList(_skills.text),
      'languages': splitList(_languages.text),
      'service_categories': splitList(_categories.text),
      'notes': _notes.text.trim(),
      'national_id_type': _idType.text.trim(),
      'national_id_number': _idNumber.text.trim(),
      'emergency_contact_name': _ecName.text.trim(),
      'emergency_contact_phone': _ecPhone.text.trim(),
      'date_of_birth': _dob,
    };
    final salary = _salary.text.trim();
    if (salary.isNotEmpty) data['expected_salary_ugx'] = salary;

    if (widget.existing == null) {
      await app.createRecord('worker', data);
    } else {
      await app.updateRecord('worker', textOf(widget.existing, 'id'), data);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: FormDialog(
        title: widget.existing == null ? 'Register worker' : 'Edit worker',
        wide: true,
        saving: _saving,
        onSubmit: _save,
        children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Full name *'),
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? 'Enter the full name' : null,
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
          Row(
            children: [
              Expanded(
                child: SelectField(
                  label: 'Status',
                  value: _status,
                  options: [
                    for (final status in _statuses)
                      SelectOption(status, Fmt.labelize(status)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _status = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SelectField(
                  label: 'Verification',
                  value: _verification,
                  options: [
                    for (final status in _verifications)
                      SelectOption(status, Fmt.labelize(status)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _verification = value);
                  },
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _experience,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Experience (years)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _salary,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Expected salary (UGX)'),
                ),
              ),
            ],
          ),
          TextFormField(
            controller: _skills,
            decoration: const InputDecoration(
              labelText: 'Skills',
              helperText: 'Comma separated, e.g. Cleaning, Cooking',
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _languages,
                  decoration: const InputDecoration(labelText: 'Languages'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _categories,
                  decoration: const InputDecoration(labelText: 'Service categories'),
                ),
              ),
            ],
          ),
          DatePickerField(
            label: 'Date of birth',
            value: _dob,
            onChanged: (value) => setState(() => _dob = value),
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _idType,
                  decoration: const InputDecoration(labelText: 'ID type'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _idNumber,
                  decoration: const InputDecoration(labelText: 'ID number'),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _ecName,
                  decoration: const InputDecoration(labelText: 'Emergency contact'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _ecPhone,
                  decoration: const InputDecoration(labelText: 'Contact phone'),
                ),
              ),
            ],
          ),
          TextFormField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Internal notes'),
          ),
        ],
      ),
    );
  }
}
