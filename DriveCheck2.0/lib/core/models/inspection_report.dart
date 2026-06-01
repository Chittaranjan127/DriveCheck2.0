import 'inspection_step_row.dart';

/// Server-rendered post-inspection report. Aggregates the parent
/// inspection + every step row + AI-generated pricing + jockey pitch
/// + next-step instructions. The Flutter side renders this on the
/// InspectionReport screen — no client-side mutation.
class InspectionReport {
  final String id;
  final ReportCar car;
  final ReportCustomer customer;
  final String status;
  final int stepsCompleted;
  final int totalSteps;
  final int score;
  final List<InspectionStepRow> steps;
  final ReportPricing? pricing;        // null if the AI call soft-failed
  // Condition-neutral market band for the make/model/year/fuel/km —
  // independent of THIS car's inspection findings. The jockey cites it
  // when the seller is anchoring far above reality.
  final ReportMarketReference? marketReference;
  final ReportJockeyPitch? jockeyPitch; // null if the AI call soft-failed
  // Optional "bridge to ask" segment — only present when the seller
  // gave a quoted price AT booking AND it's above the AI estimate.
  // Lists repairable issues the seller could fix to close the gap.
  final ReportBridgeToAsk? bridgeToAsk;
  final ReportNextSteps? nextSteps;    // null if the AI call soft-failed
  final DateTime generatedAt;

  const InspectionReport({
    required this.id,
    required this.car,
    required this.customer,
    required this.status,
    required this.stepsCompleted,
    required this.totalSteps,
    required this.score,
    required this.steps,
    required this.generatedAt,
    this.pricing,
    this.marketReference,
    this.jockeyPitch,
    this.bridgeToAsk,
    this.nextSteps,
  });

  factory InspectionReport.fromJson(Map<String, dynamic> j) => InspectionReport(
        id: j['id'] as String,
        car: ReportCar.fromJson((j['car'] as Map?)?.cast<String, dynamic>() ?? const {}),
        customer: ReportCustomer.fromJson((j['customer'] as Map?)?.cast<String, dynamic>() ?? const {}),
        status: (j['status'] as String?) ?? '',
        stepsCompleted: (j['stepsCompleted'] as num?)?.toInt() ?? 0,
        totalSteps: (j['totalSteps'] as num?)?.toInt() ?? 13,
        score: (j['score'] as num?)?.toInt() ?? 0,
        steps: ((j['steps'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => InspectionStepRow.fromJson(m.cast<String, dynamic>()))
            .toList(),
        pricing: j['pricing'] == null
            ? null
            : ReportPricing.fromJson((j['pricing'] as Map).cast<String, dynamic>()),
        marketReference: j['marketReference'] == null
            ? null
            : ReportMarketReference.fromJson(
                (j['marketReference'] as Map).cast<String, dynamic>()),
        jockeyPitch: j['jockeyPitch'] == null
            ? null
            : ReportJockeyPitch.fromJson((j['jockeyPitch'] as Map).cast<String, dynamic>()),
        bridgeToAsk: j['bridgeToAsk'] == null
            ? null
            : ReportBridgeToAsk.fromJson((j['bridgeToAsk'] as Map).cast<String, dynamic>()),
        nextSteps: j['nextSteps'] == null
            ? null
            : ReportNextSteps.fromJson((j['nextSteps'] as Map).cast<String, dynamic>()),
        generatedAt: DateTime.tryParse((j['generatedAt'] as String?) ?? '')
            ?? DateTime.now(),
      );
}

class ReportCar {
  final String title;
  final String? model;
  final int? yearOfMake;
  final String? fuelType;
  final int? kmDriven;
  final String? area;
  // Seller's asking price from the booking — surfaced on the report
  // alongside the AI estimate so the jockey sees both numbers at a
  // glance and can defend the delta.
  final int? quotedPriceInr;

  const ReportCar({
    required this.title,
    this.model,
    this.yearOfMake,
    this.fuelType,
    this.kmDriven,
    this.area,
    this.quotedPriceInr,
  });

  factory ReportCar.fromJson(Map<String, dynamic> j) => ReportCar(
        title: (j['title'] as String?) ?? '',
        model: j['model'] as String?,
        yearOfMake: (j['yearOfMake'] as num?)?.toInt(),
        fuelType: j['fuelType'] as String?,
        kmDriven: (j['kmDriven'] as num?)?.toInt(),
        area: j['area'] as String?,
        quotedPriceInr: (j['quotedPriceInr'] as num?)?.toInt(),
      );
}

class ReportCustomer {
  final String? name;
  final String? phone;
  final String? address;

  const ReportCustomer({this.name, this.phone, this.address});

  factory ReportCustomer.fromJson(Map<String, dynamic> j) => ReportCustomer(
        name: j['name'] as String?,
        phone: j['phone'] as String?,
        address: j['address'] as String?,
      );
}

class ReportPricing {
  final int estimatedPriceInr;
  final int rangeLowInr;
  final int rangeHighInr;
  final double confidence;
  final List<String> factors;

  const ReportPricing({
    required this.estimatedPriceInr,
    required this.rangeLowInr,
    required this.rangeHighInr,
    required this.confidence,
    required this.factors,
  });

  factory ReportPricing.fromJson(Map<String, dynamic> j) => ReportPricing(
        estimatedPriceInr: (j['estimatedPriceInr'] as num?)?.toInt() ?? 0,
        rangeLowInr: (j['rangeLowInr'] as num?)?.toInt() ?? 0,
        rangeHighInr: (j['rangeHighInr'] as num?)?.toInt() ?? 0,
        confidence: ((j['confidence'] as num?) ?? 0).toDouble(),
        factors: ((j['factors'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
      );
}

/// Condition-neutral market band for this make/model/year/fuel/km.
/// Independent of THIS car's inspection findings — used by the jockey
/// to anchor the conversation when the seller's quote is far above
/// reality (e.g. ₹1 Cr asked for a WagonR).
class ReportMarketReference {
  final int rangeLowInr;
  final int rangeHighInr;
  final String basis; // short, localised — "Maruti WagonR 2019, ~45,000 km"

  const ReportMarketReference({
    required this.rangeLowInr,
    required this.rangeHighInr,
    required this.basis,
  });

  factory ReportMarketReference.fromJson(Map<String, dynamic> j) =>
      ReportMarketReference(
        rangeLowInr: (j['rangeLowInr'] as num?)?.toInt() ?? 0,
        rangeHighInr: (j['rangeHighInr'] as num?)?.toInt() ?? 0,
        basis: (j['basis'] as String?) ?? '',
      );
}

/// AI-written negotiation script for the jockey. One flowing
/// paragraph that opens with the price, names the inspection-derived
/// faults that justify it, acknowledges seller pushback, and closes
/// softly. Localised to the user's chosen language.
class ReportJockeyPitch {
  final int headlineInr;
  final String script;

  const ReportJockeyPitch({
    required this.headlineInr,
    required this.script,
  });

  factory ReportJockeyPitch.fromJson(Map<String, dynamic> j) => ReportJockeyPitch(
        headlineInr: (j['headlineInr'] as num?)?.toInt() ?? 0,
        // Accept both the new `script` field and any older payloads
        // that still ship `openingLine` — concatenated into a single
        // paragraph so the screen renders SOMETHING during the
        // backend deploy window.
        script: _composeScript(j),
      );

  static String _composeScript(Map<String, dynamic> j) {
    final script = (j['script'] as String?)?.trim();
    if (script != null && script.isNotEmpty) return script;
    // Backward-compat fallback for cached / in-flight responses.
    final parts = <String>[
      (j['openingLine'] as String?)?.trim() ?? '',
      ...((j['supportingPoints'] as List?) ?? const [])
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty),
      (j['addressingObjections'] as String?)?.trim() ?? '',
    ].where((s) => s.isNotEmpty);
    return parts.join(' ');
  }
}

/// Optional "bridge to ask" segment surfaced when the seller's quoted
/// price is above the AI offer. Lists repairable issues the seller
/// could address to close the gap, plus a one-line pitch the jockey
/// can read out as a soft counter-proposal during negotiation.
class ReportBridgeToAsk {
  final int targetPriceInr;
  final List<String> issues;
  final String pitchLine;

  const ReportBridgeToAsk({
    required this.targetPriceInr,
    required this.issues,
    required this.pitchLine,
  });

  factory ReportBridgeToAsk.fromJson(Map<String, dynamic> j) =>
      ReportBridgeToAsk(
        targetPriceInr: (j['targetPriceInr'] as num?)?.toInt() ?? 0,
        issues: ((j['issues'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
        pitchLine: (j['pitchLine'] as String?) ?? '',
      );
}

class ReportNextSteps {
  final String instruction;
  final List<String> etiquetteTips;

  const ReportNextSteps({
    required this.instruction,
    required this.etiquetteTips,
  });

  factory ReportNextSteps.fromJson(Map<String, dynamic> j) => ReportNextSteps(
        instruction: (j['instruction'] as String?) ?? '',
        etiquetteTips: ((j['etiquetteTips'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
      );
}

/// Outcome captured on the InspectionTicket. Matches the Lambda's
/// ALLOWED_OUTCOMES set.
enum TicketOutcome { accepted, countered, declined }

extension TicketOutcomeJson on TicketOutcome {
  String get wire {
    switch (this) {
      case TicketOutcome.accepted:  return 'accepted';
      case TicketOutcome.countered: return 'countered';
      case TicketOutcome.declined:  return 'declined';
    }
  }
}

/// Server-acknowledged ticket row. Returned by POST
/// /inspections/{id}/tickets — we don't render it directly but use
/// it to confirm the write and surface the assigned ticket id.
class InspectionTicket {
  final String id;
  final String inspectionId;
  final TicketOutcome outcome;
  final int aiPriceInr;
  final int? customerPriceInr;
  final String notes;
  final DateTime createdAt;

  const InspectionTicket({
    required this.id,
    required this.inspectionId,
    required this.outcome,
    required this.aiPriceInr,
    required this.notes,
    required this.createdAt,
    this.customerPriceInr,
  });

  factory InspectionTicket.fromJson(Map<String, dynamic> j) => InspectionTicket(
        id: j['id'] as String,
        inspectionId: j['inspectionId'] as String,
        outcome: _outcomeFromString(j['outcome'] as String?),
        aiPriceInr: (j['aiPriceInr'] as num?)?.toInt() ?? 0,
        customerPriceInr: (j['customerPriceInr'] as num?)?.toInt(),
        notes: (j['notes'] as String?) ?? '',
        createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? '')
            ?? DateTime.now(),
      );
}

TicketOutcome _outcomeFromString(String? s) {
  switch (s) {
    case 'accepted':  return TicketOutcome.accepted;
    case 'countered': return TicketOutcome.countered;
    case 'declined':  return TicketOutcome.declined;
    default:          return TicketOutcome.declined;
  }
}

/// Closed-deal record. Returned by POST /inspections/{id}/leads when
/// the customer agrees to the AI-suggested price. We don't render
/// the snapshot fields client-side — they're for procurement — but
/// keep the assigned id / agreed price for the success state.
class InspectionLead {
  final String id;
  final String inspectionId;
  final int agreedPriceInr;
  final int aiPriceInr;
  final String notes;
  final DateTime createdAt;

  const InspectionLead({
    required this.id,
    required this.inspectionId,
    required this.agreedPriceInr,
    required this.aiPriceInr,
    required this.notes,
    required this.createdAt,
  });

  factory InspectionLead.fromJson(Map<String, dynamic> j) => InspectionLead(
        id: j['id'] as String,
        inspectionId: j['inspectionId'] as String,
        agreedPriceInr: (j['agreedPriceInr'] as num?)?.toInt() ?? 0,
        aiPriceInr: (j['aiPriceInr'] as num?)?.toInt() ?? 0,
        notes: (j['notes'] as String?) ?? '',
        createdAt: DateTime.tryParse((j['createdAt'] as String?) ?? '')
            ?? DateTime.now(),
      );
}
