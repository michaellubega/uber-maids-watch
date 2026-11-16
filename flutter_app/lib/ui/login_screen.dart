import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// Demo seed credentials for the administrator account.
  ///
  /// They are pre-filled so the office can sign in immediately after install.
  /// Remove these defaults before using the build with real accounts.
  static const _seedUsername = 'admin';
  static const _seedPassword = 'Admin1234!';

  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController(text: _seedUsername);
  final _password = TextEditingController(text: _seedPassword);
  late final TextEditingController _server;
  bool _obscure = true;
  bool _showServer = false;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: context.read<AppState>().baseUrl);
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _submit(AppState app) async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    await app.setBaseUrl(_server.text);
    await app.signIn(username: _username.text, password: _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF053F45), Color(0xFF075B63), Color(0xFF079DA5)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Expanded(child: _BrandPanel()),
                        const SizedBox(width: 36),
                        SizedBox(width: 420, child: _formCard(app)),
                      ],
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _formCard(app),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formCard(AppState app) {
    return Card(
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 28, 26, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE1E9E8)),
                    ),
                    child: Image.asset(
                      'assets/images/logo-192.png',
                      width: 168,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                'Welcome back',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Sign in to manage verification, placements and follow-ups.',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.55),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              TextFormField(
                controller: _username,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter your username'
                    : null,
              ),
              const SizedBox(height: 13),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => app.busy ? null : _submit(app),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Enter your password'
                    : null,
              ),
              const SizedBox(height: 10),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: _showServer,
                  onExpansionChanged: (value) => _showServer = value,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.dns_outlined, size: 20),
                  title: const Text(
                    'Server connection',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    app.baseUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  children: [
                    TextFormField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'API base URL',
                        hintText: 'http://127.0.0.1:8000/api',
                        helperText:
                            'Default: hosted service at uber-maids-watch.onrender.com. '
                            'Use 127.0.0.1 or your computer LAN address for a local server.',
                        helperMaxLines: 2,
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (!text.startsWith('http://') &&
                            !text.startsWith('https://')) {
                          return 'Enter a full URL starting with http:// or https://';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              if (app.error != null) ...[
                const SizedBox(height: 8),
                _Callout(
                  icon: Icons.error_outline,
                  message: app.error!,
                  background: const Color(0xFFFBE6E3),
                  foreground: const Color(0xFFB5342A),
                ),
              ],
              if (app.notice != null) ...[
                const SizedBox(height: 8),
                _Callout(
                  icon: Icons.info_outline,
                  message: app.notice!,
                  background: const Color(0xFFE8F6F5),
                  foreground: const Color(0xFF075B63),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: app.busy ? null : () => _submit(app),
                icon: app.busy
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.login, size: 19),
                label: Text(app.busy ? 'Signing in…' : 'Sign in'),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.offline_bolt_outlined,
                    size: 16,
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Offline access is enabled after the first online sign-in. '
                      'Administrator actions still need a connection.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({
    required this.icon,
    required this.message,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String message;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: foreground,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 8, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Image.asset(
              'assets/images/logo-384.png',
              width: 264,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 30),
          const Text(
            'Trusted help for\nevery home.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 40,
              height: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'One workspace for recruitment, verification, training, '
            'placements, follow-ups and replacement guarantees.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.84),
              fontSize: 15,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 28),
          const _BrandPoint(
            icon: Icons.wifi_off_outlined,
            text: 'Keep working offline — records sync when you reconnect.',
          ),
          const _BrandPoint(
            icon: Icons.verified_user_outlined,
            text: 'Identity documents stay private and every sensitive action is audited.',
          ),
          const _BrandPoint(
            icon: Icons.support_agent_outlined,
            text: 'Track every placement through its guarantee window.',
          ),
          const SizedBox(height: 26),
          Text(
            'Sign in as a family, domestic worker, administrator or any office '
            'officer. Every role only sees the records its permissions allow.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandPoint extends StatelessWidget {
  const _BrandPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFA9ECEA), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
