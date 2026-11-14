import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../state/app_state.dart';

enum PillTone { neutral, success, warning, danger, info }

PillTone toneFor(dynamic status) {
  final value = '${status ?? ''}'.toUpperCase();
  if (const {
    'ACTIVE',
    'VERIFIED',
    'PAID',
    'AVAILABLE',
    'COMPLETED',
    'RESOLVED',
    'APPLIED',
    'CLIENT_SATISFIED',
    'WORKER_SETTLED',
    'PASSED',
    'CONFIRMED',
    'ELIGIBLE',
    'APPROVED',
  }.contains(value)) {
    return PillTone.success;
  }
  if (const {
    'REJECTED',
    'EXPIRED',
    'SUSPENDED',
    'INACTIVE',
    'FAILED',
    'CANCELLED',
    'TERMINATED',
    'NOT_ELIGIBLE',
    'CLIENT_UNREACHABLE',
    'CONDUCT_CONCERN',
    'THEFT_ALLEGATION',
  }.contains(value)) {
    return PillTone.danger;
  }
  if (const {
    'PENDING',
    'PARTIAL',
    'IN_PROGRESS',
    'NEW',
    'CONTACTED',
    'REVIEWING',
    'OPEN',
    'DOCUMENTS_PENDING',
    'TRAINING',
    'RESERVED',
    'UNDER_VERIFICATION',
    'AWAITING_CLIENT',
    'AWAITING_WORKER',
    'REQUIREMENTS_CONFIRMED',
    'PREPARING',
    'PAUSED',
    'INVESTIGATING',
    'ON_LEAVE',
    'QUOTE',
  }.contains(value)) {
    return PillTone.warning;
  }
  if (const {
    'PLACED',
    'ASSIGNED',
    'CONVERTED',
    'REPLACEMENT_REQUESTED',
    'EXCEPTION',
    'IN_GUARANTEE',
  }.contains(value)) {
    return PillTone.info;
  }
  return PillTone.neutral;
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.tone});

  final String label;
  final PillTone? tone;

  @override
  Widget build(BuildContext context) {
    final resolved = tone ?? toneFor(label);
    final (background, foreground) = switch (resolved) {
      PillTone.success => (const Color(0xFFE3F6E9), const Color(0xFF17663A)),
      PillTone.warning => (const Color(0xFFFFF2D8), const Color(0xFF8A5A00)),
      PillTone.danger => (const Color(0xFFFDE7E7), const Color(0xFF9B1C1C)),
      PillTone.info => (const Color(0xFFE8F6F5), const Color(0xFF075B63)),
      PillTone.neutral => (const Color(0xFFEEF2F1), const Color(0xFF5C6B6A)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        Fmt.labelize(label),
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/logo.png', width: 190),
            const SizedBox(height: 16),
            const Text(
              'UBER MAIDS WATCH',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.onOpenSync});

  final VoidCallback? onOpenSync;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.signedIn) return const SizedBox.shrink();
    final offline = app.offlineMode || !app.online;
    final conflicts = app.conflictCount;
    if (!offline && conflicts == 0) return const SizedBox.shrink();

    final isConflict = conflicts > 0;
    final background = isConflict
        ? const Color(0xFFFFF4E5)
        : const Color(0xFFEFF3FB);
    final foreground = isConflict
        ? const Color(0xFF8A4B00)
        : const Color(0xFF2C3E66);
    final message = isConflict
        ? '$conflicts change${conflicts == 1 ? '' : 's'} need review before they can sync.'
        : 'Offline — showing data saved on this device.'
            '${app.pendingCount > 0 ? ' ${app.pendingCount} change${app.pendingCount == 1 ? '' : 's'} queued.' : ''}';

    return Material(
      color: background,
      child: InkWell(
        onTap: onOpenSync,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                isConflict ? Icons.sync_problem : Icons.cloud_off_outlined,
                size: 18,
                color: foreground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: foreground, fontSize: 13),
                ),
              ),
              if (onOpenSync != null)
                Text(
                  'View',
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.icon,
    this.tone = PillTone.info,
    this.onTap,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final PillTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      PillTone.success => const Color(0xFF17663A),
      PillTone.warning => const Color(0xFF9A6200),
      PillTone.danger => const Color(0xFF9B1C1C),
      PillTone.info => const Color(0xFF075B63),
      PillTone.neutral => const Color(0xFF5C6B6A),
    };
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.black.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (icon != null)
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 17, color: color),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: Colors.black26),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.55),
                    height: 1.4,
                  ),
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 18),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LabeledValue extends StatelessWidget {
  const LabeledValue({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Colors.black.withValues(alpha: 0.45),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 14, height: 1.35)),
        ],
      ),
    );
  }
}

class SearchBarField extends StatelessWidget {
  const SearchBarField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}

class RecordCard extends StatelessWidget {
  const RecordCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14.5,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 10),
                    trailing!,
                  ],
                ],
              ),
              if (footer != null) ...[
                const SizedBox(height: 10),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AvatarCircle extends StatelessWidget {
  const AvatarCircle({
    super.key,
    required this.name,
    this.size = 40,
    this.color,
  });

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final seed = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: seed.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(
        Fmt.initials(name),
        style: TextStyle(
          color: seed,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.34,
        ),
      ),
    );
  }
}

void showAppMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFF9B1C1C) : null,
    ),
  );
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

double pagePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width >= 1200 ? 32 : width >= 700 ? 22 : 14;
}
