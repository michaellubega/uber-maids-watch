import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../state/app_state.dart';
import 'form_helpers.dart';

Future<bool> showPlacementForm(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => const _PlacementForm(),
  );
  return result == true;
}

class _PlacementForm extends StatefulWidget {
  const _PlacementForm();

  @override
  State<_PlacementForm> createState() => _PlacementFormState();
}

class _PlacementFormState extends State<_PlacementForm> {
  final _formKey = GlobalKey<FormState>();
  final _terms = TextEditingController();
  final _notes = TextEditingController();
  final _guarantee = TextEditingController(text: '14');
  String? _bookingId;
  String? _clientId;
  String? _workerId;
  String? _startDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _startDate = Fmt.today();
  }

  @override
  void dispose() {
    _terms.dispose();
    _notes.dispose();
    _guarantee.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final app = context.read<AppState>();
    final client = rowById(app.rows('client'), _clientId);
    final worker = rowById(app.rows('worker'), _workerId);
    final booking = rowById(app.rows('booking'), _bookingId);
    if (client == null || worker == null) return;
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'booking': _bookingId,
      'client': _clientId,
      'worker': _workerId,
      'start_date': _startDate,
      'status': 'ACTIVE',
      'guarantee_days': int.tryParse(_guarantee.text.trim()) ?? 14,
      'terms': _terms.text.trim(),
      'notes': _notes.text.trim(),
      'client_name': textOf(client, 'full_name'),
      'client_number': textOf(client, 'client_number'),
      'worker_name': textOf(worker, 'full_name'),
      'worker_number': textOf(worker, 'worker_number'),
      'booking_number': textOf(booking, 'booking_number'),
    };
    await app.createRecord('placement', data);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final bookings = app
        .rows('booking')
        .where((row) => row['status'] == 'CONFIRMED')
        .toList();
    final clients = app.rows('client');
    final workers = app
        .rows('worker')
        .where((row) =>
            const {'VERIFIED', 'EXCEPTION'}
                .contains(textOf(row, 'verification_status')) &&
            !const {'PLACED', 'SUSPENDED', 'INACTIVE'}
                .contains(textOf(row, 'status')))
        .toList();

    return Form(
      key: _formKey,
      child: FormDialog(
        title: 'Create placement',
        wide: true,
        saving: _saving,
        submitLabel: 'Place worker',
        onSubmit: _save,
        children: [
          SelectField(
            label: 'Confirmed booking',
            value: _bookingId,
            options: optionsFromRows(bookings, ['booking_number', 'client_name']),
            allowEmpty: true,
            emptyLabel: 'No booking (direct placement)',
            onChanged: (value) {
              setState(() {
                _bookingId = value;
                final booking = rowById(bookings, value);
                if (booking != null) _clientId = textOf(booking, 'client');
              });
            },
          ),
          SelectField(
            label: 'Client *',
            value: _clientId,
            options: optionsFromRows(clients, ['full_name', 'phone']),
            onChanged: (value) => setState(() => _clientId = value),
            validator: (value) => value == null ? 'Choose a client' : null,
          ),
          SelectField(
            label: 'Verified worker *',
            value: _workerId,
            options: optionsFromRows(workers, ['full_name', 'worker_number']),
            onChanged: (value) => setState(() => _workerId = value),
            validator: (value) => value == null ? 'Choose a worker' : null,
          ),
          Row(
            children: [
              Expanded(
                child: DatePickerField(
                  label: 'Start date *',
                  value: _startDate,
                  required: true,
                  onChanged: (value) => setState(() => _startDate = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _guarantee,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Guarantee days',
                    helperText: 'Default pending owner confirmation',
                  ),
                ),
              ),
            ],
          ),
          TextFormField(
            controller: _terms,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Placement terms'),
          ),
          TextFormField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Internal notes'),
          ),
          Text(
            'Only verified workers can be placed. The server also marks the '
            'booking as converted and checks the worker is available.',
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
