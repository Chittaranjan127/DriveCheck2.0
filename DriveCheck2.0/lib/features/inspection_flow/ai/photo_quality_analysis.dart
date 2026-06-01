import 'dart:io';

import '../../../core/services/language_service.dart';
import '../../../core/services/openai_service.dart';

/// Quality verdict from a generic per-step photo pre-check. Mirrors
/// [PhotoQuality] from `rc_analysis.dart` but adds `wrongSubject` —
/// the freeform exterior / interior steps don't extract data, so the
/// only way to know the user pointed the camera at the right thing
/// is to ask the model.
enum PhotoQuality {
  good,
  blurry,
  dark,
  partial,
  wrongSubject,
  unreadable,
}

PhotoQuality _qualityFromString(String? s) {
  switch (s) {
    case 'good':         return PhotoQuality.good;
    case 'blurry':       return PhotoQuality.blurry;
    case 'dark':         return PhotoQuality.dark;
    case 'partial':      return PhotoQuality.partial;
    case 'wrongSubject': return PhotoQuality.wrongSubject;
    default:             return PhotoQuality.unreadable;
  }
}

/// Verdict + conversational feedback for a single non-OCR photo step
/// (engine bay, exterior sides, interior, tyres, etc.). Always has
/// EITHER a quality-reason pair (bad photo) OR a success-message pair
/// (good photo) — never both, never neither.
class PhotoQualityResult {
  final PhotoQuality quality;
  // Populated when quality != good.
  final String? qualityReasonDisplay;
  final String? qualityReasonSpoken;
  // Populated when quality == good.
  final String? successMessageDisplay;
  final String? successMessageSpoken;

  const PhotoQualityResult({
    required this.quality,
    this.qualityReasonDisplay,
    this.qualityReasonSpoken,
    this.successMessageDisplay,
    this.successMessageSpoken,
  });

  bool get isUsable => quality == PhotoQuality.good;

  factory PhotoQualityResult.fromJson(Map<String, dynamic> j) =>
      PhotoQualityResult(
        quality: _qualityFromString(j['quality'] as String?),
        qualityReasonDisplay: _str(j['qualityReasonDisplay']),
        qualityReasonSpoken: _str(j['qualityReasonSpoken']),
        successMessageDisplay: _str(j['successMessageDisplay']),
        successMessageSpoken: _str(j['successMessageSpoken']),
      );

  /// What we persist on the InspectionSteps row's `aiAnalysis` field so
  /// the persisted view can replay the original verdict without re-
  /// calling the model on revisit.
  Map<String, dynamic> toAiAnalysis() => {
        'quality': quality.name,
        if (qualityReasonDisplay != null) 'qualityReasonDisplay': qualityReasonDisplay,
        if (qualityReasonSpoken != null) 'qualityReasonSpoken': qualityReasonSpoken,
        if (successMessageDisplay != null) 'successMessageDisplay': successMessageDisplay,
        if (successMessageSpoken != null) 'successMessageSpoken': successMessageSpoken,
      };
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

/// Short on-screen example for [qualityReasonDisplay], in the script
/// the app actually renders for [lang].
String _qualityReasonDisplayExample(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english: return 'Photo is blurry';
    case AppLanguage.hindi:   return 'फ़ोटो धुंधली है';
    case AppLanguage.telugu:  return 'ఫోటో మసకగా ఉంది';
    case AppLanguage.bengali: return 'ছবিটা ঝাপসা';
  }
}

/// SSML example for the spoken bad-quality message — matches the RC /
/// Cluster format so the bubble's audio cadence is consistent across
/// every step in the flow.
String _qualityReasonSpokenExample(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english:
      return '<speak>The photo looks a little blurry. <break time="400ms"/> Please hold the phone steady and try again.</speak>';
    case AppLanguage.hindi:
      return '<speak>तस्वीर थोड़ी धुंधली है। <break time="400ms"/> कृपया फोन को स्थिर रखकर फिर से कोशिश करें।</speak>';
    case AppLanguage.telugu:
      return '<speak>ఫోటో కొంచెం మసకగా ఉంది. <break time="400ms"/> ఫోన్‌ను స్థిరంగా పట్టుకుని మళ్ళీ ప్రయత్నించండి.</speak>';
    case AppLanguage.bengali:
      return '<speak>ছবিটা একটু ঝাপসা। <break time="400ms"/> ফোনটা স্থির রেখে আবার চেষ্টা করুন।</speak>';
  }
}

String _successMessageDisplayExample(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english: return 'Photo looks good';
    case AppLanguage.hindi:   return 'फ़ोटो अच्छी है';
    case AppLanguage.telugu:  return 'ఫోటో బాగుంది';
    case AppLanguage.bengali: return 'ছবিটা ভালো হয়েছে';
  }
}

String _successMessageSpokenExample(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english:
      return '<speak>Got it — clear photo of the front of the car. <break time="400ms"/> Please tap Next to continue.</speak>';
    case AppLanguage.hindi:
      return '<speak>मिल गया — गाड़ी के सामने की साफ़ photo। <break time="400ms"/> कृपया Next दबाएँ।</speak>';
    case AppLanguage.telugu:
      return '<speak>బాగుంది — కారు ముందు భాగం స్పష్టంగా ఉంది. <break time="400ms"/> దయచేసి Next నొక్కండి.</speak>';
    case AppLanguage.bengali:
      return '<speak>পেয়েছি — গাড়ির সামনের পরিষ্কার ছবি। <break time="400ms"/> অনুগ্রহ করে Next চাপুন।</speak>';
  }
}

String _displayScriptInstruction(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english: return 'Latin (English alphabet)';
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

String _languageEnglishName(AppLanguage lang) {
  switch (lang) {
    case AppLanguage.english: return 'English';
    case AppLanguage.hindi:   return 'Hindi';
    case AppLanguage.telugu:  return 'Telugu';
    case AppLanguage.bengali: return 'Bengali';
  }
}

String _buildPrompt({
  required AppLanguage lang,
  required String subjectShort,
  required String subjectDescription,
}) => '''
You are a photo quality and subject-match verifier for a car-inspection
app. Before reaching this step the jockey was shown an EXAMPLE image
of what the capture should look like — a brief auto-dismissing modal
with the reference photo + a short instruction. Your job is to judge
the photo they just took against that reference. The expected
subject is **$subjectShort**, specifically:

    $subjectDescription

Look at the supplied image and return a single valid JSON object with
this exact shape. No prose, no markdown fences, no commentary.

{
  "quality": "good" | "blurry" | "dark" | "partial" | "wrongSubject" | "unreadable",
  "qualityReasonDisplay":  "<short on-screen reason, see rule 4a — null when quality=='good'>",
  "qualityReasonSpoken":   "<SSML TTS line, see rule 4b — null when quality=='good'>",
  "successMessageDisplay": "<short on-screen confirmation, see rule 4c — null when quality!='good'>",
  "successMessageSpoken":  "<SSML TTS line, see rule 4d — null when quality!='good'>"
}

Rules:
1. quality decision tree (apply in order, stop at first match):
     - The expected subject is **not** the dominant element of the
       frame → "wrongSubject".
     - Significant motion blur or out-of-focus softness on the subject
       → "blurry".
     - Underexposed / too dark to verify details → "dark".
     - Subject is cut off at the edges (more than ~15% missing) →
       "partial".
     - Image is corrupt, all-black, all-white, or otherwise impossible
       to evaluate → "unreadable".
     - Otherwise → "good".

2. Be reasonably lenient — these are jockeys in the field, not pro
   photographers. A small amount of glare, mild compression, or a
   non-centred subject is fine if the relevant features are clearly
   visible. Reject only when a human reviewer would also reject.

3. Do NOT extract or describe any vehicle data. The only output is the
   quality verdict + a single feedback pair (rules 4a–4d below).

4. Feedback fields. EXACTLY ONE pair is populated per response based on
   `quality`:
     - quality == "good"  → fill successMessageDisplay + successMessageSpoken,
                            leave qualityReason* null.
     - quality != "good"  → fill qualityReasonDisplay + qualityReasonSpoken,
                            leave successMessage* null.

   4a. qualityReasonDisplay — appears on screen when the photo failed.
       Short (≤ 8 words), status-style, no greeting. Use the script the
       app displays in: ${_displayScriptInstruction(lang)}.
       Example: "${_qualityReasonDisplayExample(lang)}"

   4b. qualityReasonSpoken — fed to ElevenLabs TTS. MUST be valid SSML.
       Format rules:
         - Wrap in <speak> ... </speak>.
         - Insert one <break time="350ms"/> or <break time="400ms"/>
           between the "what went wrong" sentence and the "please try
           again" closer.
         - DO NOT use other tags (<prosody>, <emphasis>, <say-as>, etc.)
           — the multilingual model honours <break> reliably; other tags
           are inconsistent.
         - Text between tags is 1-2 sentences in ${_languageEnglishName(lang)}
           written in ${_scriptName(lang)}, conversational like a
           helpful colleague speaking to the jockey. First sentence:
           what went wrong AND nudge the jockey to recall the example
           image they just saw (phrasing like "the photo doesn't
           match the example" / "उदाहरण जैसा नहीं आया" / etc. — adapt
           the wording to the specific problem). For quality=="wrongSubject"
           also name what was expected. Then a polite "please try
           again" closer.
       Example: ${_qualityReasonSpokenExample(lang)}
       Adapt to the actual problem — do not copy verbatim. Reference
       to "the example" is a hint to the jockey, not a literal
       requirement; skip it when the problem is purely technical
       (e.g. all-black image).

   4c. successMessageDisplay — appears on screen when the photo
       succeeded. Short (≤ 8 words). Use ${_displayScriptInstruction(lang)}.
       Example: "${_successMessageDisplayExample(lang)}"

   4d. successMessageSpoken — fed to ElevenLabs TTS. Same SSML rules as
       4b. Briefly confirm what was captured ("clear photo of the front
       of the car") in ${_scriptName(lang)}, then end with a polite
       "please tap Next" closer in the same language.
       Example: ${_successMessageSpokenExample(lang)}
       Adapt to the actual subject — do not copy verbatim.
''';

class PhotoQualityAnalyzer {
  final OpenAiService _ai;
  PhotoQualityAnalyzer([OpenAiService? ai]) : _ai = ai ?? OpenAiService();

  /// Analyses [image] against an expected subject. [subjectShort] is the
  /// 2-4 word label spoken back in error messages ("the front of the
  /// car"); [subjectDescription] is the longer hint fed to the model
  /// detailing exactly what should be visible.
  Future<PhotoQualityResult> analyze(
    File image, {
    required AppLanguage language,
    required String subjectShort,
    required String subjectDescription,
  }) async {
    final json = await _ai.analyzeImage(
      prompt: _buildPrompt(
        lang: language,
        subjectShort: subjectShort,
        subjectDescription: subjectDescription,
      ),
      imageFile: image,
    );
    return PhotoQualityResult.fromJson(json);
  }
}

/// Per-step subject hints fed to [PhotoQualityAnalyzer]. Kept in one
/// place so adding a new photo step is a single-table edit; the rest
/// of the pipeline is fully generic.
class StepPhotoSubjects {
  /// Returns null if [stepId] doesn't need photo-quality analysis (the
  /// caller should skip the analyse phase and just upload).
  static ({String shortLabel, String description})? forStep(String stepId) {
    switch (stepId) {
      case 'engine_bay':
        return (
          shortLabel: 'the engine bay',
          description:
              'The open engine bay of a car. The bonnet should be raised and the '
              'engine block (cylinder head, valve cover, air intake, belts) should '
              'be clearly visible from above. A close-up of just one part of the '
              'engine is acceptable; a photo of the closed bonnet from outside is NOT.',
        );
      case 'front_full':
        return (
          shortLabel: 'the front of the car',
          description:
              'The full front of a car photographed from a few steps back. Both '
              'headlights, the grille, the front bumper, and ideally the bonnet '
              'should be visible in one frame. A photo of just a headlight or '
              'just the grille is "partial".',
        );
      case 'lhs_full':
        return (
          shortLabel: 'the left side of the car',
          description:
              'The full left side of a car (driver-side in India: right-hand-drive, '
              'so the LEFT side is the passenger side) photographed from a few steps '
              'back. Both wheels on that side, both doors, and the side body line '
              'should be visible in one frame.',
        );
      case 'rhs_full':
        return (
          shortLabel: 'the right side of the car',
          description:
              'The full right side of a car (driver side in India) photographed '
              'from a few steps back. Both wheels on that side, both doors, and '
              'the side body line should be visible in one frame.',
        );
      case 'rear_full':
        return (
          shortLabel: 'the rear of the car',
          description:
              'The full rear of a car photographed from a few steps behind. The '
              'boot/tailgate, both tail lights, and the rear bumper should all be '
              'visible in one frame.',
        );
      case 'roof':
        return (
          shortLabel: 'the roof of the car',
          description:
              'The roof of a car, shot from an angled high position (camera held '
              'above shoulder height). Most of the roof panel should be visible. '
              'A side or front shot without roof emphasis is "wrongSubject".',
        );
      case 'interior':
        return (
          shortLabel: 'the interior of the car',
          description:
              'The interior of a car, shot through the driver-side door. The '
              'driver seat, steering wheel, and dashboard should all be visible '
              'together in one frame. An exterior shot is "wrongSubject".',
        );
      case 'tyre':
        return (
          shortLabel: 'a tyre',
          description:
              'A photo of one car tyre. Any angle is acceptable — a side-on '
              'shot showing the sidewall is fine, a top-down shot showing '
              'the tread is fine, even a 3/4 angle showing part sidewall + '
              'part tread is fine. Only a small portion of the rubber '
              'pattern needs to be visible. The bar is low: as long as the '
              'image is clearly a tyre (not a wheel cap close-up, not the '
              'brake disc, not the wheel arch), accept it as "good". Reject '
              'with "wrongSubject" only when the photo is unmistakably NOT '
              'a tyre. Reject with "blurry" / "dark" only on severe focus '
              'or exposure problems — minor blur is fine.',
        );
      default:
        return null; // no AI check for this step
    }
  }
}

