import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/inspection_steps.dart';
import '../../core/i18n/translations.dart';
import '../../core/models/inspection.dart';
import '../../core/models/inspection_step.dart';
import '../../core/models/inspection_step_row.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../home/inspections_provider.dart';
import '../inspection_flow/ai/test_drive_questions.dart';
import '../inspection_flow/state/step_rows_provider.dart';

/// Pre-pricing review. The test drive's save handler routes here
/// instead of straight to /report — the jockey scrolls through every
/// captured step from RC (step 2) through test drive (step 13) to
/// confirm the data is good. Tapping "Confirm & get pricing"
/// continues to the AI report screen, which is where the gpt-4o
/// pricing call actually runs.
///
/// Read-only on purpose: edits route the user back into the step in
/// the inspection flow. The review screen is the dial-tone before the
/// expensive AI roundtrip — give the jockey one last look so they
/// don't waste an OpenAI call on bad data.
class InspectionReviewScreen extends ConsumerWidget {
  final String inspectionId;
  /// When true, the screen is rendered as a *read-only* view of a
  /// completed inspection: the "Confirm & get pricing" footer is
  /// hidden and an outcome banner (Accepted / Countered / Declined +
  /// final price) replaces the review prompt.
  final bool readOnly;
  const InspectionReviewScreen({
    super.key,
    required this.inspectionId,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final rowsAsync = ref.watch(stepRowsProvider(inspectionId));
    // Pull the parent inspection from the home cache so we can render
    // the outcome chip without an extra fetch. May be null for deep
    // links that bypass the home screen.
    final inspection = ref
        .watch(inspectionsProvider)
        .where((i) => i.id == inspectionId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          readOnly ? t.viewInspectionTitle : t.reviewTitle,
          style: t.style(AppTextStyles.heading3),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: rowsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorPane(
            t: t,
            message: '$e',
            onRetry: () =>
                ref.read(stepRowsProvider(inspectionId).notifier).refresh(),
          ),
          data: (rows) => _ReviewBody(
            t: t,
            rows: rows,
            readOnly: readOnly,
            inspection: inspection,
            onConfirm: () => context.go('/inspection/$inspectionId/report'),
          ),
        ),
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  final Translations t;
  final String message;
  final VoidCallback onRetry;
  const _ErrorPane({
    required this.t,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 48),
            const SizedBox(height: 12),
            Text(t.reviewLoadFailed,
                textAlign: TextAlign.center,
                style: t.style(AppTextStyles.body)
                    .copyWith(color: AppColors.error)),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded,
                  color: AppColors.onCtaDark),
              label: Text(t.tryAgain,
                  style: t.style(AppTextStyles.button)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewBody extends StatelessWidget {
  final Translations t;
  final List<InspectionStepRow> rows;
  final bool readOnly;
  /// Parent inspection — read from the home cache. Used in [readOnly]
  /// mode to render the outcome banner (accepted / countered /
  /// declined) and the final price.
  final Inspection? inspection;
  final VoidCallback onConfirm;

  const _ReviewBody({
    required this.t,
    required this.rows,
    required this.onConfirm,
    this.readOnly = false,
    this.inspection,
  });

  @override
  Widget build(BuildContext context) {
    // Iterate the canonical step definitions in order so the review
    // always renders steps 2..N — even ones that were skipped get a
    // placeholder row. Skip arrival (step 1): per spec the review
    // starts from RC.
    final defs = kInspectionSteps
        .where((s) => s.type != StepType.arrival)
        .toList();
    final rowsById = {for (final r in rows) r.stepId: r};

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            itemCount: defs.length + 1,
            itemBuilder: (ctx, i) {
              if (i == 0) {
                // In read-only mode the header is the outcome banner
                // (accepted / countered / declined + final price). In
                // pre-pricing review mode it's the "check before AI"
                // subtitle hint.
                if (readOnly) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _OutcomeBanner(t: t, inspection: inspection),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    t.reviewSubtitle,
                    style: t.style(AppTextStyles.body)
                        .copyWith(color: AppColors.textSecondary),
                  ),
                );
              }
              final def = defs[i - 1];
              final row = rowsById[def.id];
              return _StepReviewCard(t: t, def: def, row: row);
            },
          ),
        ),
        // No footer in read-only mode — the view page is exactly
        // that: a view. The user closes via the AppBar close button.
        if (!readOnly) _Footer(t: t, onConfirm: onConfirm),
      ],
    );
  }
}

/// Top-of-list outcome chip + final price for completed inspections.
/// Renders nothing when [inspection] is null (deep-link bypassed the
/// home cache) so the screen still shows the step list cleanly.
class _OutcomeBanner extends StatelessWidget {
  final Translations t;
  final Inspection? inspection;
  const _OutcomeBanner({required this.t, required this.inspection});

  @override
  Widget build(BuildContext context) {
    final i = inspection;
    if (i == null) return const SizedBox.shrink();
    final (label, color, icon) = switch (i.outcome) {
      InspectionOutcome.accepted => (
          t.outcomeAccepted,
          AppColors.success,
          Icons.check_circle_rounded,
        ),
      InspectionOutcome.countered => (
          t.outcomeCountered,
          AppColors.warning,
          Icons.handshake_rounded,
        ),
      InspectionOutcome.declined => (
          t.outcomeDeclined,
          AppColors.error,
          Icons.cancel_rounded,
        ),
      _ => (t.statusCompleted, AppColors.textSecondary, Icons.flag_rounded),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: t.style(AppTextStyles.body).copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        )),
                if (i.finalPriceInr != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${t.finalPriceLabel}: ${_formatInr(i.finalPriceInr!)}',
                    style: t.style(AppTextStyles.caption)
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Indian-style INR formatter — duplicate of the one in
/// inspection_report_screen so this file stays self-contained.
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

class _Footer extends StatelessWidget {
  final Translations t;
  final VoidCallback onConfirm;
  const _Footer({required this.t, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        height: 56,
        child: ElevatedButton.icon(
          onPressed: onConfirm,
          icon: const Icon(Icons.check_circle_rounded,
              color: AppColors.onCtaDark),
          label: Text(t.confirmAndAnalyze,
              style: t.style(AppTextStyles.button)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size.fromHeight(56),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Per-step review card
// ============================================================

class _StepReviewCard extends StatelessWidget {
  final Translations t;
  final InspectionStep def;
  final InspectionStepRow? row;

  const _StepReviewCard({
    required this.t,
    required this.def,
    required this.row,
  });

  @override
  Widget build(BuildContext context) {
    final isComplete = row?.isCompleted == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isComplete
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(t: t, def: def, isComplete: isComplete),
          if (row == null || !isComplete)
            _IncompleteBody(t: t)
          else
            _StepBody(t: t, def: def, row: row!),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final Translations t;
  final InspectionStep def;
  final bool isComplete;
  const _CardHeader({
    required this.t,
    required this.def,
    required this.isComplete,
  });

  @override
  Widget build(BuildContext context) {
    final title = _stepTitle(t, def.titleKey);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          Icon(_iconFor(def.type),
              size: 22, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: t.style(AppTextStyles.heading3)
                    .copyWith(fontSize: 15)),
          ),
          Icon(
            isComplete ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            color: isComplete ? AppColors.success : AppColors.warning,
            size: 20,
          ),
        ],
      ),
    );
  }

  IconData _iconFor(StepType type) {
    switch (type) {
      case StepType.arrival:    return Icons.where_to_vote_rounded;
      case StepType.photo:      return Icons.photo_camera_rounded;
      case StepType.multiPhoto: return Icons.burst_mode_rounded;
      case StepType.audio:      return Icons.mic_rounded;
      case StepType.voiceQA:    return Icons.record_voice_over_rounded;
    }
  }
}

class _IncompleteBody extends StatelessWidget {
  final Translations t;
  const _IncompleteBody({required this.t});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Text(t.reviewStepIncomplete,
          style: t.style(AppTextStyles.body)
              .copyWith(color: AppColors.textSecondary)),
    );
  }
}

/// Per-step body — switches on stepId to render the most relevant
/// preview for that capture. Falls back to a key/value JSON dump for
/// unknown step ids so future steps render *something* without a
/// code change here.
class _StepBody extends StatelessWidget {
  final Translations t;
  final InspectionStep def;
  final InspectionStepRow row;
  const _StepBody({
    required this.t,
    required this.def,
    required this.row,
  });

  @override
  Widget build(BuildContext context) {
    switch (def.id) {
      case 'rc_document':
        return _RcBody(t: t, row: row);
      case 'instrument_cluster':
        return _ClusterBody(t: t, row: row);
      case 'tyres':
        return _TyresBody(t: t, row: row);
      case 'engine_sound':
        return _EngineSoundBody(t: t, row: row);
      case 'test_drive':
        return _TestDriveBody(t: t, row: row);
      default:
        return _SinglePhotoBody(t: t, row: row);
    }
  }
}

// ---- Single photo ---------------------------------------------

class _SinglePhotoBody extends StatelessWidget {
  final Translations t;
  final InspectionStepRow row;
  const _SinglePhotoBody({required this.t, required this.row});

  @override
  Widget build(BuildContext context) {
    final url = row.mediaUrls.isNotEmpty ? row.mediaUrls.first : null;
    final quality = (row.aiAnalysis?['quality'] as String?) ?? '';
    final caption = (row.aiAnalysis?['successMessageDisplay'] as String?)
        ?? (row.aiAnalysis?['qualityReasonDisplay'] as String?)
        ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (url != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _BrokenImagePlaceholder(),
                ),
              ),
            ),
          if (caption.isNotEmpty || quality.isNotEmpty) ...[
            const SizedBox(height: 8),
            _QualityRow(quality: quality, caption: caption),
          ],
        ],
      ),
    );
  }
}

// ---- RC document ----------------------------------------------

class _RcBody extends StatelessWidget {
  final Translations t;
  final InspectionStepRow row;
  const _RcBody({required this.t, required this.row});

  @override
  Widget build(BuildContext context) {
    final url = row.mediaUrls.isNotEmpty ? row.mediaUrls.first : null;
    final d = row.data;
    final fields = <(String, String?)>[
      ('Registration', d['registrationNumber'] as String?),
      ('Owner',        d['ownerName'] as String?),
      ('Make / Model', _join([d['make'], d['model']])),
      ('Year',         _yearFrom(d['manufacturingDate'])),
      ('Fuel',         d['fuelType'] as String?),
      ('Colour',       d['colour'] as String?),
      ('Chassis',      d['chassisNumber'] as String?),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (url != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1.6,
                child: Image.network(url, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _BrokenImagePlaceholder()),
              ),
            ),
          const SizedBox(height: 10),
          ...fields
              .where((f) => (f.$2 ?? '').trim().isNotEmpty)
              .map((f) => _KvRow(label: f.$1, value: f.$2!)),
        ],
      ),
    );
  }

  static String? _yearFrom(dynamic v) {
    if (v is String && v.length >= 4) return v.substring(0, 4);
    return null;
  }

  static String? _join(List<dynamic> parts) {
    final cleaned = parts
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return cleaned.isEmpty ? null : cleaned.join(' ');
  }
}

// ---- Instrument cluster ---------------------------------------

class _ClusterBody extends StatelessWidget {
  final Translations t;
  final InspectionStepRow row;
  const _ClusterBody({required this.t, required this.row});

  @override
  Widget build(BuildContext context) {
    final url = row.mediaUrls.isNotEmpty ? row.mediaUrls.first : null;
    final d = row.data;
    final odo = d['odometerKm'];
    final fuel = d['fuelLevel'];
    final lights = (d['warningLights'] as List?)?.length ?? 0;
    final rpm = d['tachometerRpm'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (url != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 2.0,
                child: Image.network(url, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _BrokenImagePlaceholder()),
              ),
            ),
          const SizedBox(height: 10),
          if (odo is num)
            _KvRow(label: 'Odometer', value: '${_formatNum(odo.toInt())} km'),
          if (fuel != null) _KvRow(label: 'Fuel', value: fuel.toString()),
          if (rpm is num && rpm > 0)
            _KvRow(label: 'RPM', value: rpm.toString()),
          if (lights > 0)
            _KvRow(label: 'Warning lights', value: '$lights lit'),
        ],
      ),
    );
  }
}

// ---- Tyres (4-up) ---------------------------------------------

class _TyresBody extends StatelessWidget {
  final Translations t;
  final InspectionStepRow row;
  const _TyresBody({required this.t, required this.row});

  @override
  Widget build(BuildContext context) {
    // Pull positional URLs out of `data.tyres` so the grid order is
    // stable (FL/FR/RL/RR) instead of whatever order the jockey
    // captured them in.
    final tyres = (row.data['tyres'] as Map?)?.cast<String, dynamic>() ?? {};
    final positions = const [
      ('frontLeft',  'FL'),
      ('frontRight', 'FR'),
      ('rearLeft',   'RL'),
      ('rearRight',  'RR'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 4,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        children: positions.map((pos) {
          final url = tyres[pos.$1] as String?;
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              color: AppColors.surfaceMuted,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url != null && url.isNotEmpty)
                    Image.network(url, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image_rounded,
                          color: AppColors.textHint,
                        ))
                  else
                    const Center(
                      child: Icon(Icons.add_a_photo_outlined,
                          color: AppColors.textHint),
                    ),
                  Positioned(
                    left: 4, bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(pos.$2,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---- Engine sound ---------------------------------------------

class _EngineSoundBody extends StatelessWidget {
  final Translations t;
  final InspectionStepRow row;
  const _EngineSoundBody({required this.t, required this.row});

  @override
  Widget build(BuildContext context) {
    final ai = row.aiAnalysis ?? const {};
    final verdict = (ai['verdict'] as String?) ?? '';
    final score = ai['healthScore'];
    final issues = (ai['detectedIssues'] as List?) ?? const [];
    final caption = (ai['summaryDisplay'] as String?)
        ?? (ai['qualityReasonDisplay'] as String?)
        ?? '';
    final hasAudio = row.mediaUrls.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(
              hasAudio ? Icons.graphic_eq_rounded : Icons.mic_off_rounded,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasAudio ? 'Engine recording captured' : 'No recording',
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
            if (score is num)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _toneFor(verdict).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('${score.toInt()}/100',
                    style: AppTextStyles.body.copyWith(
                      color: _toneFor(verdict),
                      fontWeight: FontWeight.w700,
                    )),
              ),
          ]),
          if (verdict.isNotEmpty) ...[
            const SizedBox(height: 8),
            _KvRow(label: 'Verdict', value: verdict),
          ],
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(caption,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary)),
          ],
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: issues
                  .whereType<String>()
                  .map((e) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          e.replaceAll('_', ' '),
                          style: AppTextStyles.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Color _toneFor(String v) {
    switch (v) {
      case 'smooth':        return AppColors.success;
      case 'minorIssue':    return AppColors.warning;
      case 'concern':       return AppColors.warning;
      case 'criticalIssue': return AppColors.error;
      default:              return AppColors.textSecondary;
    }
  }
}

// ---- Test drive -----------------------------------------------

class _TestDriveBody extends StatelessWidget {
  final Translations t;
  final InspectionStepRow row;
  const _TestDriveBody({required this.t, required this.row});

  @override
  Widget build(BuildContext context) {
    final d = row.data;
    final answers = (d['answers'] as List?) ?? const [];
    final overall = (d['overallSummary'] as String?) ?? '';
    final score = d['healthScore'];
    final verdictKey = (d['verdict'] as String?) ?? '';
    final lang = t.language;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (score is num)
            Row(children: [
              Expanded(
                child: Text(
                  '${t.tdVerdictLabel}: ${_localizedVerdict(t, verdictKey)}',
                  style: t.style(AppTextStyles.body),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('${score.toInt()}/100',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    )),
              ),
            ]),
          if (answers.isNotEmpty) ...[
            const SizedBox(height: 8),
            // Look the question + value up in kTestDriveQuestions so
            // both sides render in the user's chosen language instead
            // of the raw machine ids ("acceleration"/"smooth").
            ...answers.whereType<Map>().map((a) {
              final qid = a['questionId']?.toString() ?? '';
              final val = a['value']?.toString() ?? '';
              final q = kTestDriveQuestions
                  .where((x) => x.id == qid)
                  .firstOrNull;
              final label = q?.shortLabel[lang] ?? _humanize(qid);
              final value = q?.valueLabels[lang]?[val]
                  ?? _humanize(val);
              return _KvRow(label: label, value: value);
            }),
          ],
          if (overall.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(overall,
                  style: t.style(AppTextStyles.body).copyWith(height: 1.4)),
            ),
          ],
        ],
      ),
    );
  }

  String _humanize(String id) {
    if (id.isEmpty) return id;
    final spaced = id.replaceAll('_', ' ');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  String _localizedVerdict(Translations t, String key) {
    switch (key) {
      case 'good':          return t.tdVerdictGood;
      case 'minorIssue':    return t.tdVerdictMinor;
      case 'concern':       return t.tdVerdictConcern;
      case 'criticalIssue': return t.tdVerdictCritical;
      case 'inconclusive':  return t.tdVerdictInconclusive;
      default:              return '—';
    }
  }
}

// ---- Shared row + helpers -------------------------------------

class _KvRow extends StatelessWidget {
  final String label;
  final String value;
  const _KvRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w600,
                )),
          ),
        ],
      ),
    );
  }
}

class _QualityRow extends StatelessWidget {
  final String quality;
  final String caption;
  const _QualityRow({required this.quality, required this.caption});

  @override
  Widget build(BuildContext context) {
    final isGood = quality == 'good';
    final tone = isGood ? AppColors.success : AppColors.warning;
    final icon = isGood
        ? Icons.check_circle_rounded
        : Icons.info_rounded;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: tone, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            caption.isEmpty ? quality : caption,
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textPrimary, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _BrokenImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceMuted,
      child: const Center(
        child: Icon(Icons.broken_image_rounded,
            size: 32, color: AppColors.textHint),
      ),
    );
  }
}

String _stepTitle(Translations t, String key) {
  // Mirror inspection_flow_screen's _t — keep the switch local so the
  // review screen doesn't depend on that file.
  switch (key) {
    case 'stepArrivalTitle':         return t.stepArrivalTitle;
    case 'stepRcTitle':              return t.stepRcTitle;
    case 'stepClusterTitle':         return t.stepClusterTitle;
    case 'stepEngineBayTitle':       return t.stepEngineBayTitle;
    case 'stepFrontTitle':           return t.stepFrontTitle;
    case 'stepLeftTitle':            return t.stepLeftTitle;
    case 'stepRightTitle':           return t.stepRightTitle;
    case 'stepRearTitle':            return t.stepRearTitle;
    case 'stepRoofTitle':            return t.stepRoofTitle;
    case 'stepInteriorTitle':        return t.stepInteriorTitle;
    case 'stepTyresTitle':           return t.stepTyresTitle;
    case 'stepEngineSoundTitle':     return t.stepEngineSoundTitle;
    case 'stepTestDriveTitle':       return t.stepTestDriveTitle;
    default:                         return key;
  }
}

String _formatNum(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
