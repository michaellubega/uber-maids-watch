import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../state/app_state.dart';
import 'form_helpers.dart';

Future<bool> showServiceForm(
  BuildContext context, {
  Map<String, dynamic>? existing,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _ServiceForm(existing: existing),
  );
  return result == true;
}

class _ServiceForm extends StatefulWidget {
  const _ServiceForm({this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<_ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends State<_ServiceForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _requirements;
  late final TextEditingController _min;
  late final TextEditingController _max;
  late String _category;
  late String _pricing;
  late bool _active;
  late bool _public;
  bool _saving = false;

  static const _categories = [
    'MAID',
    'BABYSITTER',
    'CLEANER',
    'COOK',
    'LAUNDRY',
    'OTHER',
  ];
  static const _pricingTypes = ['ONE_TIME', 'MONTHLY', 'DAILY', 'QUOTE'];

  @override
  void initState() {
    super.initState();
    final row = widget.existing;
    _name = TextEditingController(text: textOf(row, 'name'));
    _description = TextEditingController(text: textOf(row, 'description'));
    _requirements = TextEditingController(text: textOf(row, 'requirements'));
    _min = TextEditingController(text: textOf(row, 'price_min_ugx'));
    _max = TextEditingController(text: textOf(row, 'price_max_ugx'));
    _category = textOf(row, 'category').isEmpty ? 'MAID' : textOf(row, 'category');
    _pricing =
        textOf(row, 'pricing_type').isEmpty ? 'QUOTE' : textOf(row, 'pricing_type');
    _active = row?['active'] != false;
    _public = row?['public_visibility'] == true;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _description,
      _requirements,
      _min,
      _max,
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
      'name': _name.text.trim(),
      'category': _category,
      'pricing_type': _pricing,
      'description': _description.text.trim(),
      'requirements': _requirements.text.trim(),
      'active': _active,
      'public_visibility': _public,
      if (_min.text.trim().isNotEmpty) 'price_min_ugx': _min.text.trim(),
      if (_max.text.trim().isNotEmpty) 'price_max_ugx': _max.text.trim(),
    };
    if (widget.existing == null) {
      await app.createRecord('service', data);
    } else {
      await app.updateRecord('service', textOf(widget.existing, 'id'), data);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: FormDialog(
        title: widget.existing == null ? 'Add service' : 'Edit service',
        saving: _saving,
        onSubmit: _save,
        children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Service name *'),
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? 'Enter a service name' : null,
          ),
          Row(
            children: [
              Expanded(
                child: SelectField(
                  label: 'Category',
                  value: _category,
                  options: [
                    for (final category in _categories)
                      SelectOption(category, Fmt.labelize(category)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SelectField(
                  label: 'Pricing type',
                  value: _pricing,
                  options: [
                    for (final pricing in _pricingTypes)
                      SelectOption(pricing, Fmt.labelize(pricing)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _pricing = value);
                  },
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _min,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minimum price (UGX)',
                    helperText: 'Pending owner confirmation',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _max,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Maximum price (UGX)',
                    helperText: 'Pending owner confirmation',
                  ),
                ),
              ),
            ],
          ),
          TextFormField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          TextFormField(
            controller: _requirements,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Requirements'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            subtitle: const Text('Available for new bookings'),
            value: _active,
            onChanged: (value) => setState(() => _active = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show on public website'),
            value: _public,
            onChanged: (value) => setState(() => _public = value),
          ),
        ],
      ),
    );
  }
}
