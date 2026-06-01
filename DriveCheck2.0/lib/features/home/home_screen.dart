import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/i18n/translations.dart';
import '../../core/models/inspection.dart';
import '../../core/services/language_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/cars24_wordmark.dart';
import '../auth/auth_provider.dart';
import '../auth/auth_state.dart';
import '../inspection_flow/state/assistant_utterance_provider.dart';
import '../inspection_flow/widgets/assistant_bottom_bar.dart';
import 'inspections_provider.dart';
import 'widgets/inspection_card.dart';

/// Home: today's inspections only, timeline view.
///
/// The AI assistant bar pinned to the bottom carries a silent
/// greeting on mount (text visible, no audio). Tapping play asks the
/// AI to read out the jockey's day — name + pending / in-progress /
/// completed counts. Same `assistantUtteranceProvider` the inspection
/// flow uses, so the bar component is unchanged.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Tracks the last seeded greeting snapshot so we only re-push when
  // the underlying numbers (or jockey name) actually change.
  String? _lastSeededKey;

  // True until the very first greeting of the process auto-plays.
  // Cold launches (app killed + reopened) start with this true so the
  // jockey hears the summary once on boot; in-app navigation back to
  // home keeps it false, so the bar shows the text silently.
  static bool _coldStartGreetingPending = true;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final async = ref.watch(inspectionsAsyncProvider);
    final list = ref.watch(todaysInspectionsProvider);
    final auth = ref.watch(authProvider);
    final lang = ref.watch(languageProvider).valueOrNull ?? AppLanguage.hindi;
    final today = DateTime.now();

    // Seed the AI bar's silent greeting once the inspections list has
    // settled — autoplay: false so it shows the text + play button but
    // doesn't speak until the jockey taps. Re-seed when the numbers
    // (or jockey name) change so the play button always reflects the
    // current state.
    if (!async.isLoading) {
      _maybeSeedGreeting(list: list, auth: auth, lang: lang);
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 24,
        title: const Cars24Wordmark(fontSize: 22),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: async.isLoading
                ? null
                : () => ref.read(inspectionsAsyncProvider.notifier).refresh(),
            icon: async.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(Icons.refresh_rounded,
                    color: AppColors.textPrimary, size: 24),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.today, style: t.style(AppTextStyles.heading1)),
                  const SizedBox(height: 4),
                  Text(DateFormat('EEEE, d MMMM').format(today),
                      style: t.style(AppTextStyles.bodyLarge).copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            Expanded(
              child: async.isLoading && list.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : async.hasError && list.isEmpty
                      ? _ErrorState(t: t, onRetry: () => ref.read(inspectionsAsyncProvider.notifier).refresh())
                      : list.isEmpty
                          ? _EmptyState(t: t)
                          : RefreshIndicator(
                              onRefresh: () =>
                                  ref.read(inspectionsAsyncProvider.notifier).refresh(),
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                itemCount: list.length,
                                itemBuilder: (_, i) => InspectionCard(
                                  inspection: list[i],
                                  t: t,
                                  isFirst: i == 0,
                                  isLast: i == list.length - 1,
                                ),
                              ),
                            ),
            ),
            // AI assistant capsule pinned just above the home indicator.
            // The greeting is seeded silently (no audio) above; the
            // jockey taps the play button to hear it.
            const AssistantBottomBar(),
          ],
        ),
      ),
    );
  }

  void _maybeSeedGreeting({
    required List<Inspection> list,
    required AuthState auth,
    required AppLanguage lang,
  }) {
    final name = auth is AuthAuthenticated ? auth.user.name : null;
    final next = _nextActionable(list);
    final remainingAfterNext = next == null
        ? 0
        : list.where((i) {
            if (i.id == next.id) return false;
            return i.status == InspectionStatus.scheduled ||
                i.status == InspectionStatus.inProgress;
          }).length;
    final completed =
        list.where((i) => i.status == InspectionStatus.completed).length;

    // Snapshot key — bail out if nothing the greeting depends on has
    // changed since we last pushed. Avoids re-pushing on every rebuild
    // (which would yank the bar's text mid-playback). Keyed on the
    // specific next-to-do id + status so a status flip (scheduled →
    // inProgress → completed) re-narrates the day.
    final key = '${lang.code}|${name ?? ''}|'
        '${next?.id ?? '-'}|${next?.status.name ?? '-'}|'
        '$remainingAfterNext|$completed';
    if (key == _lastSeededKey) return;
    _lastSeededKey = key;

    final intro = _homeIntro(
      lang: lang,
      name: name,
      next: next,
      remainingAfterNext: remainingAfterNext,
      completed: completed,
      totalLoaded: list.length,
    );

    // Cold-launch the audio plays once; subsequent re-seeds during the
    // same process (in-app navigation back to home, AppSync update,
    // refresh) just update the bar's text silently. The flag is a
    // process-lifetime static, so killing & reopening the app naturally
    // resets it.
    final autoplay = _coldStartGreetingPending;
    if (autoplay) _coldStartGreetingPending = false;

    // Defer to the next frame — say() mutates a provider, which Riverpod
    // rejects from inside a build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(assistantUtteranceProvider.notifier).say(
            intro.spoken,
            display: intro.display,
            autoplay: autoplay,
          );
    });
  }
}

/// Display + spoken (SSML) pair for the home AI bar greeting.
class _HomeIntro {
  final String display;
  final String spoken;
  const _HomeIntro(this.display, this.spoken);
}

/// The next inspection the jockey should act on. Prefer one already
/// in progress (finish what's open) over a fresh scheduled one; within
/// each bucket, pick the earliest by scheduledAt.
Inspection? _nextActionable(List<Inspection> list) {
  final ongoing = list
      .where((i) => i.status == InspectionStatus.inProgress)
      .toList()
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  if (ongoing.isNotEmpty) return ongoing.first;
  final scheduled = list
      .where((i) => i.status == InspectionStatus.scheduled)
      .toList()
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  return scheduled.isNotEmpty ? scheduled.first : null;
}

/// Builds the AI bar's greeting. Specific to the jockey's actual
/// state, not a generic "you have N things":
///   - If something is in progress, push them to wrap THAT one first.
///   - Else if something is scheduled, name it + where to commute to.
///   - Else if everything's done, congratulate the day.
///   - Else (nothing on the books) acknowledge the empty day.
/// `remainingAfterNext` is appended as a one-line tail so the jockey
/// knows how many more cars sit behind the recommended one.
_HomeIntro _homeIntro({
  required AppLanguage lang,
  required String? name,
  required Inspection? next,
  required int remainingAfterNext,
  required int completed,
  required int totalLoaded,
}) {
  final hasName = name != null && name.trim().isNotEmpty;
  final n = hasName ? name.trim() : null;

  switch (lang) {
    case AppLanguage.english:
      final greet = n != null ? 'Hi $n' : 'Hi';
      if (next == null) {
        if (totalLoaded == 0) {
          const body = "nothing scheduled today. Take it easy — "
              "I'll let you know when a new inspection lands.";
          return _HomeIntro(
            '$greet, $body',
            '<speak>$greet. <break time="300ms"/> $body</speak>',
          );
        }
        // All loaded inspections are completed.
        final body = "you're done for the day — "
            "${completed == 1 ? '1 inspection wrapped up' : '$completed inspections wrapped up'}. "
            "Nice work.";
        return _HomeIntro(
          '$greet, $body',
          '<speak>$greet. <break time="300ms"/> $body</speak>',
        );
      }
      final action = next.status == InspectionStatus.inProgress
          ? "${next.carTitle} at ${next.area} is still open — head back and finish that one first."
          : "start with ${next.carTitle} at ${next.area} — head over and begin the inspection.";
      final tail = remainingAfterNext == 0
          ? ''
          : remainingAfterNext == 1
              ? ' Then 1 more after that.'
              : ' Then $remainingAfterNext more after that.';
      final body = '$action$tail';
      return _HomeIntro(
        '$greet, $body',
        '<speak>$greet. <break time="300ms"/> $body</speak>',
      );

    case AppLanguage.hindi:
      final greet = n != null ? 'नमस्ते $n' : 'नमस्ते';
      if (next == null) {
        if (totalLoaded == 0) {
          const body = 'आज कोई inspection नहीं है। आराम कीजिए '
              '— नया काम आते ही मैं बता दूँगा।';
          return _HomeIntro(
            '$greet, $body',
            '<speak>$greet। <break time="300ms"/> $body</speak>',
          );
        }
        final body = 'आज का काम पूरा हो गया '
            '— $completed inspection complete। बहुत बढ़िया!';
        return _HomeIntro(
          '$greet, $body',
          '<speak>$greet। <break time="300ms"/> $body</speak>',
        );
      }
      final action = next.status == InspectionStatus.inProgress
          ? '${next.carTitle} (${next.area}) अभी open है — '
              'पहले उसी को पूरा कीजिए।'
          : '${next.carTitle} से शुरू कीजिए, ${next.area} पहुँच कर '
              'inspection start कीजिए।';
      final tail = remainingAfterNext == 0
          ? ''
          : ' उसके बाद $remainingAfterNext और inspection है।';
      final body = '$action$tail';
      return _HomeIntro(
        '$greet, $body',
        '<speak>$greet। <break time="300ms"/> $body</speak>',
      );

    case AppLanguage.telugu:
      final greet = n != null ? 'హాయ్ $n' : 'హాయ్';
      if (next == null) {
        if (totalLoaded == 0) {
          const body = 'ఈరోజు ఏ inspection లేదు. విశ్రాంతి తీసుకోండి '
              '— కొత్తది వచ్చినప్పుడు నేను చెబుతాను.';
          return _HomeIntro(
            '$greet, $body',
            '<speak>$greet. <break time="300ms"/> $body</speak>',
          );
        }
        final body = 'ఈరోజు పని పూర్తయింది '
            '— $completed inspection complete. చాలా బాగుంది!';
        return _HomeIntro(
          '$greet, $body',
          '<speak>$greet. <break time="300ms"/> $body</speak>',
        );
      }
      final action = next.status == InspectionStatus.inProgress
          ? '${next.carTitle} (${next.area}) ఇంకా open గా ఉంది '
              '— ముందుగా దాన్ని పూర్తి చేయండి.'
          : '${next.carTitle} తో మొదలు పెట్టండి, ${next.area} కి వెళ్లి '
              'inspection start చేయండి.';
      final tail = remainingAfterNext == 0
          ? ''
          : ' ఆ తరువాత $remainingAfterNext inspection ఉన్నాయి.';
      final body = '$action$tail';
      return _HomeIntro(
        '$greet, $body',
        '<speak>$greet. <break time="300ms"/> $body</speak>',
      );

    case AppLanguage.bengali:
      final greet = n != null ? 'হাই $n' : 'হাই';
      if (next == null) {
        if (totalLoaded == 0) {
          const body = 'আজ কোনো inspection নেই। বিশ্রাম নিন '
              '— নতুন কাজ এলে আমি জানাবো।';
          return _HomeIntro(
            '$greet, $body',
            '<speak>$greet। <break time="300ms"/> $body</speak>',
          );
        }
        final body = 'আজকের কাজ শেষ '
            '— $completed inspection complete। দারুণ!';
        return _HomeIntro(
          '$greet, $body',
          '<speak>$greet। <break time="300ms"/> $body</speak>',
        );
      }
      final action = next.status == InspectionStatus.inProgress
          ? '${next.carTitle} (${next.area}) এখনো open — '
              'আগে ওটাই শেষ করুন।'
          : '${next.carTitle} দিয়ে শুরু করুন, ${next.area} গিয়ে '
              'inspection start করুন।';
      final tail = remainingAfterNext == 0
          ? ''
          : ' তারপর আরো $remainingAfterNext inspection আছে।';
      final body = '$action$tail';
      return _HomeIntro(
        '$greet, $body',
        '<speak>$greet। <break time="300ms"/> $body</speak>',
      );
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
          Text(t.noInspectionsToday,
              style: t.style(AppTextStyles.heading3).copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Translations t;
  final VoidCallback onRetry;
  const _ErrorState({required this.t, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(t.couldNotLoadInspections,
              style: t.style(AppTextStyles.heading3).copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry,
              child: Text(t.tryAgain, style: t.style(AppTextStyles.button)
                  .copyWith(color: AppColors.primary))),
        ],
      ),
    );
  }
}
