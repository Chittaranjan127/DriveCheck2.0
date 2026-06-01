import '../../core/services/language_service.dart';

/// Per-language strings used in the profile completion flow. Kept local to the
/// feature instead of polluting the global Translations class.
class ProfileStrings {
  final String whatsYourName;
  final String nameHint;
  final String tapMicToSpeak;
  final String listening;
  final String continueLabel;
  final String takeSelfie;
  final String selfieHint;
  final String tapToCapture;
  final String retake;
  final String useThisPhoto;
  final String uploading;
  final String saving;
  final String permissionDenied;
  final String tryAgain;
  final String profile;
  final String editName;
  final String yourPhone;
  final String yourEmail;
  final String yourRole;
  final String yourStatus;
  final String yourEmployeeId;
  final String memberSince;
  final String save;
  final String cancel;
  final String logout;
  final String replay;
  final String nameField;
  final String notFilled;
  final String didntCatch;

  const ProfileStrings({
    required this.whatsYourName,
    required this.nameHint,
    required this.tapMicToSpeak,
    required this.listening,
    required this.continueLabel,
    required this.takeSelfie,
    required this.selfieHint,
    required this.tapToCapture,
    required this.retake,
    required this.useThisPhoto,
    required this.uploading,
    required this.saving,
    required this.permissionDenied,
    required this.tryAgain,
    required this.profile,
    required this.editName,
    required this.yourPhone,
    required this.yourEmail,
    required this.yourRole,
    required this.yourStatus,
    required this.yourEmployeeId,
    required this.memberSince,
    required this.save,
    required this.cancel,
    required this.logout,
    required this.replay,
    required this.nameField,
    required this.notFilled,
    required this.didntCatch,
  });

  static const _en = ProfileStrings(
    whatsYourName: "What's your name?",
    nameHint: 'Tap mic or type below',
    tapMicToSpeak: 'Tap mic to speak',
    listening: 'Listening…',
    continueLabel: 'Continue',
    takeSelfie: 'Take a selfie',
    selfieHint: 'We use this to confirm it is you',
    tapToCapture: 'Tap to capture',
    retake: 'Retake',
    useThisPhoto: 'Use this photo',
    uploading: 'Uploading…',
    saving: 'Saving…',
    permissionDenied: 'Permission denied',
    tryAgain: 'Try again',
    profile: 'Profile',
    editName: 'Edit name',
    yourPhone: 'Phone',
    yourEmail: 'Email',
    yourRole: 'Role',
    yourStatus: 'Status',
    yourEmployeeId: 'Employee ID',
    memberSince: 'Member since',
    save: 'Save',
    cancel: 'Cancel',
    logout: 'Logout',
    replay: 'Replay',
    nameField: 'Your name',
    notFilled: 'Not set',
    didntCatch: "Didn't catch that — try again",
  );

  static const _hi = ProfileStrings(
    whatsYourName: 'Aapka naam kya hai?',
    nameHint: 'Mic dabaiye ya neeche likhiye',
    tapMicToSpeak: 'Bolne ke liye mic dabaiye',
    listening: 'Sun raha hoon…',
    continueLabel: 'Aage badhein',
    takeSelfie: 'Selfie lijiye',
    selfieHint: 'Yeh aapko pehchaanne ke liye hai',
    tapToCapture: 'Photo lene ke liye dabaiye',
    retake: 'Phir se',
    useThisPhoto: 'Yeh photo theek hai',
    uploading: 'Bhej rahe hain…',
    saving: 'Save ho raha hai…',
    permissionDenied: 'Anumati nahin mili',
    tryAgain: 'Dobara koshish karein',
    profile: 'Profile',
    editName: 'Naam badlein',
    yourPhone: 'Phone',
    yourEmail: 'Email',
    yourRole: 'Bhumika',
    yourStatus: 'Sthiti',
    yourEmployeeId: 'Employee ID',
    memberSince: 'Tabse sadasya',
    save: 'Save karein',
    cancel: 'Radd karein',
    logout: 'Logout',
    replay: 'Phir se sunein',
    nameField: 'Aapka naam',
    notFilled: 'Bhara nahin',
    didntCatch: 'Sun nahin paaya — phir se boliye',
  );

  static const _te = ProfileStrings(
    whatsYourName: 'Mee peru emiti?',
    nameHint: 'Mic notnu nokku leda type cheyandi',
    tapMicToSpeak: 'Matladataniki mic nokkandi',
    listening: 'Vintunnanu…',
    continueLabel: 'Munduku',
    takeSelfie: 'Selfie teesukondi',
    selfieHint: 'Mimmalni gurtinchadaniki',
    tapToCapture: 'Capture cheyandi',
    retake: 'Marala',
    useThisPhoto: 'Idi vaadandi',
    uploading: 'Pampistunnam…',
    saving: 'Save avtundi…',
    permissionDenied: 'Anumati ledu',
    tryAgain: 'Marala prayatnam',
    profile: 'Profile',
    editName: 'Peru marchandi',
    yourPhone: 'Phone',
    yourEmail: 'Email',
    yourRole: 'Padavi',
    yourStatus: 'Sthithi',
    yourEmployeeId: 'Employee ID',
    memberSince: 'Sabhyudai naatinunchi',
    save: 'Save cheyandi',
    cancel: 'Radd cheyandi',
    logout: 'Logout',
    replay: 'Marala vinandi',
    nameField: 'Mee peru',
    notFilled: 'Nimpaledu',
    didntCatch: 'Vinabadaledu — marala cheppandi',
  );

  static const _bn = ProfileStrings(
    whatsYourName: 'Apnar naam ki?',
    nameHint: 'Mic chapun na hole likhun',
    tapMicToSpeak: 'Bolar jonno mic chapun',
    listening: 'Sunchhi…',
    continueLabel: 'Egiye chalun',
    takeSelfie: 'Selfie tulun',
    selfieHint: 'Aapnake chinte rakhar jonno',
    tapToCapture: 'Tulte chapun',
    retake: 'Abar tulun',
    useThisPhoto: 'Ei chhobi thik aache',
    uploading: 'Pathachhi…',
    saving: 'Save hochche…',
    permissionDenied: 'Anumati pawar jayni',
    tryAgain: 'Abar chesta korun',
    profile: 'Profile',
    editName: 'Naam paribartan korun',
    yourPhone: 'Phone',
    yourEmail: 'Email',
    yourRole: 'Bhumika',
    yourStatus: 'Abastha',
    yourEmployeeId: 'Employee ID',
    memberSince: 'Sadasya hoyechen',
    save: 'Save korun',
    cancel: 'Batil korun',
    logout: 'Logout',
    replay: 'Abar sunun',
    nameField: 'Apnar naam',
    notFilled: 'Bhara hoyni',
    didntCatch: 'Sunte parini — abar bolun',
  );

  static ProfileStrings of(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.english: return _en;
      case AppLanguage.hindi:   return _hi;
      case AppLanguage.telugu:  return _te;
      case AppLanguage.bengali: return _bn;
    }
  }
}
