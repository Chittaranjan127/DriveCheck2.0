import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/models/inspection.dart';
import '../../core/services/appsync_subscription.dart';
import '../../core/services/inspections_service.dart';
import '../../core/services/location_service.dart';
import '../auth/auth_provider.dart';
import '../auth/auth_state.dart';

const _onInspectionsForJockey = r'''
subscription OnInspectionsForJockey($assignedTo: String!) {
  onInspectionsForJockey(assignedTo: $assignedTo) {
    id assignedTo status completedStepCount stepCount
    carTitle customerName scheduledAt updatedAt
  }
}
''';

/// Backing AsyncNotifier — hits `GET /inspections?assignedTo=<me>` and holds
/// the result. Re-runs whenever the authenticated phone number changes.
///
/// On top of the REST cold-fetch this also opens an AppSync subscription
/// (`onInspectionsForJockey`) and merges incoming events into the cached
/// list — so a status flip on the backend (or a new inspection assigned
/// to this jockey) shows up on the home screen without a manual refresh.
class InspectionsNotifier extends AsyncNotifier<List<Inspection>> {
  final InspectionsService _svc = InspectionsService();

  AppsyncSubscription? _wsClient;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  @override
  Future<List<Inspection>> build() async {
    final auth = ref.watch(authProvider);

    // Whenever auth changes (or the provider's torn down) drop the
    // existing live subscription. A new one opens below once we're
    // authed again.
    ref.onDispose(_tearDownLive);

    if (auth is! AuthAuthenticated) return const [];
    final List<Inspection> initial;
    try {
      initial = await _svc.list(assignedTo: auth.user.phoneNumber);
    } catch (e) {
      debugPrint('[inspections] fetch failed: $e');
      rethrow;
    }

    // Fire-and-forget: connecting can take a few hundred ms; we
    // don't want to delay the home screen waiting for it. Errors
    // here are logged and swallowed — the REST data is still in
    // place, the user just won't get live updates.
    unawaited(_startLiveUpdates(auth.user.phoneNumber));
    return initial;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }

  /// Opens the AppSync subscription for this jockey and pipes
  /// incoming `onInspectionsForJockey` events into the cached state.
  /// Merge semantics: id-match → replace; otherwise prepend.
  Future<void> _startLiveUpdates(String assignedTo) async {
    await _tearDownLive();
    try {
      debugPrint('[inspections] live: connecting WS for $assignedTo');
      _wsClient = await AppsyncSubscription.connect();
      debugPrint('[inspections] live: WS connected, opening subscription');
      _wsSub = _wsClient!
          .subscribe(
            operation: _onInspectionsForJockey,
            variables: {'assignedTo': assignedTo},
          )
          .listen(_applyEvent, onError: (e) {
        debugPrint('[inspections] live error: $e');
      });
      debugPrint('[inspections] live: subscription open for $assignedTo');
    } catch (e) {
      debugPrint('[inspections] live subscribe failed: $e');
    }
  }

  void _applyEvent(Map<String, dynamic> data) {
    final raw = data['onInspectionsForJockey'];
    if (raw is! Map<String, dynamic>) {
      debugPrint('[inspections] live event: unexpected shape $data');
      return;
    }
    debugPrint('[inspections] live event: id=${raw['id']} '
        'assignedTo=${raw['assignedTo']} status=${raw['status']}');
    final Inspection updated;
    try {
      updated = Inspection.fromJson(raw);
    } catch (e) {
      debugPrint('[inspections] decode failed: $e');
      return;
    }
    final current = state.valueOrNull ?? const <Inspection>[];
    final idx = current.indexWhere((i) => i.id == updated.id);
    if (idx == -1) {
      state = AsyncData([updated, ...current]);
    } else {
      // Preserve the client-computed distanceKm if the live event
      // didn't carry it (the AppSync payload doesn't include lat/lng).
      final preservedDistance = current[idx].distanceKm;
      final merged = preservedDistance != null
          ? updated.withDistance(preservedDistance)
          : updated;
      final next = [...current]..[idx] = merged;
      state = AsyncData(next);
    }
  }

  Future<void> _tearDownLive() async {
    await _wsSub?.cancel();
    _wsSub = null;
    await _wsClient?.dispose();
    _wsClient = null;
  }
}

final inspectionsAsyncProvider =
    AsyncNotifierProvider<InspectionsNotifier, List<Inspection>>(
        InspectionsNotifier.new);

/// Sync view of the master list. Empty while loading or on error — UI may
/// observe [inspectionsAsyncProvider] directly when it needs those states.
final inspectionsProvider = Provider<List<Inspection>>((ref) {
  return ref.watch(inspectionsAsyncProvider).valueOrNull ?? const [];
});

/// One-shot read of the device's current position. Returns `null` if the
/// service is off or the user denied permission — the UI then just hides
/// the distance row instead of erroring.
class CurrentPositionNotifier extends AsyncNotifier<Position?> {
  @override
  Future<Position?> build() => LocationService.instance.getCurrent();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => LocationService.instance.getCurrent());
  }
}

final currentPositionProvider =
    AsyncNotifierProvider<CurrentPositionNotifier, Position?>(
        CurrentPositionNotifier.new);

/// Returns a copy of [source] with each inspection's [Inspection.distanceKm]
/// populated from the device's current position. Falls back to the original
/// row when the inspection has no coordinates or location is unavailable.
List<Inspection> _withDistances(List<Inspection> source, Position? me) {
  if (me == null) return source;
  return source
      .map((i) => i.hasLocation
          ? i.withDistance(LocationService.instance.distanceKm(
              me.latitude, me.longitude, i.latitude!, i.longitude!))
          : i)
      .toList();
}

/// Currently selected date (date-only, time normalised to midnight).
class SelectedDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void select(DateTime date) {
    state = DateTime(date.year, date.month, date.day);
  }
}

final selectedDateProvider =
    NotifierProvider<SelectedDateNotifier, DateTime>(SelectedDateNotifier.new);

/// Inspections filtered to [selectedDateProvider], sorted by time, with
/// per-row distance from the device's current position injected. Compares
/// dates after converting [Inspection.scheduledAt] (UTC from the backend)
/// to the device's local timezone.
final inspectionsForSelectedDateProvider = Provider<List<Inspection>>((ref) {
  final all = ref.watch(inspectionsProvider);
  final date = ref.watch(selectedDateProvider);
  final me = ref.watch(currentPositionProvider).valueOrNull;
  final list = all.where((i) {
    final local = i.scheduledAt.toLocal();
    return local.year == date.year &&
        local.month == date.month &&
        local.day == date.day;
  }).toList();
  list.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  return _withDistances(list, me);
});

/// Home view: every inspection scheduled today or in the future, sorted by
/// time, with per-row distance. Anything before today is hidden — that's
/// history, not "what's next". If the jockey has nothing today but
/// something tomorrow, this still shows the tomorrow row so the screen
/// never goes blank just because of a calendar boundary.
final todaysInspectionsProvider = Provider<List<Inspection>>((ref) {
  final all = ref.watch(inspectionsProvider);
  final me = ref.watch(currentPositionProvider).valueOrNull;
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final list = all.where((i) {
    final local = i.scheduledAt.toLocal();
    return !local.isBefore(startOfToday);
  }).toList();
  list.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  return _withDistances(list, me);
});
