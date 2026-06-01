enum InspectionStatus { scheduled, inProgress, completed }

/// What the seller said at the end of a completed inspection.
/// Persisted on the parent Inspection row by `createLead` (accepted)
/// and `createTicket` (countered / declined) so the home card + the
/// read-only completed-inspection view can render the outcome chip
/// without a join back to the leads/tickets tables.
enum InspectionOutcome { accepted, countered, declined }

/// One inspection job assigned to the jockey. Mirrors the backend row shape
/// from `DriveCheck-Inspections-{stage}` so a row maps 1:1 via [fromJson].
class Inspection {
  final String id;
  final DateTime scheduledAt;
  final String carTitle;     // e.g. "Maruti Swift" — make + model headline

  // Vehicle attributes shown in the computed [subtitle]. Each is nullable
  // and may be populated either at row creation time (dealer-supplied) or
  // patched in later by an inspection step (RC OCR fills year + fuel,
  // instrument-cluster OCR fills kmDriven). Steps push corrections via the
  // updateStep `parentUpdates` channel when their extracted value differs.
  final String? model;       // e.g. "Vitara Brezza"
  final int? yearOfMake;     // 4-digit year, e.g. 2019
  final String? fuelType;    // canonical: "Petrol" / "Diesel" / "CNG" / etc
  final int? kmDriven;       // odometer reading in kilometres
  // Seller's asking price at booking time. Shown next to the AI's
  // estimated price on the report so the jockey can see the delta
  // they need to defend during negotiation. Nullable — older rows
  // and inspections booked without a quote both come through as null.
  final int? quotedPriceInr;

  final String customerName;
  final String area;
  final String? address;     // full street address for the pickup
  final double? latitude;    // pickup coordinates
  final double? longitude;
  final double? distanceKm;  // backend doesn't store this; nullable
  final InspectionStatus status;
  // What the seller said at the end (only set when status==completed).
  // Null on scheduled / in-progress rows.
  final InspectionOutcome? outcome;
  // The number the deal actually closed (or counter-offered) at.
  // For accepted leads: agreedPriceInr. For countered tickets:
  // customerPriceInr. For declined tickets: the AI's last offer.
  // Null until the inspection is completed.
  final int? finalPriceInr;
  // How many of the 13 steps have been marked complete on the server. Used
  // to resume the inspection flow at the right step when the user reopens
  // an in-progress job instead of restarting from step 1.
  final int completedStepCount;
  final int stepCount;

  const Inspection({
    required this.id,
    required this.scheduledAt,
    required this.carTitle,
    required this.customerName,
    required this.area,
    this.model,
    this.yearOfMake,
    this.fuelType,
    this.kmDriven,
    this.quotedPriceInr,
    this.address,
    this.latitude,
    this.longitude,
    this.distanceKm,
    this.status = InspectionStatus.scheduled,
    this.outcome,
    this.finalPriceInr,
    this.completedStepCount = 0,
    this.stepCount = 13,
  });

  /// True when both lat & long are present, so callers can offer a "Navigate"
  /// affordance without first checking each field.
  bool get hasLocation => latitude != null && longitude != null;

  /// One-line summary displayed under [carTitle] — composed from whichever
  /// of the vehicle attributes are known. Missing fields are skipped so the
  /// line is always tight; before any step has run this may be empty.
  ///
  /// Example: "Vitara Brezza · 2019 · Petrol · 47,000 km"
  String get subtitle {
    final parts = <String>[
      if (model != null && model!.trim().isNotEmpty) model!.trim(),
      if (yearOfMake != null) yearOfMake.toString(),
      if (fuelType != null && fuelType!.trim().isNotEmpty) fuelType!.trim(),
      if (kmDriven != null) '${_formatKm(kmDriven!)} km',
    ];
    return parts.join(' · ');
  }

  /// Returns a new [Inspection] with [distanceKm] populated. Lets us inject a
  /// client-computed distance into the row without making the field mutable.
  Inspection withDistance(double? km) => Inspection(
        id: id,
        scheduledAt: scheduledAt,
        carTitle: carTitle,
        model: model,
        yearOfMake: yearOfMake,
        fuelType: fuelType,
        kmDriven: kmDriven,
        quotedPriceInr: quotedPriceInr,
        customerName: customerName,
        area: area,
        address: address,
        latitude: latitude,
        longitude: longitude,
        distanceKm: km,
        status: status,
        outcome: outcome,
        finalPriceInr: finalPriceInr,
        completedStepCount: completedStepCount,
        stepCount: stepCount,
      );

  factory Inspection.fromJson(Map<String, dynamic> j) => Inspection(
        id: j['id'] as String,
        scheduledAt: DateTime.parse(j['scheduledAt'] as String),
        carTitle: (j['carTitle'] as String?) ?? '',
        model: _str(j['model']),
        yearOfMake: _int(j['yearOfMake']),
        fuelType: _str(j['fuelType']),
        kmDriven: _int(j['kmDriven']),
        quotedPriceInr: _int(j['quotedPriceInr']),
        customerName: (j['customerName'] as String?) ?? '',
        area: (j['area'] as String?) ?? '',
        address: j['address'] as String?,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        distanceKm: (j['distanceKm'] as num?)?.toDouble(),
        status: _statusFromString(j['status'] as String?),
        outcome: _outcomeFromString(j['outcome'] as String?),
        finalPriceInr: _int(j['finalPriceInr']),
        completedStepCount: (j['completedStepCount'] as num?)?.toInt() ?? 0,
        stepCount: (j['stepCount'] as num?)?.toInt() ?? 13,
      );

  static InspectionStatus _statusFromString(String? s) {
    switch (s) {
      case 'inProgress': return InspectionStatus.inProgress;
      case 'completed':  return InspectionStatus.completed;
      default:           return InspectionStatus.scheduled;
    }
  }

  // Returns null for unknown / missing values so callers can use
  // `inspection.outcome == null` to mean "not yet decided" (covers
  // both pre-completion rows and legacy data without the field).
  static InspectionOutcome? _outcomeFromString(String? s) {
    switch (s) {
      case 'accepted':  return InspectionOutcome.accepted;
      case 'countered': return InspectionOutcome.countered;
      case 'declined':  return InspectionOutcome.declined;
      default:          return null;
    }
  }
}

// Indian-style thousands grouping (47000 → "47,000"). Same pattern used in
// the cluster step's odometer card, kept here so the subtitle uses identical
// formatting whether it's shown on the home card or the flow header.
String _formatKm(int km) {
  final s = km.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String? _str(dynamic v) {
  if (v == null) return null;
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty || t.toLowerCase() == 'null') return null;
    return t;
  }
  return v.toString();
}

int? _int(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final cleaned = v.replaceAll(RegExp(r'[^0-9-]'), '');
    return int.tryParse(cleaned);
  }
  return null;
}
