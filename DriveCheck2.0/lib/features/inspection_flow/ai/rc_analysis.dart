import 'dart:io';

import '../../../core/services/language_service.dart';
import '../../../core/services/openai_service.dart';

/// Quality verdict from photo pre-check.
enum PhotoQuality { good, blurry, dark, partial, unreadable }

PhotoQuality _qualityFromString(String? s) {
  switch (s) {
    case 'good':       return PhotoQuality.good;
    case 'blurry':     return PhotoQuality.blurry;
    case 'dark':       return PhotoQuality.dark;
    case 'partial':    return PhotoQuality.partial;
    default:           return PhotoQuality.unreadable;
  }
}

/// Structured output from GPT-4o analysing an Indian RC book main page
/// or the new RC smart card. Every field is nullable — anything the model
/// can't read with confidence comes back null and the UI just hides it.
class RcAnalysisResult {
  final PhotoQuality quality;
  // Populated only when quality != good. Display in app-script (romanized
  // for Hindi); spoken in native-script SSML, ends with "please try again".
  final String? qualityReasonDisplay;
  final String? qualityReasonSpoken;
  // Populated only when quality == good. Display is a short confirmation;
  // spoken is SSML that names a couple of OCR'd facts so the user hears
  // the agent confirm what it read, ending with "please verify and tap
  // Next" in their language.
  final String? successMessageDisplay;
  final String? successMessageSpoken;

  // Identity
  final String? registrationNumber;
  final String? rcSerialNumber;
  final String? ownerName;
  final String? parentSpouseName;
  final int? ownerSerialNumber;
  final String? address;
  final String? issuingAuthority;

  // Vehicle
  final String? make;
  final String? model;
  final String? manufacturer;
  final String? vehicleClass;
  final String? bodyType;
  final String? colour;
  final String? fuelType;

  // Dates — ISO 8601 strings from the model. Kept as strings rather than
  // DateTime so we can faithfully echo "YYYY-MM" (manufacturing month/year)
  // and the literal "OTT" for one-time-tax without losing precision.
  final String? manufacturingDate;
  final String? registrationDate;
  final String? registrationValidUpto;
  final String? taxPaidUpto;

  // Mechanical
  final String? chassisNumber;
  final String? engineNumber;
  final int? cubicCapacityCc;
  final int? cylinders;

  // Capacity / weights
  final int? seatingCapacity;
  final int? standingCapacity;
  final int? unladenWeightKg;
  final int? grossVehicleWeightKg;
  final int? wheelbaseMm;

  // Commercial
  final String? purpose;
  final String? hypothecatedTo;

  const RcAnalysisResult({
    required this.quality,
    this.qualityReasonDisplay,
    this.qualityReasonSpoken,
    this.successMessageDisplay,
    this.successMessageSpoken,
    this.registrationNumber,
    this.rcSerialNumber,
    this.ownerName,
    this.parentSpouseName,
    this.ownerSerialNumber,
    this.address,
    this.issuingAuthority,
    this.make,
    this.model,
    this.manufacturer,
    this.vehicleClass,
    this.bodyType,
    this.colour,
    this.fuelType,
    this.manufacturingDate,
    this.registrationDate,
    this.registrationValidUpto,
    this.taxPaidUpto,
    this.chassisNumber,
    this.engineNumber,
    this.cubicCapacityCc,
    this.cylinders,
    this.seatingCapacity,
    this.standingCapacity,
    this.unladenWeightKg,
    this.grossVehicleWeightKg,
    this.wheelbaseMm,
    this.purpose,
    this.hypothecatedTo,
  });

  /// Minimum bar for "we can proceed" — RC plate must be readable. Every
  /// other field is treated as nice-to-have and may be null without
  /// blocking the user.
  bool get isUsable => quality == PhotoQuality.good && registrationNumber != null;

  factory RcAnalysisResult.fromJson(Map<String, dynamic> j) => RcAnalysisResult(
        quality: _qualityFromString(j['quality'] as String?),
        qualityReasonDisplay: _str(j['qualityReasonDisplay']),
        qualityReasonSpoken: _str(j['qualityReasonSpoken']),
        successMessageDisplay: _str(j['successMessageDisplay']),
        successMessageSpoken: _str(j['successMessageSpoken']),
        registrationNumber: _str(j['registrationNumber']),
        rcSerialNumber: _str(j['rcSerialNumber']),
        ownerName: _str(j['ownerName']),
        parentSpouseName: _str(j['parentSpouseName']),
        ownerSerialNumber: _int(j['ownerSerialNumber']),
        address: _str(j['address']),
        issuingAuthority: _str(j['issuingAuthority']),
        make: _str(j['make']),
        model: _str(j['model']),
        manufacturer: _str(j['manufacturer']),
        vehicleClass: _str(j['vehicleClass']),
        bodyType: _str(j['bodyType']),
        colour: _str(j['colour']),
        fuelType: _str(j['fuelType']),
        manufacturingDate: _str(j['manufacturingDate']),
        registrationDate: _str(j['registrationDate']),
        registrationValidUpto: _str(j['registrationValidUpto']),
        taxPaidUpto: _str(j['taxPaidUpto']),
        chassisNumber: _str(j['chassisNumber']),
        engineNumber: _str(j['engineNumber']),
        cubicCapacityCc: _int(j['cubicCapacityCc']),
        cylinders: _int(j['cylinders']),
        seatingCapacity: _int(j['seatingCapacity']),
        standingCapacity: _int(j['standingCapacity']),
        unladenWeightKg: _int(j['unladenWeightKg']),
        grossVehicleWeightKg: _int(j['grossVehicleWeightKg']),
        wheelbaseMm: _int(j['wheelbaseMm']),
        purpose: _str(j['purpose']),
        hypothecatedTo: _str(j['hypothecatedTo']),
      );

  /// Flat key→value map for the backend's `data` payload on
  /// /inspections/{id}/steps/{stepId}. Skips null fields so the row stays
  /// compact and we don't pollute downstream consumers with empty keys.
  Map<String, dynamic> toBackendData() {
    final m = <String, dynamic>{
      'qualityReasonDisplay': qualityReasonDisplay,
      'qualityReasonSpoken': qualityReasonSpoken,
      'successMessageDisplay': successMessageDisplay,
      'successMessageSpoken': successMessageSpoken,
      'registrationNumber': registrationNumber,
      'rcSerialNumber': rcSerialNumber,
      'ownerName': ownerName,
      'parentSpouseName': parentSpouseName,
      'ownerSerialNumber': ownerSerialNumber,
      'address': address,
      'issuingAuthority': issuingAuthority,
      'make': make,
      'model': model,
      'manufacturer': manufacturer,
      'vehicleClass': vehicleClass,
      'bodyType': bodyType,
      'colour': colour,
      'fuelType': fuelType,
      'manufacturingDate': manufacturingDate,
      'registrationDate': registrationDate,
      'registrationValidUpto': registrationValidUpto,
      'taxPaidUpto': taxPaidUpto,
      'chassisNumber': chassisNumber,
      'engineNumber': engineNumber,
      'cubicCapacityCc': cubicCapacityCc,
      'cylinders': cylinders,
      'seatingCapacity': seatingCapacity,
      'standingCapacity': standingCapacity,
      'unladenWeightKg': unladenWeightKg,
      'grossVehicleWeightKg': grossVehicleWeightKg,
      'wheelbaseMm': wheelbaseMm,
      'purpose': purpose,
      'hypothecatedTo': hypothecatedTo,
    };
    m.removeWhere((_, v) => v == null);
    return m;
  }
}

// GPT sometimes returns numbers as strings ("1248") and vice versa. These
// coercions absorb both shapes; anything else (empty string, "null",
// non-numeric) collapses to null.
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

/// Short, status-style example for [qualityReasonDisplay] — uses the
/// script the app actually renders (romanized for Hindi, native for
/// Telugu/Bengali, English for English).
String _qualityReasonDisplayExample(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english: return 'Photo is too dark';
    case AppLanguage.hindi:   return 'फ़ोटो धुंधली है';
    case AppLanguage.telugu:  return 'ఫోటో మసకగా ఉంది';
    case AppLanguage.bengali: return 'ছবিটা ঝাপসা';
  }
}

/// Conversational TTS example for [qualityReasonSpoken] in SSML so
/// ElevenLabs can apply proper pacing. `<break>` is the most reliably
/// honoured tag across the multilingual model; `<speak>` wraps the whole
/// utterance; other tags (prosody, emphasis) are deliberately omitted
/// because they're inconsistently supported.
String _qualityReasonSpokenExample(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english:
      return '<speak>The photo looks a little dark. <break time="400ms"/> Please try again with better lighting.</speak>';
    case AppLanguage.hindi:
      return '<speak>तस्वीर थोड़ी धुंधली है। <break time="400ms"/> कृपया फिर से कोशिश करें।</speak>';
    case AppLanguage.telugu:
      return '<speak>ఫోటో కొంచెం మసకగా ఉంది. <break time="400ms"/> దయచేసి మళ్ళీ ప్రయత్నించండి.</speak>';
    case AppLanguage.bengali:
      return '<speak>ছবিটা একটু ঝাপসা। <break time="400ms"/> অনুগ্রহ করে আবার চেষ্টা করুন।</speak>';
  }
}

/// Short on-screen confirmation example for [successMessageDisplay] —
/// uses the script the app actually renders.
String _successMessageDisplayExample(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english: return 'RC details read';
    case AppLanguage.hindi:   return 'RC की जानकारी मिल गई';
    case AppLanguage.telugu:  return 'RC వివరాలు చదవబడ్డాయి';
    case AppLanguage.bengali: return 'RC বিবরণ পড়া হয়েছে';
  }
}

/// Conversational SSML success example for [successMessageSpoken].
/// Always names 1-2 OCR'd facts and ends with the "please verify and tap
/// Next" closer in the matching language.
String _successMessageSpokenExample(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english:
      return '<speak>Got it. I read the registration as HR03Z6814 for a Maruti Vitara Brezza. <break time="400ms"/> Please verify the details and tap Next.</speak>';
    case AppLanguage.hindi:
      return '<speak>मिल गया। रजिस्ट्रेशन HR03Z6814 है, मारुति विटारा ब्रेज़ा। <break time="400ms"/> कृपया जानकारी जाँचकर Next दबाएँ।</speak>';
    case AppLanguage.telugu:
      return '<speak>దొరికింది. రిజిస్ట్రేషన్ HR03Z6814, మారుతి విటారా బ్రెజ్జా. <break time="400ms"/> దయచేసి వివరాలను తనిఖీ చేసి Next నొక్కండి.</speak>';
    case AppLanguage.bengali:
      return '<speak>পেয়েছি। রেজিস্ট্রেশন HR03Z6814, মারুতি ভিটারা ব্রেজ্জা। <break time="400ms"/> অনুগ্রহ করে বিবরণ যাচাই করে Next চাপুন।</speak>';
  }
}

/// Tells the model which script to use for the *display* field. Hindi is
/// the odd one out: the app shows romanized Hindi (Latin letters) even
/// though the language is Hindi.
String _displayScriptInstruction(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english: return 'Latin (English alphabet)';
    // The AI chat bubble shows text in the same native script the audio
    // speaks, so the on-screen line and the spoken line match exactly.
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

String _buildRcPrompt(AppLanguage lang) => '''
You are an OCR + structured-extraction engine analysing a photograph of an
Indian Registration Certificate (RC) — either the laminated RC book main
page or the new RC smart card. The photo may contain other documents
(driving licence, Aadhaar, etc.); ignore those and extract ONLY the RC.

Return a single valid JSON object with this exact shape. No prose, no
markdown fences, no commentary. Use null (not the string "null", not
empty string) for any field you cannot read with confidence.

{
  "quality": "good" | "blurry" | "dark" | "partial" | "unreadable",
  "qualityReasonDisplay":  "<short on-screen summary, see rule 8a — null when quality=='good'>",
  "qualityReasonSpoken":   "<TTS SSML, see rule 8b — null when quality=='good'>",
  "successMessageDisplay": "<short on-screen confirmation, see rule 8c — null when quality!='good'>",
  "successMessageSpoken":  "<TTS SSML naming 1-2 OCR'd facts, see rule 8d — null when quality!='good'>",

  "registrationNumber":  "<RC plate number, no spaces, uppercase, e.g. HR03Z6814>",
  "rcSerialNumber":      "<serial printed on the card itself, e.g. HR5017519>",
  "ownerName":           "<owner name in Title Case>",
  "parentSpouseName":    "<S/D/W of, in Title Case>",
  "ownerSerialNumber":   <integer, e.g. 1>,
  "address":             "<single-line address as printed, commas between parts>",
  "issuingAuthority":    "<RTO or SDM name as printed>",

  "make":          "<brand in Title Case, e.g. Maruti>",
  "model":         "<full model + variant in Title Case, e.g. Vitara Brezza ZDI>",
  "manufacturer":  "<full company name, e.g. Maruti Suzuki India Ltd>",
  "vehicleClass":  "<e.g. Motor Car, Motorcycle, Goods Carrier>",
  "bodyType":      "<e.g. Saloon Car, Hatchback, SUV>",
  "colour":        "<vehicle colour in Title Case, e.g. Granite Grey>",
  "fuelType":      "Petrol" | "Diesel" | "CNG" | "Electric" | "Hybrid" | "LPG" | null,

  "manufacturingDate":     "<YYYY-MM if only month/year printed, else YYYY-MM-DD>",
  "registrationDate":      "<YYYY-MM-DD>",
  "registrationValidUpto": "<YYYY-MM-DD>",
  "taxPaidUpto":           "<YYYY-MM-DD, or 'OTT' if one-time-tax (lifetime)>",

  "chassisNumber":  "<as printed, no spaces, e.g. MA3NYFB1SKL606233>",
  "engineNumber":   "<as printed, e.g. D13A-3573665>",
  "cubicCapacityCc": <integer cc, e.g. 1248>,
  "cylinders":       <integer, e.g. 4>,

  "seatingCapacity":      <integer, includes driver, e.g. 5>,
  "standingCapacity":     <integer, usually 0 for cars>,
  "unladenWeightKg":      <integer kilograms>,
  "grossVehicleWeightKg": <integer kilograms (RLW)>,
  "wheelbaseMm":          <integer millimetres>,

  "purpose":         "<e.g. New, HPA, Private, Transport>",
  "hypothecatedTo":  "<financier name, or null if owned outright>"
}

Rules:
1. quality = "good" ONLY if the RC plate number AND chassis number are both
   sharply readable. If either is fuzzy, downgrade quality.
2. If the image is not an Indian RC at all, set quality = "unreadable" and
   every other field to null.
3. Normalise dates to ISO 8601 (YYYY-MM-DD). Common Indian formats to
   convert: 25/01/2020, 25-01-2020, 25-Jan-2020, 25.01.2020 -> 2020-01-25.
4. Strip currency, units, and whitespace from numbers (e.g. "1185 kg" -> 1185).
5. Title Case for names, places, colours. Uppercase for registration
   numbers, chassis, engine numbers, and state codes.
6. If a field is printed but illegible, use null — never guess.
7. "OTT" / "OT" / "OneTime" / "Life Time" under tax -> "OTT" (literal string).
8. Feedback fields. EXACTLY ONE pair is populated per response based on
   `quality`:
     - quality == "good"  → fill successMessageDisplay + successMessageSpoken,
                            leave qualityReason* null.
     - quality != "good"  → fill qualityReasonDisplay + qualityReasonSpoken,
                            leave successMessage* null.

   8a. qualityReasonDisplay — appears on screen when the photo failed.
       Short (≤ 8 words), status-style, no greeting, no "please". Use the
       script the app displays in: ${_displayScriptInstruction(lang)}.
       Examples: "${_qualityReasonDisplayExample(lang)}"

   8b. qualityReasonSpoken — fed to ElevenLabs text-to-speech. MUST be
       valid SSML for proper pacing and natural delivery. Format rules:
         - Wrap the whole utterance in <speak> ... </speak>.
         - Insert one <break time="350ms"/> or <break time="400ms"/>
           between the "what went wrong" sentence and the "please try
           again" closer so the audio has a natural pause.
         - DO NOT use other tags (<prosody>, <emphasis>, <say-as>, etc.)
           — the multilingual model honours <break> reliably; other tags
           are inconsistent and waste tokens.
         - Use natural punctuation inside the SSML. The text between
           tags must be 1-2 sentences in ${lang.englishName} written in
           ${_scriptName(lang)}, conversational like a helpful colleague
           speaking. First sentence: what went wrong. Then a polite
           "please try again" closer in the same language so the user
           hears what to do next.
       Example: ${_qualityReasonSpokenExample(lang)}
       Adapt to the actual problem ("dark", "blurry", "only half the card
       visible", "RC is upside down", etc.) — do not copy verbatim, but
       keep the <speak>/<break> structure and the trailing retry phrasing.

   8c. successMessageDisplay — appears on screen when the photo succeeded.
       Short (≤ 10 words), status-style. Use ${_displayScriptInstruction(lang)}.
       Examples: "${_successMessageDisplayExample(lang)}"

   8d. successMessageSpoken — fed to ElevenLabs TTS. Same SSML rules as
       8b. Must NAME 1-2 concrete facts that you just extracted (typically
       the registration number plus the make + model, OR the owner name)
       so the user hears the agent confirm what was read. Then end with a
       polite "please verify the details and tap Next" closer in the same
       language. Use the same <speak>/<break> structure as 8b.
       Example: ${_successMessageSpokenExample(lang)}
       Adapt to the actual extracted data — do not copy verbatim. Keep
       the trailing "please verify and tap Next" phrasing.
''';

class RcAnalyzer {
  final OpenAiService _ai;
  RcAnalyzer([OpenAiService? ai]) : _ai = ai ?? OpenAiService();

  Future<RcAnalysisResult> analyze(
    File image, {
    required AppLanguage language,
  }) async {
    final json = await _ai.analyzeImage(
      prompt: _buildRcPrompt(language),
      imageFile: image,
    );
    return RcAnalysisResult.fromJson(json);
  }
}
