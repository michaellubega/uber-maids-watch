import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../core/permissions.dart';
import '../state/app_state.dart';
import 'widgets.dart';

class AdministrationScreen extends StatefulWidget {
  const AdministrationScreen({super.key});

  @override
  State<AdministrationScreen> createState() => _AdministrationScreenState();
}

class _AdministrationScreenState extends State<AdministrationScreen> {
  String _tab = 'users';
  Future<Map<String, dynamic>>? _users;
  Future<Map<String, dynamic>>? _audit;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final api = context.read<AppState>().api;
    setState(() {
      _users = api.get('/users/');
      _audit = api.get('/audit-logs/');
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final padding = pagePadding(context);
    if (!app.user!.isAdmin) {
      return ListView(
        padding: EdgeInsets.all(padding),
        children: const [
          EmptyState(
            icon: Icons.lock_outline,
            title: 'Administrators only',
            message: 'This area is limited to the administrator role. It is '
                'enforced by the server, not just hidden in the app.',
          ),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.all(padding),
      children: [
        SectionHeader(
          title: 'Administration',
          subtitle: 'Accounts, audit trail and the rules still waiting for the '
              'owner to confirm them.',
          action: IconButton(
            tooltip: 'Reload',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in const {
              'users': 'Users',
              'audit': 'Audit trail',
              'policies': 'Pending policies',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _tab == entry.key,
                onSelected: (_) => setState(() => _tab = entry.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        switch (_tab) {
          'audit' => _AuditPanel(future: _audit),
          'policies' => const _PolicyPanel(),
          _ => _UsersPanel(
              future: _users,
              onChanged: _reload,
              onAdd: () => _addUser(context),
            ),
        },
        const SizedBox(height: 12),
      ],
    );
  }

  Future<void> _addUser(BuildContext context) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _UserDialog(),
    );
    if (created == true) {
      _reload();
      if (context.mounted) {
        showAppMessage(context, 'User created and written to the audit trail.');
      }
    }
  }
}

class _UsersPanel extends StatelessWidget {
  const _UsersPanel({
    required this.future,
    required this.onChanged,
    required this.onAdd,
  });

  final Future<Map<String, dynamic>>? future;
  final VoidCallback onChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.person_add_alt_1, size: 18),
            label: const Text('Add user'),
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<Map<String, dynamic>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return _ApiError(error: snapshot.error);
            }
            final rows = _rows(snapshot.data);
            if (rows.isEmpty) {
              return const EmptyState(
                icon: Icons.group_outlined,
                title: 'No users',
                message: 'Create staff and family accounts here. Each role only '
                    'sees the records the server allows.',
              );
            }
            return Column(
              children: [
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Card(
                      child: ListTile(
                        leading: AvatarCircle(
                          name: '${row['display_name'] ?? row['username'] ?? '?'}',
                        ),
                        title: Text(
                          '${row['display_name'] ?? row['username'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          [
                            '@${row['username'] ?? ''}',
                            Permissions.roleLabel('${row['role'] ?? ''}'),
                            if ('${row['email'] ?? ''}'.isNotEmpty)
                              '${row['email']}',
                            if ('${row['phone_number'] ?? ''}'.isNotEmpty)
                              '${row['phone_number']}',
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            StatusPill(
                              label: row['is_active'] == false
                                  ? 'INACTIVE'
                                  : 'ACTIVE',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Last login ${Fmt.dateTime(row['last_login'], fallback: 'never')}',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: Colors.black.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                        onTap: () => _editUser(context, row, onChanged),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  static List<Map<String, dynamic>> _rows(Map<String, dynamic>? data) {
    final results = data?['results'];
    if (results is! List) return const [];
    return results
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> _editUser(
    BuildContext context,
    Map<String, dynamic> user,
    VoidCallback onChanged,
  ) async {
    final app = context.read<AppState>();
    final active = user['is_active'] != false;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${user['display_name'] ?? user['username'] ?? 'User'}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabeledValue(
                label: 'Role',
                value: Permissions.roleLabel('${user['role'] ?? ''}'),
              ),
              LabeledValue(label: 'Username', value: '${user['username'] ?? ''}'),
              LabeledValue(
                label: 'Last login',
                value: Fmt.dateTime(user['last_login'], fallback: 'never'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Account active'),
                subtitle: const Text(
                  'Inactive accounts cannot sign in but keep their records.',
                ),
                value: active,
                onChanged: (value) =>
                    Navigator.of(dialogContext).pop(value != active),
              ),
              Text(
                'Role changes and deactivation are written to the audit trail. '
                'Reassign roles carefully — data visibility follows the role.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Colors.black.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (result != true) return;
    try {
      await app.api.patch(
        '/users/${user['id']}/',
        body: {'is_active': !active},
      );
      onChanged();
      if (context.mounted) {
        showAppMessage(
          context,
          active ? 'Account deactivated.' : 'Account reactivated.',
        );
      }
    } on ApiException catch (error) {
      if (context.mounted) showAppMessage(context, error.message, error: true);
    }
  }
}

class _AuditPanel extends StatelessWidget {
  const _AuditPanel({required this.future});

  final Future<Map<String, dynamic>>? future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) return _ApiError(error: snapshot.error);
        final results = snapshot.data?['results'];
        final rows = results is List
            ? results
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : const <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return const EmptyState(
            icon: Icons.history,
            title: 'No audit entries yet',
            message: 'Sign-ins, verification decisions, placement changes and '
                'payment updates appear here once they are recorded.',
          );
        }
        return Column(
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.receipt_long_outlined, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                Fmt.labelize(row['action']),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '${row['actor_name'] ?? 'System'} · '
                                '${row['entity'] ?? ''}'
                                '${'${row['entity_id'] ?? ''}'.isEmpty ? '' : ' · ${Fmt.truncate('${row['entity_id']}', 12)}'}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.black.withValues(alpha: 0.55),
                                ),
                              ),
                              if (row['metadata'] is Map &&
                                  (row['metadata'] as Map).isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  (row['metadata'] as Map)
                                      .entries
                                      .take(4)
                                      .map((entry) => '${entry.key}: ${entry.value}')
                                      .join(' · '),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.black.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          Fmt.dateTime(row['created_at']),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.black.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PolicyPanel extends StatelessWidget {
  const _PolicyPanel();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFFBF0),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.gavel_outlined, size: 20, color: Color(0xFF8A5A00)),
                SizedBox(width: 9),
                Text(
                  'Awaiting owner confirmation',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'The system stores these values as configurable data. It does not '
              'invent policy. Until the owner confirms them, screens label the '
              'values as pending and staff should confirm with management.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: Colors.black.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 14),
            for (final rule in AppState.pendingBusinessRules)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.pending_outlined, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(rule, style: const TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              ),
            const Divider(height: 22),
            Text(
              'Current technical defaults',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '• Guarantee: 14 days from the placement start date.\n'
              '• Replacement eligibility: always decided and recorded by a '
              'manager.\n'
              '• Payments: amounts are entered by finance; no price is '
              'calculated by the app.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: Colors.black.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'See docs/BUSINESS_RULES.md for the full list.',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApiError extends StatelessWidget {
  const _ApiError({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final message = error is ApiException
        ? (error as ApiException).message
        : 'Could not load this data from the server.';
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: 'Server unavailable',
      message: '$message Administration data is not cached on the device; '
          'reconnect and reload.',
    );
  }
}

class _UserDialog extends StatefulWidget {
  const _UserDialog();

  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String _role = 'OPERATIONS';
  bool _saving = false;

  static const _roles = [
    'ADMIN',
    'OPERATIONS',
    'VERIFICATION',
    'CUSTOMER_CARE',
    'FINANCE',
    'READONLY',
    'MAID',
    'FAMILY',
  ];

  @override
  void dispose() {
    for (final controller in [
      _username,
      _first,
      _last,
      _email,
      _phone,
      _password,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final app = context.read<AppState>();
    try {
      await app.api.post('/users/', body: {
        'username': _username.text.trim(),
        'first_name': _first.text.trim(),
        'last_name': _last.text.trim(),
        'email': _email.text.trim(),
        'phone_number': _phone.text.trim(),
        'role': _role,
        'password': _password.text,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showAppMessage(context, error.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: AlertDialog(
        title: const Text('Add user'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Username *'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Enter a username'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _first,
                        decoration: const InputDecoration(labelText: 'First name'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _last,
                        decoration: const InputDecoration(labelText: 'Last name'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        decoration: const InputDecoration(labelText: 'Phone'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role *'),
                  items: [
                    for (final role in _roles)
                      DropdownMenuItem(
                        value: role,
                        child: Text(Permissions.roleLabel(role)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _role = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Temporary password *',
                    helperText: 'At least 8 characters. Ask the user to change it.',
                  ),
                  validator: (value) => (value == null || value.length < 8)
                      ? 'Use at least 8 characters'
                      : null,
                ),
                const SizedBox(height: 10),
                Text(
                  'Accounts are created on the server. The role decides what the '
                  'user can read and write; the API enforces it on every call.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Create user'),
          ),
        ],
      ),
    );
  }
}
