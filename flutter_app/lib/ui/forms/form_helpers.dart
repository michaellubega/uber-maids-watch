import 'package:flutter/material.dart';

import '../../core/formatters.dart';

class SelectOption {
  const SelectOption(this.value, this.label);

  final String value;
  final String label;
}

class SelectField extends StatelessWidget {
  const SelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.validator,
    this.allowEmpty = false,
    this.emptyLabel = 'None',
  });

  final String label;
  final String? value;
  final List<SelectOption> options;
  final ValueChanged<String?> onChanged;
  final String? Function(String?)? validator;
  final bool allowEmpty;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final values = options.map((option) => option.value).toSet();
    final initial = value != null && values.contains(value)
        ? value
        : (allowEmpty ? '' : null);
    return DropdownButtonFormField<String>(
      initialValue: initial,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        if (allowEmpty)
          DropdownMenuItem(value: '', child: Text(emptyLabel)),
        for (final option in options)
          DropdownMenuItem(
            value: option.value,
            child: Text(option.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (selected) {
        onChanged(selected == null || selected.isEmpty ? null : selected);
      },
      validator: validator,
    );
  }
}

class DatePickerField extends StatelessWidget {
  const DatePickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final String? value;
  final ValueChanged<String> onChanged;
  final bool required;
  final DateTime? firstDate;
  final DateTime? lastDate;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final parsed = DateTime.tryParse(value ?? '') ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed,
      firstDate: firstDate ?? DateTime(now.year - 30),
      lastDate: lastDate ?? DateTime(now.year + 6),
    );
    if (picked != null) onChanged(formatDateValue(picked));
  }

  @override
  Widget build(BuildContext context) {
    final text = value == null || value!.isEmpty ? 'Not set' : Fmt.date(value);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _pick(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
          errorText: required && (value == null || value!.isEmpty)
              ? 'Choose a date'
              : null,
        ),
        child: Text(text),
      ),
    );
  }
}

String formatDateValue(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class FormDialog extends StatelessWidget {
  const FormDialog({
    super.key,
    required this.title,
    required this.children,
    required this.onSubmit,
    this.submitLabel = 'Save',
    this.saving = false,
    this.wide = false,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onSubmit;
  final String submitLabel;
  final bool saving;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: wide ? 620 : 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1) const SizedBox(height: 13),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : onSubmit,
          child: saving
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(submitLabel),
        ),
      ],
    );
  }
}

List<String> splitList(String value) {
  return value
      .split(RegExp(r'[,;\n]'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
}

String joinList(dynamic value) {
  if (value is List) return value.map((item) => '$item').join(', ');
  return '${value ?? ''}';
}

String textOf(Map<String, dynamic>? row, String key) {
  final value = row?[key];
  if (value == null) return '';
  return '$value';
}

String labelForRow(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key];
    if (value != null && '$value'.trim().isNotEmpty) return '$value';
  }
  return 'Record';
}

List<SelectOption> optionsFromRows(
  List<Map<String, dynamic>> rows,
  List<String> keys,
) {
  final options = <SelectOption>[];
  final seen = <String>{};
  for (final row in rows) {
    final id = textOf(row, 'id');
    if (id.isEmpty || !seen.add(id)) continue;
    options.add(SelectOption(id, labelForRow(row, keys)));
  }
  options.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return options;
}

Map<String, dynamic>? rowById(
  List<Map<String, dynamic>> rows,
  String? id,
) {
  if (id == null) return null;
  for (final row in rows) {
    if (textOf(row, 'id') == id) return row;
  }
  return null;
}
