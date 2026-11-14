import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import 'form_helpers.dart';

Future<bool> showPaymentForm(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => const _PaymentForm(),
  );
  return result == true;
}

class _PaymentForm extends StatefulWidget {
  const _PaymentForm();

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  String? _clientId;
  String? _placementId;
  String? _bookingId;
  String _method = 'CASH';
  String _status = 'PAID';
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final app = context.read<AppState>();
    final client = rowById(app.rows('client'), _clientId);
    final placement = rowById(app.rows('placement'), _placementId);
    final booking = rowById(app.rows('booking'), _bookingId);
    if (client == null) return;
    setState(() => _saving = true);
    await app.createRecord('payment', {
      'client': _clientId,
      'placement': _placementId,
      'booking': _bookingId,
      'amount_ugx': _amount.text.trim(),
      'currency': 'UGX',
      'payment_method': _method,
      'reference': _reference.text.trim(),
      'status': _status,
      'notes': _notes.text.trim(),
      'client_name': textOf(client, 'full_name'),
      'client_number': textOf(client, 'client_number'),
      'placement_number': textOf(placement, 'placement_number'),
      'booking_number': textOf(booking, 'booking_number'),
    });
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final clients = app.rows('client');
    final placements = app.rows('placement');
    final bookings = app.rows('booking');

    return Form(
      key: _formKey,
      child: FormDialog(
        title: 'Record payment',
        saving: _saving,
        submitLabel: 'Record payment',
        onSubmit: _save,
        children: [
          SelectField(
            label: 'Client *',
            value: _clientId,
            options: optionsFromRows(clients, ['full_name', 'phone']),
            onChanged: (value) => setState(() => _clientId = value),
            validator: (value) => value == null ? 'Choose a client' : null,
          ),
          SelectField(
            label: 'Placement (optional)',
            value: _placementId,
            options: optionsFromRows(placements, [
              'placement_number',
              'client_name',
            ]),
            allowEmpty: true,
            onChanged: (value) => setState(() => _placementId = value),
          ),
          SelectField(
            label: 'Booking (optional)',
            value: _bookingId,
            options: optionsFromRows(bookings, ['booking_number', 'client_name']),
            allowEmpty: true,
            onChanged: (value) => setState(() => _bookingId = value),
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount (UGX) *'),
                  validator: (value) {
                    final amount = double.tryParse(value?.trim() ?? '');
                    if (amount == null || amount <= 0) {
                      return 'Enter an amount greater than zero';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SelectField(
                  label: 'Method',
                  value: _method,
                  options: const [
                    SelectOption('CASH', 'Cash'),
                    SelectOption('MOBILE_MONEY', 'Mobile money'),
                    SelectOption('BANK', 'Bank transfer'),
                    SelectOption('OTHER', 'Other'),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _method = value);
                  },
                ),
              ),
            ],
          ),
          SelectField(
            label: 'Status',
            value: _status,
            options: const [
              SelectOption('PAID', 'Paid'),
              SelectOption('PARTIAL', 'Partially paid'),
              SelectOption('PENDING', 'Pending'),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _status = value);
            },
          ),
          TextFormField(
            controller: _reference,
            decoration: const InputDecoration(
              labelText: 'External reference',
              hintText: 'Mobile money or bank reference',
            ),
          ),
          TextFormField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          Text(
            'Receipt numbers are generated by the server. Amounts and refund '
            'rules remain pending owner confirmation.',
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
