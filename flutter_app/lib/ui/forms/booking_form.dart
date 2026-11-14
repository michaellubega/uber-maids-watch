import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../state/app_state.dart';
import 'form_helpers.dart';

Future<bool> showBookingForm(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => const _BookingForm(),
  );
  return result == true;
}

class _BookingForm extends StatefulWidget {
  const _BookingForm();

  @override
  State<_BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends State<_BookingForm> {
  final _formKey = GlobalKey<FormState>();
  final _location = TextEditingController();
  final _schedule = TextEditingController();
  final _requirements = TextEditingController();
  final _budget = TextEditingController();
  final _instructions = TextEditingController();
  String? _clientId;
  String? _serviceId;
  String _status = 'NEW';
  String? _startDate;
  bool _saving = false;

  static const _statuses = [
    'NEW',
    'CONTACTED',
    'REQUIREMENTS_CONFIRMED',
    'AWAITING_CLIENT',
    'AWAITING_WORKER',
  ];

  @override
  void dispose() {
    for (final controller in [
      _location,
      _schedule,
      _requirements,
      _budget,
      _instructions,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final app = context.read<AppState>();
    final family = app.user?.role == 'FAMILY';
    final client = family
        ? app.myClient
        : rowById(app.rows('client'), _clientId);
    final service = rowById(app.rows('service'), _serviceId);
    if (client == null) return;
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'client': textOf(client, 'id'),
      'service': _serviceId,
      'requested_start_date': _startDate,
      'location': _location.text.trim(),
      'schedule': _schedule.text.trim(),
      'requirements': _requirements.text.trim(),
      'special_instructions': _instructions.text.trim(),
      if (!family) 'status': _status,
      'client_name': textOf(client, 'full_name'),
      'client_number': textOf(client, 'client_number'),
      'service_name': textOf(service, 'name'),
    };
    if (_budget.text.trim().isNotEmpty) {
      data['budget_ugx'] = _budget.text.trim();
    }
    await app.createRecord('booking', data);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final family = app.user?.role == 'FAMILY';
    final clients = app.rows('client');
    final services = app.rows('service').where((row) => row['active'] != false).toList();
    final clientOptions = optionsFromRows(clients, ['full_name', 'phone']);
    final serviceOptions =
        optionsFromRows(services, ['name', 'category']);
    final myClient = app.myClient;

    return Form(
      key: _formKey,
      child: FormDialog(
        title: family ? 'Request a worker' : 'New booking',
        wide: true,
        saving: _saving,
        submitLabel: family ? 'Submit request' : 'Create booking',
        onSubmit: _save,
        children: [
          if (family) ...[
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Your household'),
              child: Text(
                myClient == null
                    ? 'No client record is linked to this account yet.'
                    : '${textOf(myClient, 'client_number')} · ${textOf(myClient, 'full_name')}',
              ),
            ),
          ] else
            SelectField(
              label: 'Client *',
              value: _clientId,
              options: clientOptions,
              onChanged: (value) => setState(() => _clientId = value),
              validator: (value) => value == null ? 'Choose a client' : null,
            ),
          SelectField(
            label: 'Service *',
            value: _serviceId,
            options: serviceOptions,
            onChanged: (value) => setState(() => _serviceId = value),
            validator: (value) => value == null ? 'Choose a service' : null,
          ),
          DatePickerField(
            label: 'Preferred start date',
            value: _startDate,
            onChanged: (value) => setState(() => _startDate = value),
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _location,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _budget,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Budget (UGX)',
                    helperText: 'Pending owner confirmation',
                  ),
                ),
              ),
            ],
          ),
          TextFormField(
            controller: _schedule,
            decoration: const InputDecoration(
              labelText: 'Schedule',
              hintText: 'e.g. Monday to Saturday, live-in',
            ),
          ),
          TextFormField(
            controller: _requirements,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Requirements',
              hintText: 'Children, cooking, cleaning, languages…',
            ),
          ),
          TextFormField(
            controller: _instructions,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Special instructions'),
          ),
          if (!family)
            SelectField(
              label: 'Initial status',
              value: _status,
              options: [
                for (final status in _statuses)
                  SelectOption(status, Fmt.labelize(status)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _status = value);
              },
            ),
          Text(
            family
                ? 'Requests are reviewed by customer care. You will be contacted '
                    'to confirm the details.'
                : 'A booking becomes a placement when a verified worker is assigned.',
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
