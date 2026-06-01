import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/translations.dart';
import '../../core/models/inspection.dart';
import '../../core/services/ai_assistant_service.dart';
import '../../core/services/language_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../auth/auth_provider.dart';
import '../auth/auth_state.dart';
import '../home/inspections_provider.dart';

/// Profile + preferences page. Hosted as the third bottom-nav tab (the
/// old top-right avatar bubble was removed).
///
/// Layout, top to bottom:
///   selfie · name · phone · joined-since · completed-inspection count
///   · change language · disable AI assistant · logout
///
/// "Disable AI assistant" persists via [aiAssistantEnabledProvider] —
/// when off, every TTS prompt is skipped and the bottom assistant bar
/// hides itself. Intended for jockeys who've already learned the flow.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final auth = ref.watch(authProvider);
    if (auth is! AuthAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final user = auth.user;
    final lang = ref.watch(languageProvider).valueOrNull;
    final inspections = ref.watch(inspectionsProvider);
    final completedCount = inspections
        .where((i) => i.status == InspectionStatus.completed)
        .length;
    final aiEnabled =
        ref.watch(aiAssistantEnabledProvider).valueOrNull ?? true;
    final dateFmt = DateFormat('d MMM yyyy');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.background,
        title: Text(t.navProfile, style: t.style(AppTextStyles.heading2)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            const SizedBox(height: 8),
            // ---- Identity block ----------------------------------
            Center(
              child: _Avatar(
                url: user.selfieUrl,
                name: user.name,
                phone: user.phoneNumber,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                user.name ?? '—',
                style: t.style(AppTextStyles.heading1),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                '+91 ${user.phoneNumber}',
                style: t.style(AppTextStyles.body)
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 24),

            // ---- Stats / facts -----------------------------------
            _Card(rows: [
              _InfoRow(
                icon: Icons.calendar_today_rounded,
                label: t.joinedSince,
                value: user.createdAt != null
                    ? dateFmt.format(user.createdAt!)
                    : '—',
                t: t,
              ),
              const _Divider(),
              _InfoRow(
                icon: Icons.task_alt_rounded,
                label: t.completedInspectionsCount,
                value: completedCount.toString(),
                t: t,
              ),
            ]),
            const SizedBox(height: 16),

            // ---- Preferences -------------------------------------
            _Card(rows: [
              _TapRow(
                icon: Icons.translate_rounded,
                label: t.changeLanguage,
                trailing: lang?.nativeName ?? t.notSet,
                onTap: () async {
                  await ref.read(languageProvider.notifier).clear();
                  if (context.mounted) context.go('/language');
                },
                t: t,
              ),
              const _Divider(),
              _SwitchRow(
                icon: Icons.auto_awesome_rounded,
                label: t.disableAiAssistant,
                hint: t.disableAiAssistantHint,
                // The toggle reads as "Disable AI", so it's ON when the
                // assistant is OFF. We negate when reading + writing.
                value: !aiEnabled,
                onChanged: (disabled) {
                  ref
                      .read(aiAssistantEnabledProvider.notifier)
                      .setEnabled(!disabled);
                },
                t: t,
              ),
            ]),
            const SizedBox(height: 24),

            // ---- Logout ------------------------------------------
            Center(
              child: TextButton.icon(
                onPressed: () => _confirmLogout(context, ref, t),
                icon: const Icon(Icons.logout_rounded,
                    color: AppColors.error),
                label: Text(
                  t.logout,
                  style: t.style(AppTextStyles.button)
                      .copyWith(color: AppColors.error),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(
      BuildContext context, WidgetRef ref, Translations t) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(t.logoutConfirmTitle,
            style: t.style(AppTextStyles.heading3)),
        content: Text(t.logoutConfirmBody, style: t.style(AppTextStyles.body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.cancel,
                style: t.style(AppTextStyles.button)
                    .copyWith(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.logout,
                style: t.style(AppTextStyles.button)
                    .copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(authProvider.notifier).signOut();
    if (context.mounted) context.go('/login');
  }
}

// ============================================================
// Pieces
// ============================================================

class _Avatar extends StatelessWidget {
  final String? url;
  final String? name;
  final String phone;
  const _Avatar({required this.url, required this.name, required this.phone});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: 0.12),
        image: url != null && url!.isNotEmpty
            ? DecorationImage(image: NetworkImage(url!), fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: (url != null && url!.isNotEmpty)
          ? null
          : Text(
              _initials(name, phone),
              style: AppTextStyles.heading1.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }

  String _initials(String? name, String phone) {
    if (name != null && name.trim().isNotEmpty) {
      final parts = name.trim().split(RegExp(r'\s+'));
      final first = parts.first.characters.first;
      final last = parts.length > 1 ? parts.last.characters.first : '';
      return (first + last).toUpperCase();
    }
    return phone.length >= 2 ? phone.substring(phone.length - 2) : phone;
  }
}

class _Card extends StatelessWidget {
  final List<Widget> rows;
  const _Card({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: rows),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => const Divider(
        height: 1,
        thickness: 1,
        indent: 18,
        endIndent: 18,
        color: AppColors.divider,
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Translations t;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: t.style(AppTextStyles.body)
                    .copyWith(color: AppColors.textSecondary)),
          ),
          Text(value,
              style: t.style(AppTextStyles.body).copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }
}

class _TapRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;
  final Translations t;
  const _TapRow({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.t,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Row(
            children: [
              Icon(icon, color: AppColors.textPrimary, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                    style: t.style(AppTextStyles.body)
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
              if (trailing != null)
                Text(trailing!,
                    style: t.style(AppTextStyles.body)
                        .copyWith(color: AppColors.textSecondary)),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textHint, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Translations t;
  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textPrimary, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: t.style(AppTextStyles.body)
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(hint,
                    style: t.style(AppTextStyles.caption)
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
