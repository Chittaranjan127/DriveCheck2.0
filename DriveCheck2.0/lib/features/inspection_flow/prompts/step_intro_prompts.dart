import '../../../core/i18n/translations.dart';
import '../../../core/services/language_service.dart';

/// One on-screen + one TTS-SSML version of a step's intro prompt. The
/// intro fires automatically when the user lands on a step — it's the
/// assistant's "welcome to this step, here's what to do" line.
///
/// Both fields use the user's language in NATIVE SCRIPT (Devanagari for
/// Hindi, Telugu/Bengali for those, English for English). The display
/// text matches what's spoken so the bubble is a faithful transcript.
class StepIntro {
  final String display;
  final String spokenSsml;
  const StepIntro({required this.display, required this.spokenSsml});
}

/// Look up the intro for a given step. [t] is the active language's
/// translations — used to interpolate real button labels (e.g. "Yes,
/// I'm here" / "हाँ, मैं पहुँच गया") so the AI references the exact
/// text the jockey can see on screen.
StepIntro stepIntroFor(
  String stepId,
  AppLanguage lang, {
  required Translations t,
  String? name,
}) {
  final n = (name?.trim().isNotEmpty ?? false) ? name!.trim() : null;
  switch (stepId) {
    case 'arrival':            return _arrival(lang, t: t, name: n);
    case 'rc_document':        return _rcDocument(lang, t: t);
    case 'instrument_cluster': return _instrumentCluster(lang, t: t);
    case 'engine_bay':         return _engineBay(lang, t: t);
    case 'front_full':         return _exterior(lang, side: 'front', t: t);
    case 'lhs_full':           return _exterior(lang, side: 'left', t: t);
    case 'rhs_full':           return _exterior(lang, side: 'right', t: t);
    case 'rear_full':          return _exterior(lang, side: 'rear', t: t);
    case 'roof':               return _roof(lang, t: t);
    case 'interior':           return _interior(lang, t: t);
    case 'tyres':              return _tyres(lang, t: t);
    case 'engine_sound':       return _engineSound(lang, t: t);
    case 'test_drive':         return _testDrive(lang, t: t);
    default:                   return _generic(lang, t: t);
  }
}

// ---- Step 1: Arrival ----

StepIntro _arrival(AppLanguage lang, {required Translations t, String? name}) {
  final greet = name != null ? ', $name' : '';
  switch (lang) {
    case AppLanguage.english:
      final body = 'Have you arrived at the customer\'s location? '
          'If yes, tap the "${t.yesArrived}" button. '
          'If you need help with directions, tap "${t.getDirections}".';
      return StepIntro(
        display: 'Hi$greet, have you arrived at the customer\'s location?',
        spokenSsml:
            '<speak>Hi$greet. <break time="300ms"/> $body</speak>',
      );
    case AppLanguage.hindi:
      // Embed the real Hindi labels (e.g. "हाँ, मैं पहुँच गया") so the
      // user hears the exact button text they see on screen. "दबाएँ" used
      // in both clauses — sticking with one verb keeps the spoken Hindi
      // consistent and easier for the jockey to mentally parse.
      final body = 'क्या आप ग्राहक की location पर पहुँच गए हैं? '
          'अगर हाँ तो "${t.yesArrived}" बटन दबाएँ। '
          'अगर रास्ता चाहिए तो "${t.getDirections}" बटन दबाएँ।';
      return StepIntro(
        display: 'नमस्ते$greet, क्या आप ग्राहक की location पर पहुँच गए हैं?',
        spokenSsml:
            '<speak>नमस्ते$greet। <break time="300ms"/> $body</speak>',
      );
    case AppLanguage.telugu:
      final body = 'మీరు కస్టమర్ లొకేషన్‌కి చేరుకున్నారా? '
          'అయితే "${t.yesArrived}" నొక్కండి. '
          'దారి కావాలంటే "${t.getDirections}" నొక్కండి.';
      return StepIntro(
        display: 'హాయ్$greet, కస్టమర్ లొకేషన్‌కి చేరుకున్నారా?',
        spokenSsml:
            '<speak>హాయ్$greet. <break time="300ms"/> $body</speak>',
      );
    case AppLanguage.bengali:
      final body = 'আপনি কি কাস্টমারের লোকেশনে পৌঁছেছেন? '
          'যদি হ্যাঁ, তাহলে "${t.yesArrived}" বোতাম চাপুন। '
          'দিকনির্দেশনা প্রয়োজন হলে "${t.getDirections}" বোতাম চাপুন।';
      return StepIntro(
        display: 'হাই$greet, আপনি কি কাস্টমারের লোকেশনে পৌঁছেছেন?',
        spokenSsml:
            '<speak>হাই$greet। <break time="300ms"/> $body</speak>',
      );
  }
}

// ---- Step 2: RC document ----

StepIntro _rcDocument(AppLanguage lang, {required Translations t}) {
  switch (lang) {
    case AppLanguage.english:
      return const StepIntro(
        display: 'Now take a clear photo of the RC card.',
        spokenSsml:
            '<speak>Now please take a clear photo of the RC card. <break time="400ms"/> Hold the card inside the frame on your screen and tap the round shutter button when it looks sharp.</speak>',
      );
    case AppLanguage.hindi:
      return const StepIntro(
        display: 'अब RC card की साफ़ photo लीजिए।',
        spokenSsml:
            '<speak>अब RC card की एक साफ़ photo लीजिए। <break time="400ms"/> Card को screen पर दिख रहे frame के अंदर रखें और जब साफ़ दिखे तब गोल shutter बटन दबाएँ।</speak>',
      );
    case AppLanguage.telugu:
      return const StepIntro(
        display: 'ఇప్పుడు RC కార్డ్ స్పష్టమైన ఫోటో తీయండి.',
        spokenSsml:
            '<speak>ఇప్పుడు RC కార్డ్ స్పష్టమైన ఫోటో తీయండి. <break time="400ms"/> కార్డ్‌ను స్క్రీన్‌పై ఉన్న ఫ్రేమ్ లోపల ఉంచి, స్పష్టంగా కనిపించినప్పుడు రౌండ్ షట్టర్ బటన్ నొక్కండి.</speak>',
      );
    case AppLanguage.bengali:
      return const StepIntro(
        display: 'এবার RC কার্ডের পরিষ্কার ছবি তুলুন।',
        spokenSsml:
            '<speak>এবার RC কার্ডের একটি পরিষ্কার ছবি তুলুন। <break time="400ms"/> কার্ডটি স্ক্রিনের ফ্রেমের ভেতরে রাখুন এবং পরিষ্কার দেখা গেলে গোল শাটার বোতাম চাপুন।</speak>',
      );
  }
}

// ---- Step 3: Instrument cluster ----

StepIntro _instrumentCluster(AppLanguage lang, {required Translations t}) {
  switch (lang) {
    case AppLanguage.english:
      return const StepIntro(
        display: 'Point the camera at the dashboard cluster.',
        spokenSsml:
            '<speak>Point the camera at the dashboard cluster. <break time="400ms"/> Make sure the kilometre reading is clearly visible inside the frame, then tap the shutter.</speak>',
      );
    case AppLanguage.hindi:
      return const StepIntro(
        display: 'Camera को dashboard cluster पर ले जाइए।',
        spokenSsml:
            '<speak>Camera को dashboard cluster पर ले जाइए। <break time="400ms"/> Frame के अंदर kilometre reading साफ़ दिखनी चाहिए, फिर shutter दबाएँ।</speak>',
      );
    case AppLanguage.telugu:
      return const StepIntro(
        display: 'డ్యాష్‌బోర్డ్ క్లస్టర్‌పై కెమెరా ఉంచండి.',
        spokenSsml:
            '<speak>డ్యాష్‌బోర్డ్ క్లస్టర్‌పై కెమెరా ఉంచండి. <break time="400ms"/> కిలోమీటర్ రీడింగ్ ఫ్రేమ్ లోపల స్పష్టంగా కనిపించాలి, తరువాత షట్టర్ నొక్కండి.</speak>',
      );
    case AppLanguage.bengali:
      return const StepIntro(
        display: 'ড্যাশবোর্ড ক্লাস্টারে ক্যামেরা ধরুন।',
        spokenSsml:
            '<speak>ড্যাশবোর্ড ক্লাস্টারে ক্যামেরা ধরুন। <break time="400ms"/> ফ্রেমের ভেতরে কিলোমিটার রিডিং পরিষ্কার দেখা যাওয়া উচিত, তারপর শাটার চাপুন।</speak>',
      );
  }
}

// ---- Step 4: Engine bay ----

StepIntro _engineBay(AppLanguage lang, {required Translations t}) {
  switch (lang) {
    case AppLanguage.english:
      return const StepIntro(
        display: 'Open the bonnet and photograph the engine bay.',
        spokenSsml:
            '<speak>Open the bonnet and take a clear photo of the engine bay. <break time="400ms"/> Make sure the whole engine is visible inside the frame.</speak>',
      );
    case AppLanguage.hindi:
      return const StepIntro(
        display: 'Bonnet खोलिए और engine bay की photo लीजिए।',
        spokenSsml:
            '<speak>Bonnet खोलिए और engine bay की एक साफ़ photo लीजिए। <break time="400ms"/> पूरा engine frame के अंदर दिखना चाहिए।</speak>',
      );
    case AppLanguage.telugu:
      return const StepIntro(
        display: 'బానెట్ తెరిచి ఇంజిన్ ఫోటో తీయండి.',
        spokenSsml:
            '<speak>బానెట్ తెరిచి ఇంజిన్ బే యొక్క స్పష్టమైన ఫోటో తీయండి. <break time="400ms"/> మొత్తం ఇంజిన్ ఫ్రేమ్ లోపల కనిపించాలి.</speak>',
      );
    case AppLanguage.bengali:
      return const StepIntro(
        display: 'বনেট খুলে ইঞ্জিনের ছবি তুলুন।',
        spokenSsml:
            '<speak>বনেট খুলুন এবং ইঞ্জিন বের একটি পরিষ্কার ছবি তুলুন। <break time="400ms"/> পুরো ইঞ্জিন ফ্রেমের ভেতরে দেখা যেতে হবে।</speak>',
      );
  }
}

// ---- Steps 5-8: Exterior (front / left / right / rear) ----

StepIntro _exterior(AppLanguage lang, {required String side, required Translations t}) {
  switch (lang) {
    case AppLanguage.english:
      return StepIntro(
        display: 'Take a $side-side photo of the full car.',
        spokenSsml:
            '<speak>Stand a few steps back and take a photo of the $side of the car. <break time="400ms"/> The full car should fit inside the frame.</speak>',
      );
    case AppLanguage.hindi:
      final hindiSide =
          {'front': 'सामने', 'left': 'बाएँ', 'right': 'दाएँ', 'rear': 'पीछे'}[side]!;
      return StepIntro(
        display: 'गाड़ी के $hindiSide तरफ़ की photo लीजिए।',
        spokenSsml:
            '<speak>थोड़ा पीछे हट कर गाड़ी के $hindiSide तरफ़ की photo लीजिए। <break time="400ms"/> पूरी गाड़ी frame के अंदर आनी चाहिए।</speak>',
      );
    case AppLanguage.telugu:
      final teluguSide =
          {'front': 'ముందు', 'left': 'ఎడమ', 'right': 'కుడి', 'rear': 'వెనుక'}[side]!;
      return StepIntro(
        display: 'కారు $teluguSide వైపు ఫోటో తీయండి.',
        spokenSsml:
            '<speak>కొద్దిగా వెనుకకు వెళ్లి కారు $teluguSide వైపు ఫోటో తీయండి. <break time="400ms"/> మొత్తం కారు ఫ్రేమ్ లోపల ఇమడాలి.</speak>',
      );
    case AppLanguage.bengali:
      final bengaliSide =
          {'front': 'সামনের', 'left': 'বাঁ', 'right': 'ডান', 'rear': 'পিছনের'}[side]!;
      return StepIntro(
        display: 'গাড়ির $bengaliSide দিকের ছবি তুলুন।',
        spokenSsml:
            '<speak>একটু পিছিয়ে গিয়ে গাড়ির $bengaliSide দিকের ছবি তুলুন। <break time="400ms"/> পুরো গাড়িটি ফ্রেমের ভেতরে আসা উচিত।</speak>',
      );
  }
}

StepIntro _roof(AppLanguage lang, {required Translations t}) {
  switch (lang) {
    case AppLanguage.english:
      return const StepIntro(
        display: 'Photograph the roof of the car.',
        spokenSsml:
            '<speak>Take a photo of the roof of the car. <break time="400ms"/> If possible, hold the camera high enough to see the whole roof.</speak>',
      );
    case AppLanguage.hindi:
      return const StepIntro(
        display: 'गाड़ी की छत की photo लीजिए।',
        spokenSsml:
            '<speak>गाड़ी की छत की photo लीजिए। <break time="400ms"/> Camera को थोड़ा ऊँचा रखें ताकि पूरी छत दिखे।</speak>',
      );
    case AppLanguage.telugu:
      return const StepIntro(
        display: 'కారు పైకప్పు ఫోటో తీయండి.',
        spokenSsml:
            '<speak>కారు పైకప్పు యొక్క ఫోటో తీయండి. <break time="400ms"/> సాధ్యమైతే, మొత్తం పైకప్పు కనిపించేలా కెమెరాను ఎత్తుగా పట్టుకోండి.</speak>',
      );
    case AppLanguage.bengali:
      return const StepIntro(
        display: 'গাড়ির ছাদের ছবি তুলুন।',
        spokenSsml:
            '<speak>গাড়ির ছাদের ছবি তুলুন। <break time="400ms"/> সম্ভব হলে পুরো ছাদ দেখতে ক্যামেরা উঁচুতে ধরুন।</speak>',
      );
  }
}

StepIntro _interior(AppLanguage lang, {required Translations t}) {
  switch (lang) {
    case AppLanguage.english:
      return const StepIntro(
        display: 'Photograph the inside of the car.',
        spokenSsml:
            '<speak>Open the driver door and take a photo of the inside of the car. <break time="400ms"/> Make sure the seats and dashboard are visible.</speak>',
      );
    case AppLanguage.hindi:
      return const StepIntro(
        display: 'गाड़ी के अंदर की photo लीजिए।',
        spokenSsml:
            '<speak>Driver की door खोलिए और गाड़ी के अंदर की photo लीजिए। <break time="400ms"/> Seats और dashboard दोनों दिखने चाहिए।</speak>',
      );
    case AppLanguage.telugu:
      return const StepIntro(
        display: 'కారు లోపలి ఫోటో తీయండి.',
        spokenSsml:
            '<speak>డ్రైవర్ డోర్ తెరిచి కారు లోపలి ఫోటో తీయండి. <break time="400ms"/> సీట్లు మరియు డ్యాష్‌బోర్డ్ కనిపించాలి.</speak>',
      );
    case AppLanguage.bengali:
      return const StepIntro(
        display: 'গাড়ির ভেতরের ছবি তুলুন।',
        spokenSsml:
            '<speak>ড্রাইভার ডোর খুলুন এবং গাড়ির ভেতরের ছবি তুলুন। <break time="400ms"/> সিট এবং ড্যাশবোর্ড দেখা যাওয়া উচিত।</speak>',
      );
  }
}

StepIntro _tyres(AppLanguage lang, {required Translations t}) {
  switch (lang) {
    case AppLanguage.english:
      return const StepIntro(
        display: 'Photograph each tyre — tread side.',
        spokenSsml:
            '<speak>Photograph each tyre showing the tread. <break time="400ms"/> Crouch down so the rubber pattern is clearly visible.</speak>',
      );
    case AppLanguage.hindi:
      return const StepIntro(
        display: 'हर tyre की tread side photo लीजिए।',
        spokenSsml:
            '<speak>हर tyre की photo लीजिए, जहाँ rubber का pattern दिखता है। <break time="400ms"/> थोड़ा झुक कर camera को tyre के पास लाएँ।</speak>',
      );
    case AppLanguage.telugu:
      return const StepIntro(
        display: 'ప్రతి టైర్ ట్రెడ్ ఫోటో తీయండి.',
        spokenSsml:
            '<speak>ప్రతి టైర్ యొక్క ట్రెడ్ కనిపించేలా ఫోటో తీయండి. <break time="400ms"/> కొద్దిగా వంగి రబ్బరు నమూనా స్పష్టంగా చూపించండి.</speak>',
      );
    case AppLanguage.bengali:
      return const StepIntro(
        display: 'প্রতিটি টায়ারের ট্রেড ছবি তুলুন।',
        spokenSsml:
            '<speak>প্রতিটি টায়ারের ট্রেড অংশের ছবি তুলুন। <break time="400ms"/> একটু ঝুঁকে রাবারের প্যাটার্ন স্পষ্ট দেখান।</speak>',
      );
  }
}

StepIntro _engineSound(AppLanguage lang, {required Translations t}) {
  switch (lang) {
    case AppLanguage.english:
      return const StepIntro(
        display: 'Start the engine and record the sound.',
        spokenSsml:
            '<speak>Start the engine and let it idle for a few seconds. <break time="400ms"/> Tap the record button so I can listen to the engine sound.</speak>',
      );
    case AppLanguage.hindi:
      return const StepIntro(
        display: 'Engine चालू करके आवाज़ रिकॉर्ड कीजिए।',
        spokenSsml:
            '<speak>Engine चालू कीजिए और कुछ seconds तक idle चलने दीजिए। <break time="400ms"/> फिर रिकॉर्ड बटन दबाएँ ताकि मैं engine की आवाज़ सुन सकूँ।</speak>',
      );
    case AppLanguage.telugu:
      return const StepIntro(
        display: 'ఇంజిన్ స్టార్ట్ చేసి శబ్దం రికార్డ్ చేయండి.',
        spokenSsml:
            '<speak>ఇంజిన్ స్టార్ట్ చేసి కొన్ని సెకన్లు ఐడిల్‌లో ఉండనివ్వండి. <break time="400ms"/> రికార్డ్ బటన్ నొక్కండి, నేను ఇంజిన్ శబ్దం వినగలను.</speak>',
      );
    case AppLanguage.bengali:
      return const StepIntro(
        display: 'ইঞ্জিন চালু করে শব্দ রেকর্ড করুন।',
        spokenSsml:
            '<speak>ইঞ্জিন চালু করুন এবং কয়েক সেকেন্ড আইডল চলতে দিন। <break time="400ms"/> রেকর্ড বোতাম চাপুন যাতে আমি ইঞ্জিনের শব্দ শুনতে পারি।</speak>',
      );
  }
}

StepIntro _testDrive(AppLanguage lang, {required Translations t}) {
  switch (lang) {
    case AppLanguage.english:
      return const StepIntro(
        display: 'Take a short test drive.',
        spokenSsml:
            '<speak>Take a short test drive of about two kilometres. <break time="400ms"/> When done, tap "Finish drive" so we can wrap up the inspection.</speak>',
      );
    case AppLanguage.hindi:
      // "Finish drive" was a hardcoded English label not matched to any
      // real Hindi button. Replaced with screen-agnostic phrasing so the
      // user isn't told to look for a button they can't find.
      return const StepIntro(
        display: 'थोड़ा सा test drive लीजिए।',
        spokenSsml:
            '<speak>लगभग दो kilometre का छोटा test drive लीजिए। <break time="400ms"/> Drive ख़त्म होने पर नीचे दिया हुआ बटन दबाएँ ताकि हम inspection पूरा कर सकें।</speak>',
      );
    case AppLanguage.telugu:
      return const StepIntro(
        display: 'చిన్న టెస్ట్ డ్రైవ్ తీసుకోండి.',
        spokenSsml:
            '<speak>సుమారు రెండు కిలోమీటర్ల చిన్న టెస్ట్ డ్రైవ్ తీసుకోండి. <break time="400ms"/> పూర్తయిన తర్వాత "Finish drive" నొక్కండి, మనం పరిశీలన ముగించగలము.</speak>',
      );
    case AppLanguage.bengali:
      return const StepIntro(
        display: 'একটি ছোট টেস্ট ড্রাইভ নিন।',
        spokenSsml:
            '<speak>প্রায় দুই কিলোমিটারের একটি ছোট টেস্ট ড্রাইভ নিন। <break time="400ms"/> শেষ হলে "Finish drive" চাপুন যাতে আমরা পরিদর্শন শেষ করতে পারি।</speak>',
      );
  }
}

StepIntro _generic(AppLanguage lang, {required Translations t}) {
  final next = t.next; // localised label on the bottom CTA
  switch (lang) {
    case AppLanguage.english:
      return StepIntro(
        display: 'Please complete this step.',
        spokenSsml:
            '<speak>Please follow the instruction on the screen and tap "$next" when done.</speak>',
      );
    case AppLanguage.hindi:
      return StepIntro(
        display: 'इस step को पूरा कीजिए।',
        spokenSsml:
            '<speak>Screen पर लिखे निर्देश का पालन कीजिए और हो जाए तो "$next" बटन दबाएँ।</speak>',
      );
    case AppLanguage.telugu:
      return StepIntro(
        display: 'ఈ దశను పూర్తి చేయండి.',
        spokenSsml:
            '<speak>స్క్రీన్‌పై ఉన్న సూచనను అనుసరించండి, పూర్తయిన తర్వాత "$next" నొక్కండి.</speak>',
      );
    case AppLanguage.bengali:
      return StepIntro(
        display: 'এই ধাপটি সম্পূর্ণ করুন।',
        spokenSsml:
            '<speak>স্ক্রিনের নির্দেশনা অনুসরণ করুন এবং শেষ হলে "$next" চাপুন।</speak>',
      );
  }
}
