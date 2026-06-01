import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/translations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../home/inspections_provider.dart';
import '../home/widgets/date_strip.dart';
import '../home/widgets/inspection_card.dart';

/// Full week timeline. Date strip on top, inspections for selected date below.
class InspectionsScreen extends ConsumerWidget {
  const InspectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final selected = ref.watch(selectedDateProvider);
    final list = ref.watch(inspectionsForSelectedDateProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.inspections, style: t.style(AppTextStyles.heading2))),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_relativeLabel(selected, t), style: t.style(AppTextStyles.heading1)),
                  const SizedBox(height: 4),
                  Text(DateFormat('EEEE, d MMMM').format(selected),
                      style: t.style(AppTextStyles.bodyLarge).copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            const DateStrip(),
            const SizedBox(height: 12),
            Expanded(
              child: list.isEmpty
                  ? _EmptyState(t: t)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: list.length,
                      itemBuilder: (_, i) => InspectionCard(
                        inspection: list[i],
                        t: t,
                        isFirst: i == 0,
                        isLast: i == list.length - 1,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _relativeLabel(DateTime date, Translations t) {
    final today = DateTime.now();
    final d = DateTime(today.year, today.month, today.day);
    final diff = date.difference(d).inDays;
    if (diff == 0) return t.today;
    if (diff == 1) return t.tomorrow;
    if (diff == -1) return t.yesterday;
    return DateFormat('d MMM').format(date);
  }
}

class _EmptyState extends StatelessWidget {
  final Translations t;
  const _EmptyState({required this.t});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.event_busy_outlined, size: 48, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(t.noInspectionsForDay,
              style: t.style(AppTextStyles.heading3).copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
