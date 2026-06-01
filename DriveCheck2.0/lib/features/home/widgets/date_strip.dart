import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../inspections_provider.dart';

/// Horizontal date strip — only days that have assigned inspections.
class DateStrip extends ConsumerWidget {
  const DateStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedDateProvider);
    final inspections = ref.watch(inspectionsProvider);

    final dates = <DateTime>{
      for (final i in inspections) DateTime(i.scheduledAt.year, i.scheduledAt.month, i.scheduledAt.day),
    }.toList()
      ..sort();

    if (dates.isEmpty) return const SizedBox(height: 0);

    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: dates.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final date = dates[i];
          final isSelected = date.year == selected.year && date.month == selected.month && date.day == selected.day;

          return _DatePill(
            date: date,
            isSelected: isSelected,
            onTap: () => ref.read(selectedDateProvider.notifier).select(date),
          );
        },
      ),
    );
  }
}

class _DatePill extends StatelessWidget {
  final DateTime date;
  final bool isSelected;
  final VoidCallback onTap;

  const _DatePill({required this.date, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = isSelected ? AppColors.ctaDark : AppColors.surfaceMuted;
    final fg = isSelected ? AppColors.onCtaDark : AppColors.textPrimary;
    final subFg = isSelected ? AppColors.onCtaDark.withValues(alpha: 0.7) : AppColors.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 58,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.ctaDark : AppColors.border, width: 1),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat('E').format(date).toUpperCase().substring(0, 3),
              style: AppTextStyles.caption.copyWith(color: subFg, fontWeight: FontWeight.w600, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              DateFormat('d').format(date),
              style: AppTextStyles.heading2.copyWith(color: fg, fontSize: 20),
            ),
          ],
        ),
      ),
    );
  }
}
