# DriveCheck
### Cars24 AI Inspection Copilot

> Token '26 Hackathon — Problem Statement 3
> Built with Flutter · Node.js · OpenAI GPT-4o · ElevenLabs · AWS (SAM + Lambda + DynamoDB + AppSync)

---

## What is DriveCheck?

DriveCheck is a voice-and-vision AI copilot for Cars24 Car Jockeys.

A Car Jockey is a trained Cars24 evaluator who drives to a customer's home and inspects their car before Cars24 makes a purchase offer. Today this inspection is long, inconsistent, and fully dependent on the jockey's training and memory.

DriveCheck solves this by guiding the jockey through every step of the inspection using voice instructions in Hindi, analyzing every photo and audio capture using AI, and auto-filling all 73 inspection checkpoints without the jockey typing a single character. At the end, it generates a realistic price estimate explained in plain Hindi.

A first-day jockey with zero prior experience can complete a full, accurate inspection using only this app.

---

## User profile

**Who uses this app:**
- Cars24 Car Jockeys — field evaluators who visit customer homes
- Age group: 20–40 years
- Education: 10th pass or below in many cases
- Language: Hindi primary, may know basic English
- Tech comfort: Uses WhatsApp and YouTube daily. Not comfortable with complex apps.
- Work context: Standing outside in sunlight, hands often busy with the car, cannot read long instructions

**What this means for the app:**
- Voice is the primary interface — not text
- One action per screen — never two things at once
- Large buttons, high contrast, simple icons
- All instructions in Hindi, short sentences only
- App must work without internet for short periods (offline-first for step progress)
- No passwords — OTP login only via phone number

---

## Language support

DriveCheck supports two languages. Hindi is the default.

| Surface | Hindi | English |
|---|---|---|
| Voice instructions | Yes — primary | Yes — fallback |
| On-screen labels | Yes | Yes |
| AI feedback messages | Yes | Yes |
| Report summary | Yes | Yes |
| Error messages | Yes | Yes |

**Language switch:** Jockey can toggle between Hindi and English from the home screen. Preference is saved locally. The app remembers their choice across sessions.

**Hindi rendering:** Uses `NotoSansDevanagari` font from Google Fonts. All Hindi strings live in `app_strings.dart` — never hardcoded in widgets.

**Voice language:** ElevenLabs TTS uses a Hindi-capable voice. All instruction text passed to ElevenLabs is in Hindi by default. English fallback uses a standard English voice.

---

## Brand and theme

### Cars24 colors
```dart
// lib/core/theme/app_colors.dart

class AppColors {
  // Cars24 brand
  static const primary       = Color(0xFFE63946); // Cars24 red
  static const primaryDark   = Color(0xFFC1121F); // Pressed state
  static const onPrimary     = Color(0xFFFFFFFF);
  static const surface       = Color(0xFFFFFFFF);
  static const background    = Color(0xFFF5F5F5);
  static const card          = Color(0xFFFFFFFF);

  // Text
  static const textPrimary   = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF6B6B6B);
  static const textHint      = Color(0xFF9E9E9E);
  static const textOnDark    = Color(0xFFFFFFFF);

  // Status — used for AI feedback cards
  static const success       = Color(0xFF2ECC71); // good photo
  static const warning       = Color(0xFFF39C12); // minor defect
  static const error         = Color(0xFFE74C3C); // retake needed
  static const info          = Color(0xFF3498DB);  // neutral info

  // Step progress
  static const stepDone      = Color(0xFF2ECC71);
  static const stepActive    = Color(0xFFE63946);
  static const stepPending   = Color(0xFFE0E0E0);
}
```

### Typography
```dart
// lib/core/theme/app_text_styles.dart
// Uses Poppins for English, NotoSansDevanagari for Hindi

class AppTextStyles {
  static TextStyle heading1  = GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w600);
  static TextStyle heading2  = GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600);
  static TextStyle heading3  = GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500);
  static TextStyle body      = GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w400);
  static TextStyle caption   = GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary);
  static TextStyle button    = GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.onPrimary);

  // Hindi text styles
  static TextStyle hindiLarge  = GoogleFonts.notoSansDevanagari(fontSize: 20, fontWeight: FontWeight.w600);
  static TextStyle hindiBody   = GoogleFonts.notoSansDevanagari(fontSize: 16, fontWeight: FontWeight.w500);
  static TextStyle hindiSmall  = GoogleFonts.notoSansDevanagari(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary);
}
```

### Logo
```
File: assets/images/cars24_logo.png
Source: Download from cars24.com
App icon: Cars24 red background + white checkmark icon
App name shown on splash: "DriveCheck" in Poppins bold
Tagline on splash: "Drive karo, check ho jaayega" in NotoSansDevanagari
```

---

## Project structure

```
lib/
├── main.dart                            # Entry point — dotenv load + ProviderScope
├── app.dart                             # MaterialApp + GoRouter setup
│
├── core/
│   ├── theme/
│   │   ├── app_colors.dart              # All colors — edit here only
│   │   ├── app_text_styles.dart         # All text styles
│   │   └── app_theme.dart               # ThemeData assembled from above
│   │
│   ├── constants/
│   │   ├── api_endpoints.dart           # All backend URLs
│   │   ├── app_strings.dart             # ALL Hindi + English strings
│   │   └── inspection_config.dart       # 12 capture steps config
│   │
│   ├── models/
│   │   ├── jockey.dart                  # Jockey profile
│   │   ├── inspection.dart              # Inspection session
│   │   ├── capture_step.dart            # One step definition
│   │   ├── ai_result.dart               # GPT-4o response shape
│   │   ├── defect.dart                  # One detected defect
│   │   └── inspection_report.dart       # Final compiled report
│   │
│   └── services/
│       ├── api_service.dart             # All HTTP calls to backend
│       ├── camera_service.dart          # Photo capture + compression
│       ├── audio_service.dart           # ElevenLabs TTS playback
│       ├── voice_service.dart           # Whisper recording
│       ├── storage_service.dart         # SharedPreferences wrapper
│       └── language_service.dart        # Hindi/English toggle
│
├── features/
│   ├── auth/
│   │   ├── splash_screen.dart           # Cars24 logo + tagline
│   │   ├── login_screen.dart            # Phone number entry
│   │   ├── otp_screen.dart              # OTP verification
│   │   └── auth_provider.dart           # AuthState machine (OTP REST flow)
│   │
│   ├── home/
│   │   ├── home_screen.dart             # Today's inspection list
│   │   ├── inspection_card.dart         # One car card
│   │   └── home_provider.dart           # Fetch today's jobs
│   │
│   ├── inspection/
│   │   ├── inspection_screen.dart       # Main step navigator shell
│   │   ├── inspection_provider.dart     # Step state + progress
│   │   │
│   │   ├── capture/
│   │   │   ├── photo_capture_screen.dart   # Camera + AI analysis
│   │   │   ├── audio_capture_screen.dart   # Engine sound recording
│   │   │   └── capture_provider.dart       # Upload + analyze state
│   │   │
│   │   └── widgets/
│   │       ├── step_progress_bar.dart      # Top progress indicator
│   │       ├── voice_instruction_bar.dart  # Auto-plays Hindi audio
│   │       ├── reference_image_card.dart   # Shows correct capture angle
│   │       ├── ai_feedback_card.dart       # Real-time AI result
│   │       ├── capture_button.dart         # Large red action button
│   │       └── retake_overlay.dart         # Blur/dark photo prompt
│   │
│   ├── test_drive/
│   │   ├── test_drive_screen.dart       # Hands-free voice Q&A
│   │   ├── question_card.dart           # Current question display
│   │   └── test_drive_provider.dart     # Recording + answer state
│   │
│   └── report/
│       ├── report_screen.dart           # Final summary
│       ├── score_ring_widget.dart       # Animated 0–100 score ring
│       ├── defect_list_widget.dart      # Defects by section
│       ├── price_card_widget.dart       # Price range in bold
│       └── report_provider.dart         # Generate + submit
│
└── shared/
    ├── widgets/
    │   ├── drivecheck_app_bar.dart      # Top bar with Cars24 logo
    │   ├── primary_button.dart          # Red Cars24 button
    │   ├── loading_overlay.dart         # Full screen loader
    │   ├── error_snackbar.dart          # Error toast
    │   └── section_header.dart          # Hindi + English section label
    └── extensions/
        └── context_extensions.dart      # BuildContext helpers
```

---

## Auth setup

DriveCheck uses our own backend for OTP login (the SAM stack in
`drivecheck-backend/`). No Firebase. No passwords. No email. Phone
number only.

### Backend endpoints
```
POST /auth/request-otp   { phoneNumber }
   → writes a one-shot 6-digit code into the UserOTPManager DDB
     table (TTL 5 min). In dev the response also returns `mockOtp`
     so the OTP screen can pre-fill it for the demo.

POST /auth/verify-otp    { phoneNumber, otp, deviceInfo?, fcmToken? }
   → burns the OTP row, upserts the User row, creates a
     UserSessions row, returns { token, user, sessionId }.
     The token is a JWT (30 d, jti = sessionId) signed by the
     Lambda layer.

GET  /auth/me            (Authorization: Bearer <jwt>)
POST /auth/logout        (sets revokedAt on the session row)
```

### Flutter packages
```yaml
# Real-network auth only — no firebase_core / firebase_auth.
dio: ^5.x                  # API client (x-api-key + bearer interceptor)
shared_preferences: ^2.x   # JWT persistence
```

### Auth flow
```
Splash
   ↓
AuthNotifier.restore() → GET /auth/me with cached JWT
   ↓
Has session? → /home   (or /language if user never picked one)
No session?  → /login
   ↓
Jockey enters phone (10 digits, no country code)
   ↓
POST /auth/request-otp   →  banner shows the dev mockOtp
   ↓
Jockey enters 6-digit OTP
   ↓
POST /auth/verify-otp    →  { token, user, sessionId }
   ↓
AuthTokenHolder.write(token); state = AuthAuthenticated(user)
   ↓
Profile-setup wizard if incomplete (name + selfie), else /home
```

### Auth state machine
The Riverpod `AuthNotifier` is a plain `Notifier<AuthState>` with a
sealed union (see `lib/features/auth/auth_state.dart`):
`AuthInitial · AuthLoading · AuthOtpSending · AuthOtpSent ·
AuthVerifying · AuthAuthenticated · AuthUnauthenticated · AuthError`.

Screens render off the state's runtime type; the notifier calls
`AuthService` (a thin Dio wrapper) for the actual network. There is
no `FirebaseAuth.instance.authStateChanges()` listener — token
restoration happens explicitly at app start via `restore()`, and
logout calls `POST /auth/logout` + clears the local token + clears
the saved language so the next sign-in re-runs the chooser.

---

## Inspection steps config

12 captures cover all 73 schema checkpoints.
Add or change steps here only — never hardcode step logic in screens.

```dart
// lib/core/constants/inspection_config.dart

const List<CaptureStep> kInspectionSteps = [

  CaptureStep(
    id: 'rc_document',
    section: StepSection.documents,
    titleEn: 'RC document',
    titleHi: 'RC book',
    instructionEn: 'Place the RC book flat and photograph the main page clearly.',
    instructionHi: 'RC book ko seedha rakhein aur poori photo lo.',
    referenceImagePath: 'assets/references/rc_document.jpg',
    captureType: CaptureType.photo,
    compressionQuality: 85,
  ),

  CaptureStep(
    id: 'instrument_cluster',
    section: StepSection.interior,
    titleEn: 'Instrument cluster',
    titleHi: 'Dashboard',
    instructionEn: 'Sit inside the car. Turn ignition on. Photograph the full dashboard.',
    instructionHi: 'Gaadi ke andar baitho. Ignition on karo. Dashboard ki poori photo lo.',
    referenceImagePath: 'assets/references/instrument_cluster.jpg',
    captureType: CaptureType.photo,
    compressionQuality: 80,
  ),

  CaptureStep(
    id: 'engine_bay',
    section: StepSection.mechanical,
    titleEn: 'Engine bay',
    titleHi: 'Engine',
    instructionEn: 'Open the bonnet. Stand at the front and photograph the engine from above.',
    instructionHi: 'Bonnet kholo. Engine ke upar se poori photo lo.',
    referenceImagePath: 'assets/references/engine_bay.jpg',
    captureType: CaptureType.photo,
    compressionQuality: 75,
  ),

  CaptureStep(
    id: 'front_full',
    section: StepSection.exterior,
    titleEn: 'Front view',
    titleHi: 'Aage se photo',
    instructionEn: 'Stand 2 steps in front of the car. Capture the full front.',
    instructionHi: 'Gaadi ke saamne do kadam peeche jao. Poori aage ki photo lo.',
    referenceImagePath: 'assets/references/front_full.jpg',
    captureType: CaptureType.photo,
    compressionQuality: 75,
  ),

  CaptureStep(
    id: 'lhs_full',
    section: StepSection.exterior,
    titleEn: 'Left side',
    titleHi: 'Baayein taraf',
    instructionEn: 'Stand on the left side. Capture the full side in one frame.',
    instructionHi: 'Gaadi ke baayein taraf jao. Poori side ek photo mein lo.',
    referenceImagePath: 'assets/references/lhs_full.jpg',
    captureType: CaptureType.photo,
    compressionQuality: 75,
  ),

  CaptureStep(
    id: 'rhs_full',
    section: StepSection.exterior,
    titleEn: 'Right side',
    titleHi: 'Daayein taraf',
    instructionEn: 'Stand on the right side. Capture the full side in one frame.',
    instructionHi: 'Gaadi ke daayein taraf jao. Poori side ek photo mein lo.',
    referenceImagePath: 'assets/references/rhs_full.jpg',
    captureType: CaptureType.photo,
    compressionQuality: 75,
  ),

  CaptureStep(
    id: 'rear_full',
    section: StepSection.exterior,
    titleEn: 'Rear view',
    titleHi: 'Peeche se photo',
    instructionEn: 'Stand 2 steps behind the car. Capture the full rear.',
    instructionHi: 'Gaadi ke peeche do kadam door jao. Poori peeche ki photo lo.',
    referenceImagePath: 'assets/references/rear_full.jpg',
    captureType: CaptureType.photo,
    compressionQuality: 75,
  ),

  CaptureStep(
    id: 'roof',
    section: StepSection.exterior,
    titleEn: 'Roof',
    titleHi: 'Chhat',
    instructionEn: 'Stand beside the car and photograph the roof at an angle.',
    instructionHi: 'Gaadi ke baaju khade ho. Upar se chhat ki photo lo.',
    referenceImagePath: 'assets/references/roof.jpg',
    captureType: CaptureType.photo,
    compressionQuality: 75,
  ),

  CaptureStep(
    id: 'interior',
    section: StepSection.interior,
    titleEn: 'Interior',
    titleHi: 'Andar',
    instructionEn: 'Open the driver door. Photograph the seats and dashboard together.',
    instructionHi: 'Darwaza kholo. Seats aur dashboard ek saath photo mein aane chahiye.',
    referenceImagePath: 'assets/references/interior.jpg',
    captureType: CaptureType.photo,
    compressionQuality: 75,
  ),

  CaptureStep(
    id: 'tyres',
    section: StepSection.exterior,
    titleEn: 'All 4 tyres',
    titleHi: 'Charon tyre',
    instructionEn: 'Photograph each tyre close up. Tread must be clearly visible.',
    instructionHi: 'Har tyre ke paas jao. Rubber ka hissa clearly dikhna chahiye.',
    referenceImagePath: 'assets/references/tyre.jpg',
    captureType: CaptureType.multiPhoto,
    photoCount: 4,
    compressionQuality: 80,
  ),

  CaptureStep(
    id: 'engine_sound',
    section: StepSection.mechanical,
    titleEn: 'Engine sound',
    titleHi: 'Engine ki awaaz',
    instructionEn: 'Start the engine. Hold the phone near the engine for 15 seconds.',
    instructionHi: 'Engine chalu karo. Phone ko engine ke paas rakho. 15 second record karo.',
    referenceImagePath: 'assets/references/engine_sound.jpg',
    captureType: CaptureType.audio,
    audioDurationSeconds: 15,
    compressionQuality: 0,
  ),

  CaptureStep(
    id: 'test_drive',
    section: StepSection.testDrive,
    titleEn: 'Test drive',
    titleHi: 'Test drive',
    instructionEn: 'Drive the car. Answer questions by speaking. Keep hands on the wheel.',
    instructionHi: 'Gaadi chalao. Sawaalon ke jawab bolte raho. Haath steering par rakhna.',
    referenceImagePath: 'assets/references/test_drive.jpg',
    captureType: CaptureType.voiceQA,
    compressionQuality: 0,
  ),
];
```

---

## All app strings

Every string the user sees lives here. Never hardcode text in widgets.

```dart
// lib/core/constants/app_strings.dart

class AppStrings {

  // ── Splash ────────────────────────────────────────────
  static const appName       = 'DriveCheck';
  static const appTaglineHi  = 'Drive karo, check ho jaayega';
  static const appTaglineEn  = 'Drive it. Check it. Done.';
  static const poweredBy     = 'Powered by Cars24';

  // ── Auth ──────────────────────────────────────────────
  static const enterPhone    = 'Mobile number daalo';
  static const enterPhoneEn  = 'Enter mobile number';
  static const sendOtp       = 'OTP bhejo';
  static const enterOtp      = '6-digit OTP daalo';
  static const verifyOtp     = 'Verify karo';
  static const resendOtp     = 'OTP dobara bhejo';
  static const otpSent       = 'OTP bhej diya gaya';
  static const otpError      = 'OTP galat hai. Dobara try karo.';
  static const phoneError    = 'Sahi number daalo';

  // ── Home ──────────────────────────────────────────────
  static const greeting      = 'Namaste'; // + jockey name
  static const todaysJobs    = 'Aaj ke inspections';
  static const todaysJobsEn  = "Today's inspections";
  static const noJobs        = 'Aaj koi inspection nahi hai';
  static const startInspect  = 'Inspection shuru karo';
  static const kmAway        = 'km door';
  static const carDetails    = 'Gaadi ki jaankari';

  // ── Inspection ────────────────────────────────────────
  static const stepProgress  = 'Step'; // "Step 3 / 12"
  static const of            = '/';
  static const capture       = 'Photo lo';
  static const record        = 'Record karo';
  static const next          = 'Aage badho';
  static const retake        = 'Dobara lo';
  static const analyzing     = 'Dekh raha hoon...';
  static const uploading     = 'Upload ho raha hai...';

  // AI feedback — good
  static const photoGood     = 'Acchi photo!';
  static const audioGood     = 'Acchi recording!';

  // AI feedback — retake reasons
  static const blurry        = 'Photo blur hai. Thoda door jao aur phir lo.';
  static const tooDark       = 'Photo andheri hai. Roshni mein jao.';
  static const partial       = 'Poori cheez frame mein nahi hai. Peeche jao.';
  static const audioShort    = 'Recording bahut choti hai. 15 second record karo.';
  static const audioNoEngine = 'Engine ki awaaz nahi aayi. Engine chalu karo.';

  // AI results spoken aloud
  static const kmFound       = 'KM reading nota ho gayi.';
  static const warningFound  = 'Warning light mili. Note kar li.';
  static const defectFound   = 'Kharabi mili. Note kar li.';
  static const allClear      = 'Sab theek lag raha hai.';

  // ── Test drive ────────────────────────────────────────
  static const testDriveStart  = 'Gaadi chalao. Main sawaal poochhta hoon.';
  static const listening        = 'Sun raha hoon...';
  static const answerSaved      = 'Jawab nota ho gaya.';
  static const nextQuestion     = 'Agla sawaal.';
  static const testDriveDone    = 'Test drive khatam. Bahut accha kiya!';

  // Test drive questions in Hindi
  static const List<String> testDriveQuestionsHi = [
    'Brake dabao. Smooth hai ya hard?',
    'Clutch kaisa lag raha hai? Smooth hai ya tight?',
    'Gear change karo. Smooth shift ho raha hai?',
    'Steering seedha ja raha hai? Koi vibration?',
    'Indicators on karo. Dono taraf chal rahe hain?',
    'AC on karo. Thanda aa raha hai?',
    'Koi awaaz aa rahi hai engine se chalate waqt?',
  ];

  static const List<String> testDriveQuestionsEn = [
    'Press the brake. Is it smooth or hard?',
    'How does the clutch feel? Smooth or tight?',
    'Change gears. Is the shift smooth?',
    'Is the steering straight? Any vibration?',
    'Turn on indicators. Do both sides work?',
    'Turn on AC. Is it cooling?',
    'Any unusual sounds from the engine while driving?',
  ];

  // ── Report ────────────────────────────────────────────
  static const reportReady     = 'Inspection poori hui!';
  static const conditionScore  = 'Condition score';
  static const excellent       = 'Bahut acchi condition';
  static const good            = 'Acchi condition';
  static const fair            = 'Theek condition';
  static const average         = 'Thodi kharabi hai';
  static const poor            = 'Zyada kharabi hai';
  static const estimatedPrice  = 'Estimated price';
  static const deductions      = 'Katoti ki wajah';
  static const submitReport    = 'Report bhejo';
  static const reportSent      = 'Report bhej di gayi!';
  static const reportError     = 'Report nahi gayi. Dobara try karo.';

  // ── Errors ────────────────────────────────────────────
  static const noInternet      = 'Internet nahi hai. Check karo.';
  static const serverError     = 'Kuch gadbad hui. Dobara try karo.';
  static const cameraError     = 'Camera nahi khula. Permission do.';
  static const micError        = 'Mic nahi khula. Permission do.';
  static const tryAgain        = 'Dobara try karo';
}
```

---

## Media compression rules

All media is compressed on-device before leaving the phone.
Raw camera output is never sent to the API.

```dart
// lib/core/services/camera_service.dart

/// Step-specific compression quality.
/// Documents need higher quality for OCR accuracy.
/// Exterior panels can be more compressed — AI reads shapes not text.
const Map<String, int> kCompressionByStep = {
  'rc_document':          85,  // OCR needs clarity
  'instrument_cluster':   80,  // needs to read numbers
  'engine_bay':           75,
  'front_full':           75,
  'lhs_full':             75,
  'rhs_full':             75,
  'rear_full':            75,
  'roof':                 75,
  'interior':             75,
  'tyres':                80,  // tread detail matters
};

/// Thumbnail quality used only for the blur pre-check.
/// Costs almost nothing in API credits.
const int kThumbnailQuality = 40;
const int kThumbnailMaxWidth = 400;
```

**Two-stage upload rule:**
1. Compress to thumbnail → send for blur check → if bad, ask jockey to retake (no full upload wasted)
2. Compress to full working quality → upload to S3 → send S3 URL to AI for analysis

---

## Coding standards

Follow these rules for every file in the project.
Code should read like a human wrote it for another human to maintain.

### File size
- Max 200 lines per file. If longer, split into smaller widgets or helpers.
- One class per file. File name matches class name in snake_case.

### Naming
- Variables and functions: clear, descriptive. `isPhotoBlurry` not `flag`.
- Booleans always start with: is, has, can, should. Example: `isLoading`, `hasError`, `canSubmit`.
- Constants: `kConstantName` prefix. Example: `kInspectionSteps`, `kCompressionByStep`.
- Private methods: underscore prefix. Example: `_playVoiceInstruction`.

### Logic placement
- No business logic inside `build()` methods.
- No API calls inside `initState()` directly — use `ref.read` in a `Future.delayed(Duration.zero)` callback or in a button handler.
- All logic goes in Riverpod notifiers.
- Widgets only render state — they never compute it.

### Error handling
- Every async method wraps the body in try/catch.
- Never let exceptions reach the UI silently.
- Show a Hindi error message for every failure.
- Log errors to console in development.

### Comments
- Every public class gets a one-line doc comment explaining what it does.
- Every public method gets a one-line doc comment.
- No comments explaining what the code does — write self-documenting code instead.
- Comments explain WHY, not WHAT.

### Example: correct widget
```dart
/// Displays the Hindi voice instruction for the current inspection step.
/// Auto-plays audio when the step changes.
class VoiceInstructionBar extends ConsumerWidget {
  const VoiceInstructionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = ref.watch(inspectionProvider.select((s) => s.currentStep));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.primary.withOpacity(0.08),
      child: Row(
        children: [
          const Icon(Icons.volume_up, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(step.instructionHindi, style: AppTextStyles.hindiBody),
          ),
        ],
      ),
    );
  }
}
```

---

## Screen design guide

Each screen must feel instantly understandable to a 10th-pass Hindi speaker.

### Splash screen
- Full screen Cars24 red background
- White Cars24 logo centered
- "DriveCheck" in white Poppins bold below logo
- Hindi tagline in white NotoSansDevanagari below that
- Auto-navigates after 2 seconds

### Login screen
- White background
- Cars24 logo top center — smaller
- "Mobile number daalo" in large Hindi text
- Single numeric input field — opens number keyboard automatically
- Big red "OTP bhejo" button — full width
- No other options, no links, no distractions

### OTP screen
- "OTP aaya?" heading in Hindi
- 6 individual OTP digit boxes
- Auto-submits when 6th digit entered
- "OTP dobara bhejo" link below after 30 seconds
- Loading state shows spinner inside button

### Home screen
- "Namaste [Name]" greeting top left
- Today's date in Hindi below greeting
- List of inspection jobs as cards
- Each card: car make + model + year, customer area, distance
- One red "Inspection shuru karo" button per card
- Empty state: simple illustration + "Aaj koi inspection nahi"

### Inspection screen — every step follows this exact layout
```
┌─────────────────────────────┐
│ [Back] Step 4 / 12  ████░░ │  ← progress bar
├─────────────────────────────┤
│ [voice instruction strip]   │  ← auto-plays on step load
│ "Aage se poori photo lo"    │
├─────────────────────────────┤
│                             │
│   [reference image]         │  ← shows correct angle
│   example photo here        │
│                             │
├─────────────────────────────┤
│   [AI feedback card]        │  ← slides up after capture
│   shown only after capture  │
├─────────────────────────────┤
│                             │
│      [ 📷 PHOTO LO ]        │  ← big red button
│                             │
└─────────────────────────────┘
```

### Test drive screen
- Full black screen — minimal distraction while driving
- Large white Hindi question text centered
- Pulsing red mic circle — always recording
- Small progress dots at bottom — questions answered
- No buttons — entirely voice controlled

### Report screen
- Animated score ring: 0–100, fills in Cars24 red
- Score number in large bold text inside ring
- Condition label in Hindi below: "Acchi condition"
- Price range card: "₹4,20,000 – ₹4,50,000" in large bold
- Expandable defects list grouped by section
- Big red "Report bhejo" button at bottom
- ElevenLabs auto-plays Hindi price explanation when screen loads

---

## pubspec.yaml

```yaml
name: drive_check
description: DriveCheck — Cars24 AI Inspection Copilot

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # Networking + config
  dio: ^5.4.0
  flutter_dotenv: ^5.1.0

  # State management
  flutter_riverpod: ^2.5.0

  # Navigation
  go_router: ^13.2.0

  # HTTP
  dio: ^5.4.0

  # Camera and media
  image_picker: ^1.1.0
  flutter_image_compress: ^2.2.0
  record: ^5.1.0
  just_audio: ^0.9.36

  # Fonts
  google_fonts: ^6.1.0

  # Storage
  shared_preferences: ^2.2.3
  flutter_secure_storage: ^9.0.0

  # UI
  flutter_svg: ^2.0.10
  permission_handler: ^11.3.0

  # Utils
  uuid: ^4.4.0
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  riverpod_generator: ^2.3.9
  build_runner: ^2.4.9
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/references/
    - assets/audio/
```

---

## Assets needed before building

### Place in assets/images/
```
cars24_logo.png          — Cars24 logo white version for red backgrounds
cars24_logo_dark.png     — Cars24 logo dark version for white backgrounds
app_icon.png             — App icon (1024x1024)
```

### Place in assets/references/
One clean reference photo per inspection step showing correct capture angle:
```
rc_document.jpg
instrument_cluster.jpg
engine_bay.jpg
front_full.jpg
lhs_full.jpg
rhs_full.jpg
rear_full.jpg
roof.jpg
interior.jpg
tyre.jpg
engine_sound.jpg         — illustration of phone near engine
test_drive.jpg           — illustration of person driving
```

Source: Browse cars24.com listing pages for real car photos.

---

## Build and run

```bash
# Install all packages
flutter pub get

# Generate Riverpod providers
dart run build_runner build --delete-conflicting-outputs

# Run on connected Android device
flutter run --dart-define=API_BASE_URL=https://your-api.amazonaws.com/prod

# Build release APK for demo
flutter build apk --release \
  --dart-define=API_BASE_URL=https://your-api.amazonaws.com/prod

# APK location
build/app/outputs/flutter-apk/app-release.apk
```

---

## Permissions required (AndroidManifest.xml)

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
```

Request camera and mic permissions at app start using `permission_handler`.
Show Hindi explanation before requesting: "Gaadi ki photo ke liye camera chahiye."

---

## Demo flow (5 minutes)

```
1. Open app on Android phone
2. Login with phone OTP — backend returns a dev `mockOtp` for the demo
3. Home screen — select today's car "Maruti Swift 2019, Dwarka"
4. Step 1: RC book — photograph RC → AI extracts reg number + owner name
5. Step 4: Front view — upload blurry photo → app says "Thoda door jao, phir se lo"
6. Re-capture good photo → "Scratches detected on bumper — noted"
7. Step 2: Instrument cluster → KM 47,832 auto-filled, service light flagged
8. Step 11: Test drive → phone in pocket, AI asks 7 questions in Hindi, jockey answers
9. Report screen → 72/100 score, ₹4,20,000 – ₹4,50,000 range
10. ElevenLabs explains price in Hindi, jockey taps "Report bhejo"
```

---

*DriveCheck · Built at Token '26 · Cars24 AI Hackathon · May 2026*
