import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/models/inspection.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Inspection card. Whole card tinted by status with a strong left accent + status icon.
/// Built for low-literacy users: color + icon + label triple-encode every state.
class InspectionCard extends StatelessWidget {
  final Inspection inspection;
  final Translations t;
  final bool isFirst;
  final bool isLast;

  const InspectionCard({
    super.key,
    required this.inspection,
    required this.t,
    this.isFirst = false,
    this.isLast = false,
  });

  _StatusStyle _style() {
    switch (inspection.status) {
      case InspectionStatus.scheduled:
        return _StatusStyle(
          accent: AppColors.primary,
          tint: AppColors.primaryLight,
          icon: Icons.schedule_rounded,
          label: t.statusScheduled,
          ctaLabel: t.startInspection,
          ctaIcon: Icons.play_arrow_rounded,
          ctaDestructive: false,
        );
      case InspectionStatus.inProgress:
        return _StatusStyle(
          accent: AppColors.warning,
          tint: const Color(0xFFFFF4E0),
          icon: Icons.directions_car_filled_rounded,
          label: t.statusInProgress,
          ctaLabel: t.continueInspection,
          ctaIcon: Icons.arrow_forward_rounded,
          ctaDestructive: false,
        );
      case InspectionStatus.completed:
        return _StatusStyle(
          accent: AppColors.success,
          tint: const Color(0xFFE8F8F1),
          icon: Icons.check_circle_rounded,
          label: t.statusCompleted,
          ctaLabel: t.viewReport,
          ctaIcon: Icons.description_outlined,
          ctaDestructive: false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _style();
    // Backend stores scheduledAt as ISO UTC (Date.toISOString from the
    // admin form). The DateTime that DateTime.parse returns is also
    // UTC; format it in the device's local timezone or jockeys in
    // IST see the slot 5h30m earlier than the booking actually was.
    final localAt = inspection.scheduledAt.toLocal();
    final time = DateFormat('h:mm').format(localAt);
    final ampm = DateFormat('a').format(localAt);
    final isDone = inspection.status == InspectionStatus.completed;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 60,
            child: Column(
              children: [
                const SizedBox(height: 6),
                Text(time, style: AppTextStyles.heading3.copyWith(fontSize: 15, color: isDone ? AppColors.textSecondary : AppColors.textPrimary)),
                Text(ampm, style: AppTextStyles.caption),
              ],
            ),
          ),
          _TimelineRail(isFirst: isFirst, isLast: isLast, color: s.accent),
          const SizedBox(width: 12),
          // Completed inspections collapse to a compact one-line
          // summary — the deal is closed, nothing to do here EXCEPT
          // tap to see the read-only details page (every captured
          // step + the outcome). Active cards keep the full body
          // with the CTA.
          Expanded(child: isDone
              ? InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () =>
                      context.push('/inspection/${inspection.id}/view'),
                  child: _CompletedCardBody(
                      inspection: inspection, t: t, s: s),
                )
              : _CardBody(
            inspection: inspection,
            t: t,
            s: s,
            // Completed inspections land on the report screen (the
            // "View report" CTA implies the priced + jockey-pitch
            // view, not the test-drive step the in-flow resume
            // logic would otherwise pick as the last completed step).
            // In-progress / scheduled keep the inspection-flow
            // entrypoint, which resumes at the next pending step.
            onAction: () => context.push(
              inspection.status == InspectionStatus.completed
                  ? '/inspection/${inspection.id}/report'
                  : '/inspection/${inspection.id}',
            ),
          )),
        ],
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  final Inspection inspection;
  final Translations t;
  final _StatusStyle s;
  final VoidCallback onAction;
  const _CardBody({required this.inspection, required this.t, required this.s, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final isDone = inspection.status == InspectionStatus.completed;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: s.tint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: s.accent.withValues(alpha: 0.25), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: s.accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(s.icon, size: 18, color: s.accent),
                        const SizedBox(width: 6),
                        Text(s.label,
                            style: AppTextStyles.chip.copyWith(color: s.accent, fontWeight: FontWeight.w700, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      inspection.carTitle,
                      style: t.style(AppTextStyles.heading3).copyWith(
                        color: isDone ? AppColors.textSecondary : AppColors.textPrimary,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        decorationColor: AppColors.textHint,
                      ),
                    ),
                    if (inspection.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(inspection.subtitle, style: t.style(AppTextStyles.caption)),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(inspection.customerName,
                              style: t.style(AppTextStyles.body).copyWith(color: AppColors.textSecondary)),
                        ),
                        if (inspection.distanceKm != null) ...[
                          const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text('${_approxKm(inspection.distanceKm!)} ${t.kmAway}',
                              style: t.style(AppTextStyles.caption)),
                        ],
                      ],
                    ),
                    // Seller's asking price chip — gives the jockey
                    // a heads-up on the negotiation anchor before they
                    // even open the inspection. Hidden when the
                    // booking didn't capture a quote.
                    if (inspection.quotedPriceInr != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.sell_outlined,
                              size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(
                            '${t.sellerQuoted}: ${_formatInr(inspection.quotedPriceInr!)}',
                            style: t.style(AppTextStyles.caption)
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    // Completed inspections are finalised — hide the
                    // action button and show a passive "submitted"
                    // chip instead so the card reads as terminal.
                    // Active jobs (scheduled / inProgress) keep their
                    // CTA so the jockey can resume the flow.
                    if (isDone)
                      _SubmittedBadge(label: t.submittedBadge, color: s.accent, t: t)
                    else
                      _ActionButton(label: s.ctaLabel, icon: s.ctaIcon, color: s.accent, isDone: isDone, onTap: onAction),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Collapsed variant rendered for COMPLETED inspections. One-row,
/// no CTA — the deal is closed and the jockey doesn't need to act on
/// it again. Matches the full card's left-rail / time-gutter so a
/// list of mixed-status cards still vertically aligns.
class _CompletedCardBody extends StatelessWidget {
  final Inspection inspection;
  final Translations t;
  final _StatusStyle s;
  const _CompletedCardBody({
    required this.inspection,
    required this.t,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: s.tint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: s.accent.withValues(alpha: 0.25), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Container(width: 3, height: 56, color: s.accent),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(s.icon, size: 18, color: s.accent),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    inspection.carTitle,
                    style: t.style(AppTextStyles.body).copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: AppColors.textHint,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    inspection.customerName,
                    style: t.style(AppTextStyles.caption)
                        .copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: s.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  t.statusCompleted,
                  style: AppTextStyles.chip.copyWith(
                    color: s.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Passive status chip rendered in place of [_ActionButton] when the
/// inspection has been completed + submitted. Looks like a soft-tinted
/// pill (matches the card accent), reads "This inspection has been
/// submitted" in the active language, and has no tap target — the
/// jockey is done with this job.
class _SubmittedBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Translations t;
  const _SubmittedBadge({
    required this.label,
    required this.color,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: t.style(AppTextStyles.body).copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isDone;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon, required this.color, required this.isDone, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = isDone ? Colors.transparent : color;
    final fg = isDone ? color : AppColors.onCtaDark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: isDone ? Border.all(color: color, width: 1.5) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 18),
            const SizedBox(width: 6),
            Text(label, style: AppTextStyles.button.copyWith(color: fg, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _TimelineRail extends StatelessWidget {
  final bool isFirst;
  final bool isLast;
  final Color color;
  const _TimelineRail({required this.isFirst, required this.isLast, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      child: Column(
        children: [
          Container(width: 2, height: 12, color: isFirst ? Colors.transparent : AppColors.border),
          Container(
            width: 14, height: 14,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: AppColors.background, width: 2)),
          ),
          Expanded(child: Container(width: 2, color: isLast ? Colors.transparent : AppColors.border)),
        ],
      ),
    );
  }
}

/// Formats a kilometre distance for the inspection card. Always
/// approximate — straight-line, not road distance — so we never imply
/// false precision. Examples: 0.4 → "<1", 3.7 → "~4", 12.4 → "~12".
String _approxKm(double km) {
  if (km < 1) return '<1';
  return '~${km.round()}';
}

/// Indian-style INR formatter: 480000 → "₹4,80,000". Mirrors the
/// helper in inspection_report_screen.dart — kept inline here so the
/// home card doesn't drag in the report-feature import surface.
String _formatInr(int n) {
  if (n < 1000) return '₹$n';
  final s = n.toString();
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '₹${groups.join(',')},$last3';
}

class _StatusStyle {
  final Color accent;
  final Color tint;
  final IconData icon;
  final String label;
  final String ctaLabel;
  final IconData ctaIcon;
  final bool ctaDestructive;
  const _StatusStyle({
    required this.accent,
    required this.tint,
    required this.icon,
    required this.label,
    required this.ctaLabel,
    required this.ctaIcon,
    required this.ctaDestructive,
  });
}
