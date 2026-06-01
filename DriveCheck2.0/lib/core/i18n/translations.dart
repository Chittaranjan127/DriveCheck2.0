import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/language_service.dart';

/// All user-facing strings. Add a new key here and to every per-language map below.
class Translations {
  final AppLanguage language;

  final String signIn;
  final String otpHint;
  final String mobileNumber;
  final String sendOtp;
  final String changeLanguage;
  final String poweredBy;
  final String invalidPhone;
  final String numberNotRegistered;
  final String enterCode;
  final String sentTo;
  final String verify;
  final String resend;
  final String otpWrong;
  final String chooseLanguage;
  final String chooseLanguageSub;
  final String continueLabel;
  final String todaysInspections;
  final String noInspectionsToday;
  final String inspections;
  final String pastInspections;
  final String noInspectionsYet;
  final String settings;
  final String profile;
  final String preferences;
  final String languageLabel;
  final String account;
  final String logout;
  final String logoutConfirmTitle;
  final String logoutConfirmBody;
  final String cancel;
  final String notSet;
  final String navHome;
  final String navInspections;
  final String navSettings;
  final String navProfile;
  final String joinedSince;
  final String completedInspectionsCount;
  final String disableAiAssistant;
  final String disableAiAssistantHint;
  final String today;
  final String tomorrow;
  final String yesterday;
  final String statusScheduled;
  final String statusInProgress;
  final String statusCompleted;
  final String kmAway;
  final String noInspectionsForDay;
  final String startInspection;
  final String continueInspection;
  final String viewReport;
  final String step;
  final String of;
  final String next;
  final String redo;
  final String retake;
  final String saveAndFinish;
  final String example;
  // ---- Test drive verdict + summary labels ----
  final String tdVerdictGood;
  final String tdVerdictMinor;
  final String tdVerdictConcern;
  final String tdVerdictCritical;
  final String tdVerdictInconclusive;
  final String tdChecksComplete;     // "{done} of {total} checks complete"
  final String tdOverallFeedback;
  final String tdVerdictLabel;       // "Verdict:" prefix in review row
  // ---- Test drive on-screen labels (intro / conversing / errors) ----
  final String tdLoading;
  final String tdSavingDrive;
  final String tdAdvancing;
  final String tdHandsFreeTitle;
  final String tdHandsFreeBody;
  final String tdStartDrive;
  final String tdNoMoreTaps;
  final String tdOverallFeedbackHeader; // pill on conversing screen
  final String tdAsking;
  final String tdListenCarefully;
  final String tdTranscribing;
  final String tdHearingWhat;
  final String tdUnderstanding;
  final String tdGotIt;
  final String tdWrappingUp;
  final String tdSpeakAnswer;
  final String tdPlay;
  final String tdPlaying;
  final String tdStartOver;
  final String tdSomethingWrong;
  final String tdMicPermissionNeeded;
  // ---- Cross-screen common buttons / status copy ----
  final String couldNotLoadInspections;
  final String cameraAccessNeeded;
  final String useThis;
  final String reRecord;
  final String tapToRecord;
  final String useRcValues;
  final String carDetailsDiffer;
  final String useRcValuesBody;
  final String couldNotSave;
  final String couldNotOpenMaps;
  // ---- Inspection review screen ----
  final String reviewTitle;
  final String viewInspectionTitle;
  final String outcomeAccepted;
  final String outcomeCountered;
  final String outcomeDeclined;
  final String finalPriceLabel;
  final String reviewSubtitle;
  final String confirmAndAnalyze;
  final String reviewLoadFailed;
  final String reviewStepIncomplete;
  // ---- Inspection report screen ----
  final String reportTitle;
  final String preparingReport;
  final String tryAgain;
  final String estimatedPrice;
  final String sellerQuoted;
  final String fairRange;
  final String marketRange;
  final String aiConfidence;
  final String whatToTellCustomer;
  final String bridgeToAskTitle;
  final String playPitch;
  final String stopPitch;
  final String openingLine;
  final String supportingPoints;
  final String ifCustomerPushesBack;
  final String whatToDoNext;
  final String customerAgreed;
  final String customerNotAgreed;
  final String counterOfferTitle;
  final String counterOfferHint;
  final String customerPriceLabel;
  final String notesLabel;
  final String notesHint;
  final String submitTicket;
  final String allFindings;
  final String inspectionScoreLabel;
  final String copiedToClipboard;
  final String reportLoadFailed;
  final String submitFailed;
  final String submittedBadge;
  final String exit;
  final String customerLocation;
  final String arrivalQuestion;
  final String arrivalHelp;
  final String yesArrived;
  final String arrivedConfirmed;
  final String notYet;
  final String getDirections;
  final String exitInspectionTitle;
  final String exitInspectionBody;
  final String stepArrivalTitle;
  final String stepArrivalInstruction;
  final String stepRcTitle;
  final String stepRcInstruction;
  final String stepClusterTitle;
  final String stepClusterInstruction;
  final String stepEngineBayTitle;
  final String stepEngineBayInstruction;
  final String stepFrontTitle;
  final String stepFrontInstruction;
  final String stepLeftTitle;
  final String stepLeftInstruction;
  final String stepRightTitle;
  final String stepRightInstruction;
  final String stepRearTitle;
  final String stepRearInstruction;
  final String stepRoofTitle;
  final String stepRoofInstruction;
  final String stepInteriorTitle;
  final String stepInteriorInstruction;
  final String stepTyresTitle;
  final String stepTyresInstruction;
  final String stepEngineSoundTitle;
  final String stepEngineSoundInstruction;
  final String stepTestDriveTitle;
  final String stepTestDriveInstruction;

  const Translations({
    required this.language,
    required this.signIn,
    required this.otpHint,
    required this.mobileNumber,
    required this.sendOtp,
    required this.changeLanguage,
    required this.poweredBy,
    required this.invalidPhone,
    required this.numberNotRegistered,
    required this.enterCode,
    required this.sentTo,
    required this.verify,
    required this.resend,
    required this.otpWrong,
    required this.chooseLanguage,
    required this.chooseLanguageSub,
    required this.continueLabel,
    required this.todaysInspections,
    required this.noInspectionsToday,
    required this.inspections,
    required this.pastInspections,
    required this.noInspectionsYet,
    required this.settings,
    required this.profile,
    required this.preferences,
    required this.languageLabel,
    required this.account,
    required this.logout,
    required this.logoutConfirmTitle,
    required this.logoutConfirmBody,
    required this.cancel,
    required this.notSet,
    required this.navHome,
    required this.navInspections,
    required this.navSettings,
    required this.navProfile,
    required this.joinedSince,
    required this.completedInspectionsCount,
    required this.disableAiAssistant,
    required this.disableAiAssistantHint,
    required this.today,
    required this.tomorrow,
    required this.yesterday,
    required this.statusScheduled,
    required this.statusInProgress,
    required this.statusCompleted,
    required this.kmAway,
    required this.noInspectionsForDay,
    required this.startInspection,
    required this.continueInspection,
    required this.viewReport,
    required this.step,
    required this.of,
    required this.next,
    required this.redo,
    required this.retake,
    required this.saveAndFinish,
    required this.example,
    required this.tdVerdictGood,
    required this.tdVerdictMinor,
    required this.tdVerdictConcern,
    required this.tdVerdictCritical,
    required this.tdVerdictInconclusive,
    required this.tdChecksComplete,
    required this.tdOverallFeedback,
    required this.tdLoading,
    required this.tdSavingDrive,
    required this.tdAdvancing,
    required this.tdHandsFreeTitle,
    required this.tdHandsFreeBody,
    required this.tdStartDrive,
    required this.tdNoMoreTaps,
    required this.tdOverallFeedbackHeader,
    required this.tdAsking,
    required this.tdListenCarefully,
    required this.tdTranscribing,
    required this.tdHearingWhat,
    required this.tdUnderstanding,
    required this.tdGotIt,
    required this.tdWrappingUp,
    required this.tdSpeakAnswer,
    required this.tdPlay,
    required this.tdPlaying,
    required this.tdStartOver,
    required this.tdSomethingWrong,
    required this.tdMicPermissionNeeded,
    required this.couldNotLoadInspections,
    required this.cameraAccessNeeded,
    required this.useThis,
    required this.reRecord,
    required this.tapToRecord,
    required this.useRcValues,
    required this.carDetailsDiffer,
    required this.useRcValuesBody,
    required this.couldNotSave,
    required this.couldNotOpenMaps,
    required this.tdVerdictLabel,
    required this.reviewTitle,
    required this.viewInspectionTitle,
    required this.outcomeAccepted,
    required this.outcomeCountered,
    required this.outcomeDeclined,
    required this.finalPriceLabel,
    required this.reviewSubtitle,
    required this.confirmAndAnalyze,
    required this.reviewLoadFailed,
    required this.reviewStepIncomplete,
    required this.reportTitle,
    required this.preparingReport,
    required this.tryAgain,
    required this.estimatedPrice,
    required this.sellerQuoted,
    required this.fairRange,
    required this.marketRange,
    required this.aiConfidence,
    required this.whatToTellCustomer,
    required this.bridgeToAskTitle,
    required this.playPitch,
    required this.stopPitch,
    required this.openingLine,
    required this.supportingPoints,
    required this.ifCustomerPushesBack,
    required this.whatToDoNext,
    required this.customerAgreed,
    required this.customerNotAgreed,
    required this.counterOfferTitle,
    required this.counterOfferHint,
    required this.customerPriceLabel,
    required this.notesLabel,
    required this.notesHint,
    required this.submitTicket,
    required this.allFindings,
    required this.inspectionScoreLabel,
    required this.copiedToClipboard,
    required this.reportLoadFailed,
    required this.submitFailed,
    required this.submittedBadge,
    required this.exit,
    required this.customerLocation,
    required this.arrivalQuestion,
    required this.arrivalHelp,
    required this.yesArrived,
    required this.arrivedConfirmed,
    required this.notYet,
    required this.getDirections,
    required this.exitInspectionTitle,
    required this.exitInspectionBody,
    required this.stepArrivalTitle,
    required this.stepArrivalInstruction,
    required this.stepRcTitle,
    required this.stepRcInstruction,
    required this.stepClusterTitle,
    required this.stepClusterInstruction,
    required this.stepEngineBayTitle,
    required this.stepEngineBayInstruction,
    required this.stepFrontTitle,
    required this.stepFrontInstruction,
    required this.stepLeftTitle,
    required this.stepLeftInstruction,
    required this.stepRightTitle,
    required this.stepRightInstruction,
    required this.stepRearTitle,
    required this.stepRearInstruction,
    required this.stepRoofTitle,
    required this.stepRoofInstruction,
    required this.stepInteriorTitle,
    required this.stepInteriorInstruction,
    required this.stepTyresTitle,
    required this.stepTyresInstruction,
    required this.stepEngineSoundTitle,
    required this.stepEngineSoundInstruction,
    required this.stepTestDriveTitle,
    required this.stepTestDriveInstruction,
  });

  /// Returns [base] with the active language's font applied (Indic scripts swap to Noto Sans).
  TextStyle style(TextStyle base) {
    final family = switch (language) {
      AppLanguage.english => null,
      AppLanguage.hindi   => GoogleFonts.notoSansDevanagari().fontFamily,
      AppLanguage.telugu  => GoogleFonts.notoSansTelugu().fontFamily,
      AppLanguage.bengali => GoogleFonts.notoSansBengali().fontFamily,
    };
    if (family == null) return base;
    return base.copyWith(fontFamily: family, height: 1.35);
  }

  static Translations forLanguage(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.english: return _en;
      case AppLanguage.hindi:   return _hi;
      case AppLanguage.telugu:  return _te;
      case AppLanguage.bengali: return _bn;
    }
  }
}

final translationsProvider = Provider<Translations>((ref) {
  final lang = ref.watch(languageProvider).valueOrNull ?? AppLanguage.english;
  return Translations.forLanguage(lang);
});

const _en = Translations(
  language: AppLanguage.english,
  signIn: 'Sign in',
  otpHint: "We'll send a 6-digit code to verify your number.",
  mobileNumber: 'Mobile number',
  sendOtp: 'Send OTP',
  changeLanguage: 'Change language',
  poweredBy: 'Powered by Cars24',
  invalidPhone: 'Enter a valid 10-digit number',
  numberNotRegistered: "This number isn't registered.",
  enterCode: 'Enter the code',
  sentTo: 'Sent to',
  verify: 'Verify',
  resend: "Didn't get it? Resend",
  otpWrong: 'Wrong OTP. Try again.',
  chooseLanguage: 'Choose language',
  chooseLanguageSub: 'Pick the one you read most comfortably.',
  continueLabel: 'Continue',
  todaysInspections: "Today's inspections",
  noInspectionsToday: 'No inspections scheduled yet.',
  inspections: 'Inspections',
  pastInspections: 'Past inspections',
  noInspectionsYet: 'No inspections yet',
  settings: 'Settings',
  profile: 'Profile',
  preferences: 'Preferences',
  languageLabel: 'Language',
  account: 'Account',
  logout: 'Log out',
  logoutConfirmTitle: 'Log out?',
  logoutConfirmBody: "You'll need to sign in again.",
  cancel: 'Cancel',
  notSet: 'Not set',
  navHome: 'Home',
  navInspections: 'Inspections',
  navSettings: 'Settings',
  navProfile: 'Profile',
  joinedSince: 'Joined',
  completedInspectionsCount: 'Inspections completed',
  disableAiAssistant: 'Disable AI assistant',
  disableAiAssistantHint: 'Skip voice prompts and hide the assistant bar.',
  today: 'Today',
  tomorrow: 'Tomorrow',
  yesterday: 'Yesterday',
  statusScheduled: 'Scheduled',
  statusInProgress: 'In progress',
  statusCompleted: 'Done',
  kmAway: 'km away',
  noInspectionsForDay: 'No inspections this day',
  startInspection: 'Start',
  continueInspection: 'Continue',
  viewReport: 'View report',
  step: 'Step',
  of: 'of',
  next: 'Next',
  redo: 'Redo',
  retake: 'Retake',
  saveAndFinish: 'Save & finish',
  example: 'Example',
  tdVerdictGood: 'Good drive',
  tdVerdictMinor: 'Minor issues',
  tdVerdictConcern: 'Needs attention',
  tdVerdictCritical: 'Critical issues',
  tdVerdictInconclusive: 'Inconclusive',
  tdChecksComplete: 'checks complete',
  tdOverallFeedback: 'Overall feedback',
  tdVerdictLabel: 'Verdict',
  tdLoading: 'Loading…',
  tdSavingDrive: 'Saving test drive…',
  tdAdvancing: 'Saved. Continuing…',
  tdHandsFreeTitle: 'Hands-free drive',
  tdHandsFreeBody: "You'll answer 7 short questions while driving. "
      "I'll ask, listen, and confirm each answer back to you. "
      "Drive safely — keep your eyes on the road.",
  tdStartDrive: 'Start drive',
  tdNoMoreTaps: 'No more taps after this — drive safe',
  tdOverallFeedbackHeader: 'Overall feedback',
  tdAsking: 'Asking…',
  tdListenCarefully: 'Listen carefully',
  tdTranscribing: 'Transcribing…',
  tdHearingWhat: 'Hearing what you said',
  tdUnderstanding: 'Understanding…',
  tdGotIt: 'Got it',
  tdWrappingUp: 'Wrapping up…',
  tdSpeakAnswer: 'Speak your answer',
  tdPlay: 'Play',
  tdPlaying: 'Playing',
  tdStartOver: 'Start over',
  tdSomethingWrong: 'Something went wrong.',
  tdMicPermissionNeeded: 'Microphone permission is required for the test drive.',
  couldNotLoadInspections: "Couldn't load inspections",
  cameraAccessNeeded: 'Camera access is needed. Please allow it in Settings.',
  useThis: 'Use this',
  reRecord: 'Re-record',
  tapToRecord: 'Tap the button below to record',
  useRcValues: 'Use RC values',
  carDetailsDiffer: 'Car details differ',
  useRcValuesBody: 'The RC card shows different values than the booking. '
      'Confirm to use the RC values for the rest of the inspection.',
  couldNotSave: "Couldn't save",
  couldNotOpenMaps: "Couldn't open maps app",
  reviewTitle: 'Review captured data',
  viewInspectionTitle: 'Inspection details',
  outcomeAccepted: 'Customer accepted',
  outcomeCountered: 'Counter-offer',
  outcomeDeclined: 'Customer declined',
  finalPriceLabel: 'Final price',
  reviewSubtitle: 'Check every step before sending for AI pricing.',
  confirmAndAnalyze: 'Confirm & get pricing',
  reviewLoadFailed: 'Could not load inspection data.',
  reviewStepIncomplete: 'Not captured',
  reportTitle: 'Inspection report',
  preparingReport: 'Preparing the report — AI is pricing the car…',
  tryAgain: 'Try again',
  estimatedPrice: 'Estimated price',
  sellerQuoted: 'Seller quoted',
  fairRange: 'Fair range',
  marketRange: 'Market range',
  aiConfidence: 'AI confidence',
  whatToTellCustomer: 'What to tell the customer',
  bridgeToAskTitle: "How to match the seller's price",
  playPitch: 'Play pitch',
  stopPitch: 'Stop',
  openingLine: 'Opening line',
  supportingPoints: 'Supporting points',
  ifCustomerPushesBack: 'If the customer pushes back',
  whatToDoNext: 'What to do next',
  customerAgreed: 'Customer agreed',
  customerNotAgreed: 'Customer not agreed',
  counterOfferTitle: "Customer's counter-offer",
  counterOfferHint: 'Enter the price the customer wants.',
  customerPriceLabel: 'Customer price (₹)',
  notesLabel: 'Notes (optional)',
  notesHint: 'Anything the customer said worth recording',
  submitTicket: 'Submit ticket',
  allFindings: 'All inspection findings',
  inspectionScoreLabel: 'Inspection',
  copiedToClipboard: 'Copied to clipboard',
  reportLoadFailed: 'Could not load the report.',
  submitFailed: 'Could not submit. Please try again.',
  submittedBadge: 'This inspection has been submitted',
  exit: 'Exit',
  customerLocation: 'Customer location',
  arrivalQuestion: 'Have you arrived?',
  arrivalHelp: "Tap Yes once you reach the customer's location.",
  yesArrived: "Yes, I'm here",
  arrivedConfirmed: 'Arrived — continue',
  notYet: 'Not yet',
  getDirections: 'Get directions',
  exitInspectionTitle: 'Exit inspection?',
  exitInspectionBody: 'Your progress will be saved.',
  stepArrivalTitle: 'Arrival',
  stepArrivalInstruction: "Confirm when you reach the customer's location.",
  stepRcTitle: 'RC document',
  stepRcInstruction: 'Place the RC book flat and photograph the main page.',
  stepClusterTitle: 'Dashboard',
  stepClusterInstruction: 'Turn ignition on. Photograph the full dashboard.',
  stepEngineBayTitle: 'Engine bay',
  stepEngineBayInstruction: 'Open the bonnet. Photograph the engine from above.',
  stepFrontTitle: 'Front view',
  stepFrontInstruction: 'Stand 2 steps in front. Capture the full front.',
  stepLeftTitle: 'Left side',
  stepLeftInstruction: 'Stand on the left side. Capture the full side in one frame.',
  stepRightTitle: 'Right side',
  stepRightInstruction: 'Stand on the right side. Capture the full side in one frame.',
  stepRearTitle: 'Rear view',
  stepRearInstruction: 'Stand 2 steps behind. Capture the full rear.',
  stepRoofTitle: 'Roof',
  stepRoofInstruction: 'Stand beside the car and photograph the roof at an angle.',
  stepInteriorTitle: 'Interior',
  stepInteriorInstruction: 'Open the driver door. Photograph seats and dashboard together.',
  stepTyresTitle: 'All 4 tyres',
  stepTyresInstruction: 'Photograph each tyre close up. Tread must be clearly visible.',
  stepEngineSoundTitle: 'Engine sound',
  stepEngineSoundInstruction: 'Start the engine. Hold the phone near it for 15 seconds.',
  stepTestDriveTitle: 'Test drive',
  stepTestDriveInstruction: 'Drive the car. Answer questions by speaking. Hands on the wheel.',
);

const _hi = Translations(
  language: AppLanguage.hindi,
  signIn: 'साइन इन करें',
  otpHint: 'हम आपके नंबर पर 6 अंकों का कोड भेजेंगे।',
  mobileNumber: 'मोबाइल नंबर',
  sendOtp: 'OTP भेजें',
  changeLanguage: 'भाषा बदलें',
  poweredBy: 'Cars24 द्वारा संचालित',
  invalidPhone: 'सही 10 अंकों का नंबर डालें',
  numberNotRegistered: 'यह नंबर रजिस्टर्ड नहीं है।',
  enterCode: 'कोड डालें',
  sentTo: 'भेजा गया',
  verify: 'वेरिफ़ाई करें',
  resend: 'नहीं मिला? दोबारा भेजें',
  otpWrong: 'OTP ग़लत है। दोबारा कोशिश करें।',
  chooseLanguage: 'भाषा चुनें',
  chooseLanguageSub: 'वही चुनें जो आप आसानी से पढ़ सकें।',
  continueLabel: 'आगे बढ़ें',
  todaysInspections: 'आज के इंस्पेक्शन',
  noInspectionsToday: 'आज कोई इंस्पेक्शन तय नहीं है।',
  inspections: 'इंस्पेक्शन',
  pastInspections: 'पुराने इंस्पेक्शन',
  noInspectionsYet: 'अभी कोई इंस्पेक्शन नहीं',
  settings: 'सेटिंग्स',
  profile: 'प्रोफाइल',
  preferences: 'प्राथमिकताएं',
  languageLabel: 'भाषा',
  account: 'अकाउंट',
  logout: 'लॉग आउट',
  logoutConfirmTitle: 'लॉग आउट करें?',
  logoutConfirmBody: 'दोबारा साइन इन करना होगा।',
  cancel: 'रद्द करें',
  notSet: 'सेट नहीं है',
  navHome: 'होम',
  navInspections: 'इंस्पेक्शन',
  navSettings: 'सेटिंग्स',
  navProfile: 'Profile',
  joinedSince: 'Join किया',
  completedInspectionsCount: 'Inspection पूरे किए',
  disableAiAssistant: 'AI assistant बंद करें',
  disableAiAssistantHint: 'Voice prompts off, assistant bar hidden.',
  today: 'आज',
  tomorrow: 'कल',
  yesterday: 'बीता कल',
  statusScheduled: 'तय है',
  statusInProgress: 'चल रहा है',
  statusCompleted: 'पूरा',
  kmAway: 'km दूर',
  noInspectionsForDay: 'इस दिन कोई इंस्पेक्शन नहीं',
  startInspection: 'शुरू करें',
  continueInspection: 'जारी रखें',
  viewReport: 'रिपोर्ट देखें',
  step: 'स्टेप',
  of: 'से',
  next: 'आगे',
  redo: 'फिर से करें',
  retake: 'दोबारा फोटो',
  saveAndFinish: 'सेव करें और खत्म',
  example: 'उदाहरण',
  tdVerdictGood: 'अच्छी ड्राइव',
  tdVerdictMinor: 'छोटी समस्याएँ',
  tdVerdictConcern: 'ध्यान देने योग्य',
  tdVerdictCritical: 'गंभीर समस्याएँ',
  tdVerdictInconclusive: 'अनिश्चित',
  tdChecksComplete: 'जाँच पूरी',
  tdOverallFeedback: 'कुल राय',
  tdLoading: 'Loading…',
  tdSavingDrive: 'Test drive save हो रहा है…',
  tdAdvancing: 'Save हो गया. आगे बढ़ रहे हैं…',
  tdHandsFreeTitle: 'Hands-free drive',
  tdHandsFreeBody: 'Drive करते हुए मैं 7 छोटे सवाल पूछूँगा. '
      'सुनकर हर जवाब confirm भी करूँगा. '
      'सावधानी से चलाइए — ध्यान road पर रखिए.',
  tdStartDrive: 'Drive शुरू करो',
  tdNoMoreTaps: 'अब कोई tap नहीं — drive safe',
  tdOverallFeedbackHeader: 'कुल राय',
  tdAsking: 'पूछ रहा हूँ…',
  tdListenCarefully: 'ध्यान से सुनिए',
  tdTranscribing: 'सुन रहा हूँ…',
  tdHearingWhat: 'आपने जो कहा उसे समझ रहा हूँ',
  tdUnderstanding: 'समझ रहा हूँ…',
  tdGotIt: 'समझ गया',
  tdWrappingUp: 'पूरा कर रहा हूँ…',
  tdSpeakAnswer: 'अब अपना जवाब बोलिए',
  tdPlay: 'Play',
  tdPlaying: 'Play हो रहा है',
  tdStartOver: 'फिर से शुरू करो',
  tdSomethingWrong: 'कुछ गड़बड़ हो गई.',
  tdMicPermissionNeeded: 'Test drive के लिए microphone की permission चाहिए.',
  couldNotLoadInspections: 'Inspections load नहीं हो पाए',
  cameraAccessNeeded: 'Camera की permission चाहिए. Settings में जाकर allow कीजिए.',
  useThis: 'इसे रखो',
  reRecord: 'फिर से record करो',
  tapToRecord: 'Record करने के लिए नीचे का button दबाइए',
  useRcValues: 'RC के values रखो',
  carDetailsDiffer: 'Car की details अलग हैं',
  useRcValuesBody: 'RC card पर booking से अलग values हैं. '
      'Confirm कीजिए तो आगे की inspection RC के values से होगी.',
  couldNotSave: 'Save नहीं हो पाया',
  couldNotOpenMaps: 'Maps app नहीं खुल पाया',
  tdVerdictLabel: 'नतीजा',
  reviewTitle: 'सारी जानकारी देखें',
  viewInspectionTitle: 'Inspection की जानकारी',
  outcomeAccepted: 'Customer ने हाँ कहा',
  outcomeCountered: 'Counter-offer',
  outcomeDeclined: 'Customer ने मना कर दिया',
  finalPriceLabel: 'Final price',
  reviewSubtitle: 'AI से कीमत लगवाने से पहले हर स्टेप चेक करें।',
  confirmAndAnalyze: 'पुष्टि करें और कीमत लें',
  reviewLoadFailed: 'जानकारी लोड नहीं हो सकी।',
  reviewStepIncomplete: 'नहीं लिया',
  reportTitle: 'इंस्पेक्शन रिपोर्ट',
  preparingReport: 'रिपोर्ट तैयार हो रही है — AI गाड़ी की कीमत लगा रहा है…',
  tryAgain: 'फिर से कोशिश करें',
  estimatedPrice: 'अनुमानित कीमत',
  sellerQuoted: 'विक्रेता ने माँगा',
  fairRange: 'सही रेंज',
  marketRange: 'Market रेंज',
  aiConfidence: 'AI भरोसा',
  whatToTellCustomer: 'ग्राहक को क्या कहें',
  bridgeToAskTitle: 'अपनी quoted price match करने के लिए',
  playPitch: 'सुनिए',
  stopPitch: 'रोकें',
  openingLine: 'शुरुआती बात',
  supportingPoints: 'मुख्य बातें',
  ifCustomerPushesBack: 'अगर ग्राहक मना करे',
  whatToDoNext: 'आगे क्या करना है',
  customerAgreed: 'ग्राहक मान गए',
  customerNotAgreed: 'ग्राहक नहीं माने',
  counterOfferTitle: 'ग्राहक की कीमत',
  counterOfferHint: 'ग्राहक जो कीमत चाहते हैं वो डालें।',
  customerPriceLabel: 'ग्राहक की कीमत (₹)',
  notesLabel: 'टिप्पणी (वैकल्पिक)',
  notesHint: 'ग्राहक ने जो कुछ कहा हो वो लिखें',
  submitTicket: 'टिकट भेजें',
  allFindings: 'सभी इंस्पेक्शन जानकारी',
  inspectionScoreLabel: 'इंस्पेक्शन',
  copiedToClipboard: 'कॉपी हो गया',
  reportLoadFailed: 'रिपोर्ट लोड नहीं हो सकी।',
  submitFailed: 'भेजा नहीं जा सका। फिर कोशिश करें।',
  submittedBadge: 'यह इंस्पेक्शन जमा हो गया है',
  exit: 'बाहर निकलें',
  customerLocation: 'ग्राहक का पता',
  arrivalQuestion: 'क्या आप पहुँच गए?',
  arrivalHelp: 'ग्राहक के पास पहुँचते ही हाँ दबाएँ।',
  yesArrived: 'हाँ, मैं पहुँच गया',
  arrivedConfirmed: 'पहुँच गए — आगे बढ़ें',
  notYet: 'अभी नहीं',
  getDirections: 'रास्ता दिखाओ',
  exitInspectionTitle: 'इंस्पेक्शन बंद करें?',
  exitInspectionBody: 'आपकी प्रगति सेव हो जाएगी।',
  stepArrivalTitle: 'पहुँचना',
  stepArrivalInstruction: 'ग्राहक के पास पहुँचते ही पुष्टि करें।',
  stepRcTitle: 'RC बुक',
  stepRcInstruction: 'RC book को सीधा रखें और मुख्य पन्ने की फोटो लें।',
  stepClusterTitle: 'डैशबोर्ड',
  stepClusterInstruction: 'गाड़ी चालू करें। पूरा डैशबोर्ड फोटो लें।',
  stepEngineBayTitle: 'इंजन',
  stepEngineBayInstruction: 'बोनेट खोलें। ऊपर से इंजन की फोटो लें।',
  stepFrontTitle: 'आगे से फोटो',
  stepFrontInstruction: 'गाड़ी के सामने 2 कदम पीछे जाएँ। पूरी सामने की फोटो लें।',
  stepLeftTitle: 'बायीं तरफ',
  stepLeftInstruction: 'बायीं तरफ खड़े हों। पूरी साइड एक फोटो में लें।',
  stepRightTitle: 'दायीं तरफ',
  stepRightInstruction: 'दायीं तरफ खड़े हों। पूरी साइड एक फोटो में लें।',
  stepRearTitle: 'पीछे से फोटो',
  stepRearInstruction: 'गाड़ी के पीछे 2 कदम दूर जाएँ। पूरी पीछे की फोटो लें।',
  stepRoofTitle: 'छत',
  stepRoofInstruction: 'गाड़ी के बाजू खड़े हों। ऊपर से छत की फोटो लें।',
  stepInteriorTitle: 'अंदर',
  stepInteriorInstruction: 'दरवाज़ा खोलें। सीट और डैशबोर्ड एक साथ फोटो में लें।',
  stepTyresTitle: 'चारों टायर',
  stepTyresInstruction: 'हर टायर के पास जाएँ। रबर का हिस्सा साफ़ दिखना चाहिए।',
  stepEngineSoundTitle: 'इंजन की आवाज़',
  stepEngineSoundInstruction: 'इंजन चालू करें। फोन को इंजन के पास 15 सेकंड रखें।',
  stepTestDriveTitle: 'टेस्ट ड्राइव',
  stepTestDriveInstruction: 'गाड़ी चलाएँ। बोलकर सवालों के जवाब दें। हाथ स्टीयरिंग पर रखें।',
);

const _te = Translations(
  language: AppLanguage.telugu,
  signIn: 'సైన్ ఇన్',
  otpHint: 'మీ నంబర్‌కి 6 అంకెల కోడ్ పంపుతాం.',
  mobileNumber: 'మొబైల్ నంబర్',
  sendOtp: 'OTP పంపండి',
  changeLanguage: 'భాష మార్చండి',
  poweredBy: 'Cars24 ద్వారా',
  invalidPhone: 'సరైన 10 అంకెల నంబర్ ఇవ్వండి',
  numberNotRegistered: 'ఈ నంబర్ నమోదు కాలేదు.',
  enterCode: 'కోడ్ నమోదు చేయండి',
  sentTo: 'పంపబడింది',
  verify: 'ధృవీకరించండి',
  resend: 'రాలేదా? మళ్లీ పంపండి',
  otpWrong: 'OTP తప్పు. మళ్లీ ప్రయత్నించండి.',
  chooseLanguage: 'భాషను ఎంచుకోండి',
  chooseLanguageSub: 'మీరు సులభంగా చదవగలిగేది ఎంచుకోండి.',
  continueLabel: 'కొనసాగించండి',
  todaysInspections: 'ఈరోజు ఇన్‌స్పెక్షన్‌లు',
  noInspectionsToday: 'ఇంకా ఇన్‌స్పెక్షన్‌లు లేవు.',
  inspections: 'ఇన్‌స్పెక్షన్‌లు',
  pastInspections: 'గత ఇన్‌స్పెక్షన్‌లు',
  noInspectionsYet: 'ఇంకా ఇన్‌స్పెక్షన్‌లు లేవు',
  settings: 'సెట్టింగ్‌లు',
  profile: 'ప్రొఫైల్',
  preferences: 'ప్రాధాన్యతలు',
  languageLabel: 'భాష',
  account: 'ఖాతా',
  logout: 'లాగ్ అవుట్',
  logoutConfirmTitle: 'లాగ్ అవుట్ చేయాలా?',
  logoutConfirmBody: 'మళ్లీ సైన్ ఇన్ చేయాల్సి ఉంటుంది.',
  cancel: 'రద్దు చేయండి',
  notSet: 'సెట్ చేయలేదు',
  navHome: 'హోమ్',
  navInspections: 'ఇన్‌స్పెక్షన్',
  navSettings: 'సెట్టింగ్‌లు',
  navProfile: 'Profile',
  joinedSince: 'Join అయింది',
  completedInspectionsCount: 'Inspections పూర్తి చేశారు',
  disableAiAssistant: 'AI assistant ఆపండి',
  disableAiAssistantHint: 'Voice prompts ఆగుతాయి, assistant bar కనిపించదు.',
  today: 'ఈరోజు',
  tomorrow: 'రేపు',
  yesterday: 'నిన్న',
  statusScheduled: 'షెడ్యూల్',
  statusInProgress: 'జరుగుతోంది',
  statusCompleted: 'పూర్తయింది',
  kmAway: 'km దూరం',
  noInspectionsForDay: 'ఈ రోజు ఇన్‌స్పెక్షన్‌లు లేవు',
  startInspection: 'మొదలుపెట్టండి',
  continueInspection: 'కొనసాగించండి',
  viewReport: 'రిపోర్ట్ చూడండి',
  step: 'దశ',
  of: 'లో',
  next: 'తదుపరి',
  redo: 'మళ్ళీ చేయండి',
  retake: 'మళ్ళీ ఫోటో',
  saveAndFinish: 'సేవ్ చేసి ముగించండి',
  example: 'ఉదాహరణ',
  tdVerdictGood: 'మంచి డ్రైవ్',
  tdVerdictMinor: 'చిన్న సమస్యలు',
  tdVerdictConcern: 'శ్రద్ధ అవసరం',
  tdVerdictCritical: 'తీవ్రమైన సమస్యలు',
  tdVerdictInconclusive: 'నిర్ధారణ లేదు',
  tdChecksComplete: 'తనిఖీలు పూర్తి',
  tdOverallFeedback: 'మొత్తం అభిప్రాయం',
  tdLoading: 'Loading…',
  tdSavingDrive: 'Test drive save అవుతోంది…',
  tdAdvancing: 'Save అయింది. ముందుకు వెళ్తున్నాం…',
  tdHandsFreeTitle: 'Hands-free drive',
  tdHandsFreeBody: 'Drive చేస్తూ నేను 7 చిన్న ప్రశ్నలు అడుగుతాను. '
      'వింటాను, ప్రతి జవాబు confirm చేస్తాను. '
      'జాగ్రత్తగా నడపండి — దృష్టి road పై ఉంచండి.',
  tdStartDrive: 'Drive మొదలు పెట్టండి',
  tdNoMoreTaps: 'ఇక tap అవసరం లేదు — drive safe',
  tdOverallFeedbackHeader: 'మొత్తం అభిప్రాయం',
  tdAsking: 'అడుగుతున్నాను…',
  tdListenCarefully: 'జాగ్రత్తగా వినండి',
  tdTranscribing: 'వింటున్నాను…',
  tdHearingWhat: 'మీరు చెప్పింది అర్థం చేసుకుంటున్నాను',
  tdUnderstanding: 'అర్థం చేసుకుంటున్నాను…',
  tdGotIt: 'అర్థమైంది',
  tdWrappingUp: 'ముగిస్తున్నాను…',
  tdSpeakAnswer: 'మీ జవాబు చెప్పండి',
  tdPlay: 'Play',
  tdPlaying: 'Play అవుతోంది',
  tdStartOver: 'మళ్ళీ మొదలు పెట్టండి',
  tdSomethingWrong: 'ఏదో తప్పు జరిగింది.',
  tdMicPermissionNeeded: 'Test drive కోసం microphone permission అవసరం.',
  couldNotLoadInspections: 'Inspections load కాలేదు',
  cameraAccessNeeded: 'Camera permission అవసరం. Settings లో allow చేయండి.',
  useThis: 'ఇది ఉంచండి',
  reRecord: 'మళ్ళీ record చేయండి',
  tapToRecord: 'Record కోసం కింది button నొక్కండి',
  useRcValues: 'RC values ఉంచండి',
  carDetailsDiffer: 'Car details వేరుగా ఉన్నాయి',
  useRcValuesBody: 'RC card లో booking కంటే వేరే values ఉన్నాయి. '
      'Confirm చేస్తే మిగతా inspection RC values తో జరుగుతుంది.',
  couldNotSave: 'Save కాలేదు',
  couldNotOpenMaps: 'Maps app తెరువబడలేదు',
  tdVerdictLabel: 'తీర్పు',
  reviewTitle: 'సేకరించిన డేటాను సమీక్షించండి',
  viewInspectionTitle: 'Inspection వివరాలు',
  outcomeAccepted: 'Customer అంగీకరించారు',
  outcomeCountered: 'Counter-offer',
  outcomeDeclined: 'Customer తిరస్కరించారు',
  finalPriceLabel: 'Final price',
  reviewSubtitle: 'AI ధర కోసం పంపే ముందు ప్రతి దశను తనిఖీ చేయండి.',
  confirmAndAnalyze: 'నిర్ధారించి ధర పొందండి',
  reviewLoadFailed: 'డేటా లోడ్ కాలేదు.',
  reviewStepIncomplete: 'తీయలేదు',
  reportTitle: 'ఇన్‌స్పెక్షన్ రిపోర్ట్',
  preparingReport: 'రిపోర్ట్ తయారవుతోంది — AI కారు ధర నిర్ధారిస్తోంది…',
  tryAgain: 'మళ్ళీ ప్రయత్నించండి',
  estimatedPrice: 'అంచనా ధర',
  sellerQuoted: 'విక్రేత అడిగిన ధర',
  fairRange: 'సరైన శ్రేణి',
  marketRange: 'Market శ్రేణి',
  aiConfidence: 'AI నమ్మకం',
  whatToTellCustomer: 'కస్టమర్‌కి ఏమి చెప్పాలి',
  bridgeToAskTitle: 'మీ quoted price match చేయడానికి',
  playPitch: 'వినండి',
  stopPitch: 'ఆపండి',
  openingLine: 'మొదటి మాట',
  supportingPoints: 'ముఖ్య విషయాలు',
  ifCustomerPushesBack: 'కస్టమర్ ఒప్పుకోకపోతే',
  whatToDoNext: 'తర్వాత ఏమి చేయాలి',
  customerAgreed: 'కస్టమర్ ఒప్పుకున్నారు',
  customerNotAgreed: 'కస్టమర్ ఒప్పుకోలేదు',
  counterOfferTitle: 'కస్టమర్ ధర',
  counterOfferHint: 'కస్టమర్ కోరిన ధరను ఇవ్వండి.',
  customerPriceLabel: 'కస్టమర్ ధర (₹)',
  notesLabel: 'వ్యాఖ్యలు (ఐచ్ఛికం)',
  notesHint: 'కస్టమర్ చెప్పిన విషయాలు రాయండి',
  submitTicket: 'టికెట్ పంపండి',
  allFindings: 'అన్ని ఇన్‌స్పెక్షన్ వివరాలు',
  inspectionScoreLabel: 'ఇన్‌స్పెక్షన్',
  copiedToClipboard: 'కాపీ అయింది',
  reportLoadFailed: 'రిపోర్ట్ లోడ్ కాలేదు.',
  submitFailed: 'పంపలేకపోయాం. మళ్ళీ ప్రయత్నించండి.',
  submittedBadge: 'ఈ ఇన్‌స్పెక్షన్ సమర్పించబడింది',
  exit: 'నిష్క్రమించండి',
  customerLocation: 'కస్టమర్ స్థానం',
  arrivalQuestion: 'మీరు చేరుకున్నారా?',
  arrivalHelp: 'కస్టమర్ వద్దకు చేరిన తర్వాత అవును నొక్కండి.',
  yesArrived: 'అవును, నేను చేరుకున్నాను',
  arrivedConfirmed: 'చేరుకున్నారు — కొనసాగండి',
  notYet: 'ఇంకా కాదు',
  getDirections: 'దారి చూపండి',
  exitInspectionTitle: 'ఇన్‌స్పెక్షన్ ఆపాలా?',
  exitInspectionBody: 'మీ పురోగతి సేవ్ చేయబడుతుంది.',
  stepArrivalTitle: 'రాక',
  stepArrivalInstruction: 'కస్టమర్ వద్దకు చేరిన తర్వాత నిర్ధారించండి.',
  stepRcTitle: 'RC డాక్యుమెంట్',
  stepRcInstruction: 'RC పుస్తకాన్ని ఫ్లాట్‌గా ఉంచి ముఖ్య పేజీ ఫోటో తీయండి.',
  stepClusterTitle: 'డ్యాష్‌బోర్డ్',
  stepClusterInstruction: 'ఇగ్నిషన్ ఆన్ చేయండి. మొత్తం డ్యాష్‌బోర్డ్ ఫోటో తీయండి.',
  stepEngineBayTitle: 'ఇంజిన్ బే',
  stepEngineBayInstruction: 'బోనెట్ తెరవండి. పైనుండి ఇంజిన్ ఫోటో తీయండి.',
  stepFrontTitle: 'ముందు',
  stepFrontInstruction: 'కారు ముందు 2 అడుగులు వెనక్కి. మొత్తం ముందు భాగం తీయండి.',
  stepLeftTitle: 'ఎడమవైపు',
  stepLeftInstruction: 'ఎడమవైపు నిలబడండి. ఒక ఫ్రేమ్‌లో మొత్తం వైపు తీయండి.',
  stepRightTitle: 'కుడివైపు',
  stepRightInstruction: 'కుడివైపు నిలబడండి. ఒక ఫ్రేమ్‌లో మొత్తం వైపు తీయండి.',
  stepRearTitle: 'వెనుక',
  stepRearInstruction: 'కారు వెనుక 2 అడుగులు. మొత్తం వెనుక భాగం తీయండి.',
  stepRoofTitle: 'రూఫ్',
  stepRoofInstruction: 'కారు పక్కన నిలబడి కోణంలో రూఫ్ ఫోటో తీయండి.',
  stepInteriorTitle: 'లోపలి భాగం',
  stepInteriorInstruction: 'డ్రైవర్ డోర్ తెరవండి. సీట్లు మరియు డ్యాష్‌బోర్డ్ కలిపి తీయండి.',
  stepTyresTitle: 'నాలుగు టైర్లు',
  stepTyresInstruction: 'ప్రతి టైర్ దగ్గరగా తీయండి. ట్రెడ్ స్పష్టంగా కనిపించాలి.',
  stepEngineSoundTitle: 'ఇంజిన్ శబ్దం',
  stepEngineSoundInstruction: 'ఇంజిన్ స్టార్ట్ చేయండి. ఫోన్ ఇంజిన్ దగ్గర 15 సెకన్లు పట్టుకోండి.',
  stepTestDriveTitle: 'టెస్ట్ డ్రైవ్',
  stepTestDriveInstruction: 'కారు నడపండి. మాట్లాడుతూ ప్రశ్నలకు సమాధానం ఇవ్వండి. చేతులు స్టీరింగ్ మీద.',
);

const _bn = Translations(
  language: AppLanguage.bengali,
  signIn: 'সাইন ইন',
  otpHint: 'আপনার নম্বরে ৬-অঙ্কের কোড পাঠাব।',
  mobileNumber: 'মোবাইল নম্বর',
  sendOtp: 'OTP পাঠান',
  changeLanguage: 'ভাষা পরিবর্তন',
  poweredBy: 'Cars24 দ্বারা চালিত',
  invalidPhone: 'সঠিক ১০-অঙ্কের নম্বর লিখুন',
  numberNotRegistered: 'এই নম্বরটি নিবন্ধিত নয়।',
  enterCode: 'কোড লিখুন',
  sentTo: 'পাঠানো হয়েছে',
  verify: 'যাচাই করুন',
  resend: 'পাননি? আবার পাঠান',
  otpWrong: 'ভুল OTP। আবার চেষ্টা করুন।',
  chooseLanguage: 'ভাষা নির্বাচন করুন',
  chooseLanguageSub: 'যেটি সহজে পড়তে পারেন তা বেছে নিন।',
  continueLabel: 'এগিয়ে যান',
  todaysInspections: 'আজকের ইন্সপেকশন',
  noInspectionsToday: 'এখনো কোনো ইন্সপেকশন নেই।',
  inspections: 'ইন্সপেকশন',
  pastInspections: 'পুরনো ইন্সপেকশন',
  noInspectionsYet: 'এখনো কোনো ইন্সপেকশন নেই',
  settings: 'সেটিংস',
  profile: 'প্রোফাইল',
  preferences: 'পছন্দসমূহ',
  languageLabel: 'ভাষা',
  account: 'অ্যাকাউন্ট',
  logout: 'লগ আউট',
  logoutConfirmTitle: 'লগ আউট করবেন?',
  logoutConfirmBody: 'আবার সাইন ইন করতে হবে।',
  cancel: 'বাতিল',
  notSet: 'সেট করা নেই',
  navHome: 'হোম',
  navInspections: 'ইন্সপেকশন',
  navSettings: 'সেটিংস',
  navProfile: 'Profile',
  joinedSince: 'Join করেছেন',
  completedInspectionsCount: 'Inspection শেষ করেছেন',
  disableAiAssistant: 'AI assistant বন্ধ করুন',
  disableAiAssistantHint: 'Voice prompts বন্ধ, assistant bar লুকানো।',
  today: 'আজ',
  tomorrow: 'কাল',
  yesterday: 'গতকাল',
  statusScheduled: 'নির্ধারিত',
  statusInProgress: 'চলছে',
  statusCompleted: 'সম্পন্ন',
  kmAway: 'km দূরে',
  noInspectionsForDay: 'এই দিনে কোনো ইন্সপেকশন নেই',
  startInspection: 'শুরু করুন',
  continueInspection: 'চালিয়ে যান',
  viewReport: 'রিপোর্ট দেখুন',
  step: 'ধাপ',
  of: 'এর',
  next: 'পরবর্তী',
  redo: 'আবার করুন',
  retake: 'আবার ছবি তুলুন',
  saveAndFinish: 'সেভ করে শেষ করুন',
  example: 'উদাহরণ',
  tdVerdictGood: 'ভালো ড্রাইভ',
  tdVerdictMinor: 'ছোট সমস্যা',
  tdVerdictConcern: 'মনোযোগ প্রয়োজন',
  tdVerdictCritical: 'গুরুতর সমস্যা',
  tdVerdictInconclusive: 'অনিশ্চিত',
  tdChecksComplete: 'চেক সম্পন্ন',
  tdOverallFeedback: 'সামগ্রিক মতামত',
  tdLoading: 'Loading…',
  tdSavingDrive: 'Test drive save হচ্ছে…',
  tdAdvancing: 'Save হয়েছে. এগিয়ে যাচ্ছি…',
  tdHandsFreeTitle: 'Hands-free drive',
  tdHandsFreeBody: 'Drive করতে করতে আমি ৭টি ছোট প্রশ্ন করব. '
      'শুনে প্রতিটি উত্তর confirm করব. '
      'সাবধানে চালান — চোখ road-এ রাখুন.',
  tdStartDrive: 'Drive শুরু করুন',
  tdNoMoreTaps: 'এরপর আর tap লাগবে না — drive safe',
  tdOverallFeedbackHeader: 'সামগ্রিক মতামত',
  tdAsking: 'জিজ্ঞাসা করছি…',
  tdListenCarefully: 'মনোযোগ দিয়ে শুনুন',
  tdTranscribing: 'শুনছি…',
  tdHearingWhat: 'আপনি যা বললেন বুঝছি',
  tdUnderstanding: 'বুঝছি…',
  tdGotIt: 'বুঝতে পারলাম',
  tdWrappingUp: 'শেষ করছি…',
  tdSpeakAnswer: 'আপনার উত্তর বলুন',
  tdPlay: 'Play',
  tdPlaying: 'Play হচ্ছে',
  tdStartOver: 'আবার শুরু করুন',
  tdSomethingWrong: 'কিছু সমস্যা হয়েছে.',
  tdMicPermissionNeeded: 'Test drive-এর জন্য microphone permission প্রয়োজন.',
  couldNotLoadInspections: 'Inspections load করা যায়নি',
  cameraAccessNeeded: 'Camera permission প্রয়োজন. Settings থেকে allow করুন.',
  useThis: 'এটাই রাখুন',
  reRecord: 'আবার record করুন',
  tapToRecord: 'Record করতে নিচের button চাপুন',
  useRcValues: 'RC-র values রাখুন',
  carDetailsDiffer: 'Car-এর details আলাদা',
  useRcValuesBody: 'RC card-এ booking-এর চেয়ে আলাদা values দেখাচ্ছে. '
      'Confirm করলে বাকি inspection RC-এর values দিয়ে হবে.',
  couldNotSave: 'Save করা যায়নি',
  couldNotOpenMaps: 'Maps app খোলা যায়নি',
  tdVerdictLabel: 'রায়',
  reviewTitle: 'সংগৃহীত তথ্য পর্যালোচনা',
  viewInspectionTitle: 'Inspection-এর বিবরণ',
  outcomeAccepted: 'Customer রাজি হয়েছেন',
  outcomeCountered: 'Counter-offer',
  outcomeDeclined: 'Customer প্রত্যাখ্যান করেছেন',
  finalPriceLabel: 'Final price',
  reviewSubtitle: 'AI দিয়ে দাম দেওয়ার আগে প্রতিটি ধাপ দেখুন।',
  confirmAndAnalyze: 'নিশ্চিত করুন ও দাম নিন',
  reviewLoadFailed: 'তথ্য লোড করা যায়নি।',
  reviewStepIncomplete: 'তোলা হয়নি',
  reportTitle: 'ইন্সপেকশন রিপোর্ট',
  preparingReport: 'রিপোর্ট তৈরি হচ্ছে — AI গাড়ির দাম ঠিক করছে…',
  tryAgain: 'আবার চেষ্টা করুন',
  estimatedPrice: 'অনুমানিত দাম',
  sellerQuoted: 'বিক্রেতার দাম',
  fairRange: 'ন্যায্য রেঞ্জ',
  marketRange: 'Market রেঞ্জ',
  aiConfidence: 'AI বিশ্বাস',
  whatToTellCustomer: 'কাস্টমারকে কী বলবেন',
  bridgeToAskTitle: 'আপনার quoted price match করতে',
  playPitch: 'শুনুন',
  stopPitch: 'থামান',
  openingLine: 'প্রথম বাক্য',
  supportingPoints: 'মূল কথা',
  ifCustomerPushesBack: 'কাস্টমার রাজি না হলে',
  whatToDoNext: 'এরপর কী করবেন',
  customerAgreed: 'কাস্টমার রাজি',
  customerNotAgreed: 'কাস্টমার রাজি নন',
  counterOfferTitle: 'কাস্টমারের দাম',
  counterOfferHint: 'কাস্টমার যে দাম চান সেটা লিখুন।',
  customerPriceLabel: 'কাস্টমার দাম (₹)',
  notesLabel: 'নোট (ঐচ্ছিক)',
  notesHint: 'কাস্টমার যা বলেছেন তা লিখুন',
  submitTicket: 'টিকেট পাঠান',
  allFindings: 'সব ইন্সপেকশন তথ্য',
  inspectionScoreLabel: 'ইন্সপেকশন',
  copiedToClipboard: 'কপি হয়েছে',
  reportLoadFailed: 'রিপোর্ট লোড করা যায়নি।',
  submitFailed: 'পাঠানো যায়নি। আবার চেষ্টা করুন।',
  submittedBadge: 'এই ইন্সপেকশন জমা দেওয়া হয়েছে',
  exit: 'প্রস্থান',
  customerLocation: 'গ্রাহকের অবস্থান',
  arrivalQuestion: 'আপনি কি পৌঁছেছেন?',
  arrivalHelp: 'গ্রাহকের কাছে পৌঁছানোর পর হ্যাঁ চাপুন।',
  yesArrived: 'হ্যাঁ, আমি এসেছি',
  arrivedConfirmed: 'পৌঁছেছেন — এগিয়ে যান',
  notYet: 'এখনো নয়',
  getDirections: 'পথ দেখাও',
  exitInspectionTitle: 'ইন্সপেকশন বন্ধ করবেন?',
  exitInspectionBody: 'আপনার অগ্রগতি সংরক্ষিত থাকবে।',
  stepArrivalTitle: 'পৌঁছানো',
  stepArrivalInstruction: 'গ্রাহকের কাছে পৌঁছানোর পর নিশ্চিত করুন।',
  stepRcTitle: 'RC ডকুমেন্ট',
  stepRcInstruction: 'RC বইটি সমতল রেখে মূল পৃষ্ঠার ছবি তুলুন।',
  stepClusterTitle: 'ড্যাশবোর্ড',
  stepClusterInstruction: 'গাড়ি চালু করুন। পুরো ড্যাশবোর্ডের ছবি তুলুন।',
  stepEngineBayTitle: 'ইঞ্জিন',
  stepEngineBayInstruction: 'বনেট খুলুন। উপর থেকে ইঞ্জিনের ছবি তুলুন।',
  stepFrontTitle: 'সামনের ছবি',
  stepFrontInstruction: 'গাড়ির সামনে ২ পা পিছিয়ে যান। পুরো সামনের ছবি তুলুন।',
  stepLeftTitle: 'বাঁ দিক',
  stepLeftInstruction: 'বাঁ দিকে দাঁড়ান। এক ফ্রেমে পুরো দিকটি ক্যাপচার করুন।',
  stepRightTitle: 'ডান দিক',
  stepRightInstruction: 'ডান দিকে দাঁড়ান। এক ফ্রেমে পুরো দিকটি ক্যাপচার করুন।',
  stepRearTitle: 'পিছনের ছবি',
  stepRearInstruction: 'গাড়ির পিছনে ২ পা দূরে যান। পুরো পিছনের ছবি তুলুন।',
  stepRoofTitle: 'ছাদ',
  stepRoofInstruction: 'গাড়ির পাশে দাঁড়িয়ে কোণ থেকে ছাদের ছবি তুলুন।',
  stepInteriorTitle: 'ভেতর',
  stepInteriorInstruction: 'চালকের দরজা খুলুন। সিট ও ড্যাশবোর্ড একসাথে তুলুন।',
  stepTyresTitle: 'চারটি টায়ার',
  stepTyresInstruction: 'প্রতিটি টায়ার কাছ থেকে তুলুন। ট্রেড স্পষ্ট দেখা যেতে হবে।',
  stepEngineSoundTitle: 'ইঞ্জিনের শব্দ',
  stepEngineSoundInstruction: 'ইঞ্জিন চালু করুন। ফোনটি ইঞ্জিনের কাছে ১৫ সেকেন্ড ধরুন।',
  stepTestDriveTitle: 'টেস্ট ড্রাইভ',
  stepTestDriveInstruction: 'গাড়ি চালান। কথা বলে প্রশ্নের উত্তর দিন। হাত স্টিয়ারিংয়ে রাখুন।',
);
