import 'dart:io';

import '../../../core/services/language_service.dart';
import '../../../core/services/openai_service.dart';
import 'rc_analysis.dart'; // reuse PhotoQuality enum

/// Where the fuel needle / digital gauge sits. Quantised to six buckets
/// so the value is comparable across analog and digital clusters without
/// the model having to invent a percentage.
enum FuelLevel { empty, low, quarter, half, threeQuarter, full }

/// Cluster construction style — informational, doesn't affect price but
/// useful context on the inspection report.
enum ClusterType { analog, digital, hybrid }

/// Severity for visual styling on the chip.
enum WarningSeverity { critical, caution, info }

/// Canonical IDs the OCR model is allowed to return. Names match the
/// JSON strings the prompt instructs the model to use — `Enum.name`
/// roundtrips. `unknown` is the model's escape hatch for symbols it
/// can't confidently classify; the chip rendering hides unknowns.
enum WarningLight {
  checkEngine,
  batteryCharging,
  engineOilPressure,
  brakeWarning,
  abs,
  airbag,
  tirePressure,
  engineTemperature,
  seatbelt,
  lowFuel,
  doorOpen,
  glowPlug,
  tractionControl,
  powerSteering,
  unknown;

  /// Severity tier used to pick chip colour. Critical = red (driver
  /// must act now); caution = yellow (service soon); info = neutral.
  WarningSeverity get severity {
    switch (this) {
      case WarningLight.batteryCharging:
      case WarningLight.engineOilPressure:
      case WarningLight.brakeWarning:
      case WarningLight.airbag:
      case WarningLight.engineTemperature:
      case WarningLight.seatbelt:
        return WarningSeverity.critical;
      case WarningLight.checkEngine:
      case WarningLight.abs:
      case WarningLight.tirePressure:
      case WarningLight.lowFuel:
      case WarningLight.doorOpen:
      case WarningLight.glowPlug:
      case WarningLight.tractionControl:
      case WarningLight.powerSteering:
        return WarningSeverity.caution;
      case WarningLight.unknown:
        return WarningSeverity.info;
    }
  }

  /// Short label for the on-screen chip. English-only for now — Hindi
  /// jockeys learn these symbols by sight, the chip's role is mostly
  /// to disambiguate the icon, not be the primary content.
  String get displayName {
    switch (this) {
      case WarningLight.checkEngine:       return 'Check engine';
      case WarningLight.batteryCharging:   return 'Battery';
      case WarningLight.engineOilPressure: return 'Oil pressure';
      case WarningLight.brakeWarning:      return 'Brake';
      case WarningLight.abs:               return 'ABS';
      case WarningLight.airbag:            return 'Airbag';
      case WarningLight.tirePressure:      return 'Tyre pressure';
      case WarningLight.engineTemperature: return 'Engine temp';
      case WarningLight.seatbelt:          return 'Seatbelt';
      case WarningLight.lowFuel:           return 'Low fuel';
      case WarningLight.doorOpen:          return 'Door open';
      case WarningLight.glowPlug:          return 'Glow plug';
      case WarningLight.tractionControl:   return 'Traction control';
      case WarningLight.powerSteering:     return 'Power steering';
      case WarningLight.unknown:           return 'Other';
    }
  }
}

/// Structured output from GPT-4o reading an Indian car instrument
/// cluster. Same SSML-bearing feedback fields as [RcAnalysisResult] so
/// the same assistant-bubble UI / TTS pipeline works unchanged.
class InstrumentClusterResult {
  final PhotoQuality quality;
  final String? qualityReasonDisplay;
  final String? qualityReasonSpoken;
  final String? successMessageDisplay;
  final String? successMessageSpoken;

  final int? odometerKm;
  final double? tripMeterKm;
  final FuelLevel? fuelLevel;
  final int? tachometerRpm;
  final List<WarningLight> warningLights;
  final ClusterType? clusterType;

  const InstrumentClusterResult({
    required this.quality,
    this.qualityReasonDisplay,
    this.qualityReasonSpoken,
    this.successMessageDisplay,
    this.successMessageSpoken,
    this.odometerKm,
    this.tripMeterKm,
    this.fuelLevel,
    this.tachometerRpm,
    this.warningLights = const [],
    this.clusterType,
  });

  /// Bar for "we can proceed": odometer must be readable. The other
  /// fields are nice-to-haves and may be null without blocking the user.
  bool get isUsable => quality == PhotoQuality.good && odometerKm != null;

  factory InstrumentClusterResult.fromJson(Map<String, dynamic> j) =>
      InstrumentClusterResult(
        quality: _qualityFromString(j['quality'] as String?),
        qualityReasonDisplay: _str(j['qualityReasonDisplay']),
        qualityReasonSpoken: _str(j['qualityReasonSpoken']),
        successMessageDisplay: _str(j['successMessageDisplay']),
        successMessageSpoken: _str(j['successMessageSpoken']),
        odometerKm: _int(j['odometerKm']),
        tripMeterKm: _double(j['tripMeterKm']),
        fuelLevel: _fuelFromString(_str(j['fuelLevel'])),
        tachometerRpm: _int(j['tachometerRpm']),
        warningLights: _warningsFromJson(j['warningLights']),
        clusterType: _clusterTypeFromString(_str(j['clusterType'])),
      );

  Map<String, dynamic> toBackendData() {
    final m = <String, dynamic>{
      'qualityReasonDisplay': qualityReasonDisplay,
      'qualityReasonSpoken': qualityReasonSpoken,
      'successMessageDisplay': successMessageDisplay,
      'successMessageSpoken': successMessageSpoken,
      'odometerKm': odometerKm,
      'tripMeterKm': tripMeterKm,
      'fuelLevel': fuelLevel?.name,
      'tachometerRpm': tachometerRpm,
      'warningLights': warningLights.map((w) => w.name).toList(),
      'clusterType': clusterType?.name,
    };
    m.removeWhere((_, v) => v == null);
    return m;
  }
}

// ---- JSON coercion helpers (lenient — GPT returns inconsistent types) ----

PhotoQuality _qualityFromString(String? s) {
  switch (s) {
    case 'good':       return PhotoQuality.good;
    case 'blurry':     return PhotoQuality.blurry;
    case 'dark':       return PhotoQuality.dark;
    case 'partial':    return PhotoQuality.partial;
    default:           return PhotoQuality.unreadable;
  }
}

FuelLevel? _fuelFromString(String? s) {
  if (s == null) return null;
  for (final v in FuelLevel.values) {
    if (v.name == s) return v;
  }
  return null;
}

ClusterType? _clusterTypeFromString(String? s) {
  if (s == null) return null;
  for (final v in ClusterType.values) {
    if (v.name == s) return v;
  }
  return null;
}

List<WarningLight> _warningsFromJson(dynamic v) {
  if (v is! List) return const [];
  final out = <WarningLight>[];
  for (final item in v) {
    if (item is! String) continue;
    final match = WarningLight.values
        .where((w) => w.name == item)
        .firstOrNull;
    out.add(match ?? WarningLight.unknown);
  }
  return out;
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

double? _double(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) {
    final cleaned = v.replaceAll(RegExp(r'[^0-9.-]'), '');
    return double.tryParse(cleaned);
  }
  return null;
}

// ---- Prompt builders ----

String _qualityReasonDisplayExample(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english: return 'Cluster has glare';
    case AppLanguage.hindi:   return 'क्लस्टर पर glare है';
    case AppLanguage.telugu:  return 'క్లస్టర్‌పై మెరుపు ఉంది';
    case AppLanguage.bengali: return 'ক্লাস্টারে আলো পড়ছে';
  }
}

String _qualityReasonSpokenExample(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english:
      return '<speak>There is some glare on the cluster glass and I cannot read the kilometre reading. <break time="400ms"/> Please move slightly to one side and try again.</speak>';
    case AppLanguage.hindi:
      return '<speak>क्लस्टर के शीशे पर रोशनी पड़ रही है और किलोमीटर रीडिंग नहीं दिख रही। <break time="400ms"/> कृपया थोड़ा एक तरफ़ हटकर फिर से कोशिश करें।</speak>';
    case AppLanguage.telugu:
      return '<speak>క్లస్టర్ గ్లాస్‌పై మెరుపు ఉంది, కిలోమీటర్ రీడింగ్ స్పష్టంగా కనిపించడం లేదు. <break time="400ms"/> దయచేసి కొంచెం ప్రక్కకు మారి మళ్ళీ ప్రయత్నించండి.</speak>';
    case AppLanguage.bengali:
      return '<speak>ক্লাস্টারের কাচে আলো পড়ছে, কিলোমিটার রিডিং পড়া যাচ্ছে না। <break time="400ms"/> অনুগ্রহ করে একটু পাশে সরে আবার চেষ্টা করুন।</speak>';
  }
}

String _successMessageDisplayExample(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english: return 'Cluster read';
    case AppLanguage.hindi:   return 'क्लस्टर पढ़ लिया';
    case AppLanguage.telugu:  return 'క్లస్టర్ చదవబడింది';
    case AppLanguage.bengali: return 'ক্লাস্টার পড়া হয়েছে';
  }
}

String _successMessageSpokenExample(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english:
      return '<speak>Reading is forty-seven thousand kilometres. Fuel is half and two warning lights are on. <break time="400ms"/> Please verify the details and tap Next.</speak>';
    case AppLanguage.hindi:
      return '<speak>रीडिंग सैंतालीस हज़ार किलोमीटर है। फ्यूल आधा है और दो वार्निंग लाइट जल रही हैं। <break time="400ms"/> कृपया जानकारी जाँचकर Next दबाएँ।</speak>';
    case AppLanguage.telugu:
      return '<speak>రీడింగ్ నలభై ఏడు వేల కిలోమీటర్లు. ఫ్యూయల్ సగం ఉంది, రెండు హెచ్చరిక లైట్లు వెలుగుతున్నాయి. <break time="400ms"/> దయచేసి వివరాలను తనిఖీ చేసి Next నొక్కండి.</speak>';
    case AppLanguage.bengali:
      return '<speak>রিডিং সাতচল্লিশ হাজার কিলোমিটার। ফুয়েল অর্ধেক এবং দুটি ওয়ার্নিং লাইট জ্বলছে। <break time="400ms"/> অনুগ্রহ করে বিবরণ যাচাই করে Next চাপুন।</speak>';
  }
}

String _displayScriptInstruction(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english: return 'Latin (English alphabet)';
    // AI chat bubble shows text in the same native script as the audio.
    case AppLanguage.hindi:   return 'Devanagari (देवनागरी)';
    case AppLanguage.telugu:  return 'Telugu script (తెలుగు)';
    case AppLanguage.bengali: return 'Bengali script (বাংলা)';
  }
}

String _scriptName(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english: return 'Latin (English)';
    case AppLanguage.hindi:   return 'Devanagari (देवनागरी)';
    case AppLanguage.telugu:  return 'Telugu (తెలుగు)';
    case AppLanguage.bengali: return 'Bengali (বাংলা)';
  }
}

String _buildClusterPrompt(AppLanguage lang) => '''
You are an OCR + structured-extraction engine analysing a photograph of
the instrument cluster (dashboard) of an Indian passenger car. The
cluster may be analog (needles), digital (LCD/LED), or a hybrid. Ignore
anything outside the cluster (steering wheel, windshield, etc.).

Return a single valid JSON object with this exact shape. No prose, no
markdown fences, no commentary. Use null for any field you cannot read
with confidence. For warningLights return an empty array if none are
visibly illuminated.

{
  "quality": "good" | "blurry" | "dark" | "partial" | "unreadable",

  "qualityReasonDisplay":  "<short on-screen summary, see rule 8a — null when quality=='good'>",
  "qualityReasonSpoken":   "<TTS SSML, see rule 8b — null when quality=='good'>",
  "successMessageDisplay": "<short on-screen confirmation, see rule 8c — null when quality!='good'>",
  "successMessageSpoken":  "<TTS SSML naming odometer + 1 other fact, see rule 8d — null when quality!='good'>",

  "odometerKm":     <integer kilometres, e.g. 47000>,
  "tripMeterKm":    <decimal kilometres if a trip meter is shown, e.g. 124.6, else null>,
  "fuelLevel":      "empty" | "low" | "quarter" | "half" | "threeQuarter" | "full" | null,
  "tachometerRpm":  <integer RPM, typically 0 if engine is off>,
  "warningLights":  [ <one or more of the canonical IDs in rule 9>, ... ],
  "clusterType":    "analog" | "digital" | "hybrid" | null
}

Rules:
1. quality = "good" ONLY if the odometer reading is sharply readable.
   Other fields can be partially missing without downgrading quality.
2. If the image is not an instrument cluster at all (steering wheel only,
   dashboard wood trim, etc.), set quality = "unreadable" and every
   other field to null / empty array.
3. odometerKm is the TOTAL odometer, NOT the trip meter. They are
   usually labelled "ODO" and "TRIP". If both are shown, distinguish
   them; tripMeterKm goes in its own field.
4. Strip commas, decimals, units. "47,238 km" -> 47238.
5. If the cluster shows miles instead of kilometres (rare in India,
   common on grey-imports), convert to km: 1 mile = 1.60934 km, round
   to the nearest integer. Set qualityReasonDisplay/Spoken to note this
   only if the conversion looks unreliable (set quality accordingly).
6. fuelLevel buckets: estimate which sixth of the gauge the needle / bar
   is in. "empty" = at or below E line; "low" = between E and 1/4;
   "quarter" = roughly at 1/4; "half" = around mid; "threeQuarter" =
   between half and F; "full" = at or above F line.
7. tachometerRpm = 0 if the engine is clearly off (no idle, needle at
   rest). If the engine is running this matters for inspection; record
   the actual reading.
8. Feedback fields. EXACTLY ONE pair is populated per response based on
   `quality`:
     - quality == "good"  → fill successMessageDisplay + successMessageSpoken,
                            leave qualityReason* null.
     - quality != "good"  → fill qualityReasonDisplay + qualityReasonSpoken,
                            leave successMessage* null.

   8a. qualityReasonDisplay — short (≤ 8 words), status-style, no
       "please". Use ${_displayScriptInstruction(lang)}.
       Example: "${_qualityReasonDisplayExample(lang)}"

   8b. qualityReasonSpoken — SSML for ElevenLabs TTS:
         - Wrap in <speak>...</speak>.
         - One <break time="400ms"/> between the problem statement and the
           "please try again" closer.
         - DO NOT use other SSML tags.
         - 1-2 sentences in ${lang.englishName} written in ${_scriptName(lang)},
           conversational. First sentence: what went wrong (be specific
           — "glare on the glass", "screen off, please turn ignition on",
           "only half the cluster visible"). End with a polite "please
           try again" closer in the same language.
       Example: ${_qualityReasonSpokenExample(lang)}

   8c. successMessageDisplay — short (≤ 10 words), status-style. Use
       ${_displayScriptInstruction(lang)}.
       Example: "${_successMessageDisplayExample(lang)}"

   8d. successMessageSpoken — SSML for ElevenLabs TTS. Same structural
       rules as 8b. MUST name the odometer reading aloud (use natural
       number form, e.g. "forty-seven thousand kilometres", not "47000
       k m"), PLUS one secondary fact: fuel level if known, or the count
       of warning lights if any are on. Then end with a polite "please
       verify the details and tap Next" closer in the same language.
       Example: ${_successMessageSpokenExample(lang)}
       Adapt to the actual reading — do not copy verbatim.

9. warningLights — return ONLY IDs from this fixed allowlist. Anything
   illuminated that doesn't match an entry goes in as "unknown" once.
   Empty array if no warnings are lit.

   - checkEngine          (yellow MIL, "engine"-shaped symbol)
   - batteryCharging      (red battery icon)
   - engineOilPressure    (red oil-can with drip)
   - brakeWarning         (red circle with !, or "BRAKE" text)
   - abs                  (yellow circle with "ABS")
   - airbag               (red person + airbag)
   - tirePressure         (yellow tyre cross-section with !)
   - engineTemperature    (red thermometer in liquid)
   - seatbelt             (red seatbelt person)
   - lowFuel              (yellow fuel pump)
   - doorOpen             (red car with open door)
   - glowPlug             (yellow coil symbol, diesel only)
   - tractionControl      (yellow car with skid lines)
   - powerSteering        (yellow steering wheel + !)
   - unknown              (any lit symbol you can't confidently classify)

   DO NOT include lights that are off / unlit, even if you can see the
   icon outline. Only lights that are actively glowing/illuminated.
''';

class InstrumentClusterAnalyzer {
  final OpenAiService _ai;
  InstrumentClusterAnalyzer([OpenAiService? ai]) : _ai = ai ?? OpenAiService();

  Future<InstrumentClusterResult> analyze(
    File image, {
    required AppLanguage language,
  }) async {
    final json = await _ai.analyzeImage(
      prompt: _buildClusterPrompt(language),
      imageFile: image,
    );
    return InstrumentClusterResult.fromJson(json);
  }
}
