import '../../../core/services/language_service.dart';

/// One question in the test-drive conversational flow. Each holds the
/// SSML spoken to the driver, a short label for the final summary
/// card, and the set of categorical values the parser will choose
/// from. The category strings are the canonical machine ids — they
/// stay in English in every language so we have one consistent key
/// for downstream code; the human-facing labels are localised in
/// [TestDriveAnswer.localizedValueLabel] via [valueLabels].
class TestDriveQuestion {
  final String id;
  final List<String> categories;        // canonical machine ids
  final Duration listenDuration;        // how long we record after TTS

  /// Per-language spoken prompt (SSML). The TTS-friendly version of
  /// what the AI says — includes a leading "Question N of 7" beat and
  /// trails off with the expected categories so the driver knows
  /// what shape of answer is wanted.
  final Map<AppLanguage, String> spokenSsml;

  /// Per-language plain display text — shown on screen so a passenger
  /// can read along. Matches what's spoken but without SSML.
  final Map<AppLanguage, String> display;

  /// Per-language short label rendered on the final summary chip.
  final Map<AppLanguage, String> shortLabel;

  /// Per-language label for each category, used on the summary chips.
  /// Map keys are the canonical machine ids from [categories]; missing
  /// keys fall back to the canonical id with a leading capital.
  final Map<AppLanguage, Map<String, String>> valueLabels;

  const TestDriveQuestion({
    required this.id,
    required this.categories,
    required this.listenDuration,
    required this.spokenSsml,
    required this.display,
    required this.shortLabel,
    required this.valueLabels,
  });
}

/// Free-form overall feedback question. Last in the sequence. Has a
/// longer listen window (~30s) and no categorical choices — answer is
/// stored as raw transcription plus a model-generated verdict bucket.
class TestDriveOverallPrompt {
  final Map<AppLanguage, String> spokenSsml;
  final Map<AppLanguage, String> display;
  final Map<AppLanguage, String> shortLabel;
  final Duration listenDuration;

  const TestDriveOverallPrompt({
    required this.spokenSsml,
    required this.display,
    required this.shortLabel,
    required this.listenDuration,
  });
}

/// Six quick categorical checks + one open-ended overall. Each
/// SSML prompt opens with "Question N of 7" so a driver who tuned out
/// can re-orient by the count alone. Categories are tight — three
/// buckets per question max — so a Whisper transcription can map
/// cleanly without the parser getting creative.
const _kListen = Duration(seconds: 10);

const List<TestDriveQuestion> kTestDriveQuestions = [
  TestDriveQuestion(
    id: 'acceleration',
    categories: ['smooth', 'jerky', 'sluggish'],
    listenDuration: _kListen,
    spokenSsml: {
      AppLanguage.english:
          '<speak>Question 1 of 7. <break time="300ms"/> How is the car\'s acceleration — smooth, jerky, or sluggish? <break time="500ms"/> You can answer now.</speak>',
      AppLanguage.hindi:
          '<speak>सवाल 7 का 1। <break time="300ms"/> गाड़ी का pickup कैसा है — smooth, jerky, या sluggish? <break time="500ms"/> अब जवाब दीजिए।</speak>',
      AppLanguage.telugu:
          '<speak>ప్రశ్న 1 యొక్క 7. <break time="300ms"/> కారు యాక్సిలరేషన్ ఎలా ఉంది — smooth, jerky, లేదా sluggish? <break time="500ms"/> ఇప్పుడు సమాధానం చెప్పండి.</speak>',
      AppLanguage.bengali:
          '<speak>প্রশ্ন ১ এর ৭। <break time="300ms"/> গাড়ির পিকআপ কেমন — smooth, jerky, নাকি sluggish? <break time="500ms"/> এখন উত্তর দিন।</speak>',
    },
    display: {
      AppLanguage.english: 'Question 1 of 7 — How is the acceleration? Smooth, jerky, or sluggish?',
      AppLanguage.hindi:   'सवाल 7 का 1 — गाड़ी का pickup कैसा है? Smooth, jerky, या sluggish?',
      AppLanguage.telugu:  'ప్రశ్న 1 యొక్క 7 — యాక్సిలరేషన్ ఎలా ఉంది? Smooth, jerky, లేదా sluggish?',
      AppLanguage.bengali: 'প্রশ্ন ১ এর ৭ — পিকআপ কেমন? Smooth, jerky, নাকি sluggish?',
    },
    shortLabel: {
      AppLanguage.english: 'Acceleration',
      AppLanguage.hindi:   'Pickup',
      AppLanguage.telugu:  'యాక్సిలరేషన్',
      AppLanguage.bengali: 'পিকআপ',
    },
    valueLabels: {
      AppLanguage.english: {'smooth': 'Smooth', 'jerky': 'Jerky', 'sluggish': 'Sluggish'},
      AppLanguage.hindi:   {'smooth': 'अच्छा', 'jerky': 'झटकेदार', 'sluggish': 'धीमा'},
      AppLanguage.telugu:  {'smooth': 'మృదువు', 'jerky': 'కుదుపు', 'sluggish': 'మందగతి'},
      AppLanguage.bengali: {'smooth': 'মসৃণ', 'jerky': 'ঝাঁকুনি', 'sluggish': 'ধীর'},
    },
  ),

  TestDriveQuestion(
    id: 'brakes',
    categories: ['firm', 'soft', 'pulling'],
    listenDuration: _kListen,
    spokenSsml: {
      AppLanguage.english:
          '<speak>Question 2 of 7. <break time="300ms"/> How do the brakes feel — firm, soft, or pulling to one side? <break time="500ms"/> Try a normal brake now and tell me.</speak>',
      AppLanguage.hindi:
          '<speak>सवाल 7 का 2। <break time="300ms"/> ब्रेक कैसा लगता है — firm, soft, या एक side खिंच रहा है? <break time="500ms"/> एक normal brake लगा कर बताइए।</speak>',
      AppLanguage.telugu:
          '<speak>ప్రశ్న 2 యొక్క 7. <break time="300ms"/> బ్రేకులు ఎలా ఉన్నాయి — firm, soft, లేదా ఒక వైపుకు లాగుతున్నాయా? <break time="500ms"/> ఇప్పుడు ఒక బ్రేక్ వేసి చెప్పండి.</speak>',
      AppLanguage.bengali:
          '<speak>প্রশ্ন ২ এর ৭। <break time="300ms"/> ব্রেক কেমন — firm, soft, নাকি একদিকে টানছে? <break time="500ms"/> একটা normal brake দিয়ে বলুন।</speak>',
    },
    display: {
      AppLanguage.english: 'Question 2 of 7 — How do the brakes feel? Firm, soft, or pulling?',
      AppLanguage.hindi:   'सवाल 7 का 2 — Brake कैसा है? Firm, soft, या pulling?',
      AppLanguage.telugu:  'ప్రశ్న 2 యొక్క 7 — బ్రేకులు ఎలా ఉన్నాయి? Firm, soft, లేదా pulling?',
      AppLanguage.bengali: 'প্রশ্ন ২ এর ৭ — ব্রেক কেমন? Firm, soft, নাকি pulling?',
    },
    shortLabel: {
      AppLanguage.english: 'Brakes',
      AppLanguage.hindi:   'Brake',
      AppLanguage.telugu:  'బ్రేకులు',
      AppLanguage.bengali: 'ব্রেক',
    },
    valueLabels: {
      AppLanguage.english: {'firm': 'Firm', 'soft': 'Soft', 'pulling': 'Pulling'},
      AppLanguage.hindi:   {'firm': 'सख्त', 'soft': 'नरम', 'pulling': 'खिंच रहा'},
      AppLanguage.telugu:  {'firm': 'గట్టి', 'soft': 'మెత్తని', 'pulling': 'లాగుతోంది'},
      AppLanguage.bengali: {'firm': 'শক্ত', 'soft': 'নরম', 'pulling': 'টানছে'},
    },
  ),

  TestDriveQuestion(
    id: 'steering',
    categories: ['straight', 'pulling', 'vibrating'],
    listenDuration: _kListen,
    spokenSsml: {
      AppLanguage.english:
          '<speak>Question 3 of 7. <break time="300ms"/> How is the steering — going straight, pulling to one side, or vibrating? <break time="500ms"/> Loosen your grip for a moment on a straight road and answer.</speak>',
      AppLanguage.hindi:
          '<speak>सवाल 7 का 3। <break time="300ms"/> Steering कैसी है — straight जा रही है, एक side खिंच रही है, या vibrate हो रही है? <break time="500ms"/> Straight road पर थोड़ा हाथ ढीला कर के बताइए।</speak>',
      AppLanguage.telugu:
          '<speak>ప్రశ్న 3 యొక్క 7. <break time="300ms"/> స్టీరింగ్ ఎలా ఉంది — straight వెళుతోందా, ఒక వైపు లాగుతోందా, లేదా vibrate అవుతోందా? <break time="500ms"/> సరళమైన రోడ్డుపై చేయి కొంచెం వదిలి చెప్పండి.</speak>',
      AppLanguage.bengali:
          '<speak>প্রশ্ন ৩ এর ৭। <break time="300ms"/> স্টিয়ারিং কেমন — straight যাচ্ছে, একদিকে টানছে, নাকি vibrate করছে? <break time="500ms"/> Straight road-এ হাত একটু ঢিলে করে বলুন।</speak>',
    },
    display: {
      AppLanguage.english: 'Question 3 of 7 — How is the steering? Straight, pulling, or vibrating?',
      AppLanguage.hindi:   'सवाल 7 का 3 — Steering कैसी है? Straight, pulling, या vibrating?',
      AppLanguage.telugu:  'ప్రశ్న 3 యొక్క 7 — స్టీరింగ్ ఎలా ఉంది? Straight, pulling, లేదా vibrating?',
      AppLanguage.bengali: 'প্রশ্ন ৩ এর ৭ — স্টিয়ারিং কেমন? Straight, pulling, নাকি vibrating?',
    },
    shortLabel: {
      AppLanguage.english: 'Steering',
      AppLanguage.hindi:   'Steering',
      AppLanguage.telugu:  'స్టీరింగ్',
      AppLanguage.bengali: 'স্টিয়ারিং',
    },
    valueLabels: {
      AppLanguage.english: {'straight': 'Straight', 'pulling': 'Pulling', 'vibrating': 'Vibrating'},
      AppLanguage.hindi:   {'straight': 'सीधी', 'pulling': 'खिंच रही', 'vibrating': 'थरथरा रही'},
      AppLanguage.telugu:  {'straight': 'సూటిగా', 'pulling': 'లాగుతోంది', 'vibrating': 'వణుకుతోంది'},
      AppLanguage.bengali: {'straight': 'সোজা', 'pulling': 'টানছে', 'vibrating': 'কাঁপছে'},
    },
  ),

  TestDriveQuestion(
    id: 'transmission',
    categories: ['smooth', 'jerky', 'slipping'],
    listenDuration: _kListen,
    spokenSsml: {
      AppLanguage.english:
          '<speak>Question 4 of 7. <break time="300ms"/> How is the gear shifting — smooth, jerky, or slipping? <break time="500ms"/> Change a gear and tell me.</speak>',
      AppLanguage.hindi:
          '<speak>सवाल 7 का 4। <break time="300ms"/> Gear shifting कैसी है — smooth, jerky, या slipping? <break time="500ms"/> एक gear बदल कर बताइए।</speak>',
      AppLanguage.telugu:
          '<speak>ప్రశ్న 4 యొక్క 7. <break time="300ms"/> గేర్ షిఫ్టింగ్ ఎలా ఉంది — smooth, jerky, లేదా slipping? <break time="500ms"/> ఒక గేర్ మార్చి చెప్పండి.</speak>',
      AppLanguage.bengali:
          '<speak>প্রশ্ন ৪ এর ৭। <break time="300ms"/> গিয়ার শিফটিং কেমন — smooth, jerky, নাকি slipping? <break time="500ms"/> একটা গিয়ার পরিবর্তন করে বলুন।</speak>',
    },
    display: {
      AppLanguage.english: 'Question 4 of 7 — How is the gear shifting? Smooth, jerky, or slipping?',
      AppLanguage.hindi:   'सवाल 7 का 4 — Gear shifting कैसी है? Smooth, jerky, या slipping?',
      AppLanguage.telugu:  'ప్రశ్న 4 యొక్క 7 — గేర్ షిఫ్టింగ్? Smooth, jerky, లేదా slipping?',
      AppLanguage.bengali: 'প্রশ্ন ৪ এর ৭ — গিয়ার শিফটিং? Smooth, jerky, নাকি slipping?',
    },
    shortLabel: {
      AppLanguage.english: 'Transmission',
      AppLanguage.hindi:   'Gear',
      AppLanguage.telugu:  'గేర్',
      AppLanguage.bengali: 'গিয়ার',
    },
    valueLabels: {
      AppLanguage.english: {'smooth': 'Smooth', 'jerky': 'Jerky', 'slipping': 'Slipping'},
      AppLanguage.hindi:   {'smooth': 'अच्छा', 'jerky': 'झटकेदार', 'slipping': 'फिसल रहा'},
      AppLanguage.telugu:  {'smooth': 'మృదువు', 'jerky': 'కుదుపు', 'slipping': 'జారుతోంది'},
      AppLanguage.bengali: {'smooth': 'মসৃণ', 'jerky': 'ঝাঁকুনি', 'slipping': 'পিছলাচ্ছে'},
    },
  ),

  TestDriveQuestion(
    id: 'suspension',
    categories: ['smooth', 'bouncy', 'noisy'],
    listenDuration: _kListen,
    spokenSsml: {
      AppLanguage.english:
          '<speak>Question 5 of 7. <break time="300ms"/> How is the suspension over bumps — smooth, bouncy, or making noise? <break time="500ms"/> If there\'s a speed breaker nearby, go over it and answer.</speak>',
      AppLanguage.hindi:
          '<speak>सवाल 7 का 5। <break time="300ms"/> Suspension कैसा है bumps पर — smooth, bouncy, या आवाज़ कर रहा है? <break time="500ms"/> कोई speed breaker पास हो तो उसे पार करके बताइए।</speak>',
      AppLanguage.telugu:
          '<speak>ప్రశ్న 5 యొక్క 7. <break time="300ms"/> సస్పెన్షన్ bumps మీద ఎలా ఉంది — smooth, bouncy, లేదా శబ్దం చేస్తోందా? <break time="500ms"/> దగ్గర స్పీడ్ బ్రేకర్ ఉంటే దాని మీద నుండి వెళ్లి చెప్పండి.</speak>',
      AppLanguage.bengali:
          '<speak>প্রশ্ন ৫ এর ৭। <break time="300ms"/> Suspension bumps-এ কেমন — smooth, bouncy, নাকি আওয়াজ করছে? <break time="500ms"/> কাছে speed breaker থাকলে সেটা পার করে বলুন।</speak>',
    },
    display: {
      AppLanguage.english: 'Question 5 of 7 — How is the suspension? Smooth, bouncy, or noisy?',
      AppLanguage.hindi:   'सवाल 7 का 5 — Suspension कैसा है? Smooth, bouncy, या noisy?',
      AppLanguage.telugu:  'ప్రశ్న 5 యొక్క 7 — సస్పెన్షన్? Smooth, bouncy, లేదా noisy?',
      AppLanguage.bengali: 'প্রশ্ন ৫ এর ৭ — Suspension? Smooth, bouncy, নাকি noisy?',
    },
    shortLabel: {
      AppLanguage.english: 'Suspension',
      AppLanguage.hindi:   'Suspension',
      AppLanguage.telugu:  'సస్పెన్షన్',
      AppLanguage.bengali: 'সাসপেনশন',
    },
    valueLabels: {
      AppLanguage.english: {'smooth': 'Smooth', 'bouncy': 'Bouncy', 'noisy': 'Noisy'},
      AppLanguage.hindi:   {'smooth': 'अच्छा', 'bouncy': 'उछल रहा', 'noisy': 'आवाज़'},
      AppLanguage.telugu:  {'smooth': 'మృదువు', 'bouncy': 'ఎగురుతోంది', 'noisy': 'శబ్దం'},
      AppLanguage.bengali: {'smooth': 'মসৃণ', 'bouncy': 'লাফাচ্ছে', 'noisy': 'আওয়াজ'},
    },
  ),

  TestDriveQuestion(
    id: 'noises',
    categories: ['none', 'present'],
    listenDuration: _kListen,
    spokenSsml: {
      AppLanguage.english:
          '<speak>Question 6 of 7. <break time="300ms"/> Are you hearing any unusual sounds while driving — rattles, squeaks, or knocks? <break time="500ms"/> Yes or no, and tell me what you hear.</speak>',
      AppLanguage.hindi:
          '<speak>सवाल 7 का 6। <break time="300ms"/> चलाते समय कोई unusual आवाज़ आ रही है क्या — rattle, squeak, या knock? <break time="500ms"/> हाँ या ना, और क्या सुन रहे हैं वो बताइए।</speak>',
      AppLanguage.telugu:
          '<speak>ప్రశ్న 6 యొక్క 7. <break time="300ms"/> నడుపుతున్నప్పుడు ఏదైనా unusual శబ్దాలు వినిపిస్తున్నాయా — rattle, squeak, లేదా knock? <break time="500ms"/> అవును లేదా కాదు, మరియు ఏమి వింటున్నారో చెప్పండి.</speak>',
      AppLanguage.bengali:
          '<speak>প্রশ্ন ৬ এর ৭। <break time="300ms"/> চালানোর সময় কোনো unusual আওয়াজ পাচ্ছেন — rattle, squeak, বা knock? <break time="500ms"/> হ্যাঁ বা না, এবং কী শুনছেন বলুন।</speak>',
    },
    display: {
      AppLanguage.english: 'Question 6 of 7 — Any unusual sounds while driving?',
      AppLanguage.hindi:   'सवाल 7 का 6 — चलाते समय कोई unusual आवाज़?',
      AppLanguage.telugu:  'ప్రశ్న 6 యొక్క 7 — నడుపుతున్నప్పుడు unusual శబ్దాలు?',
      AppLanguage.bengali: 'প্রশ্ন ৬ এর ৭ — চালানোর সময় unusual আওয়াজ?',
    },
    shortLabel: {
      AppLanguage.english: 'Sounds',
      AppLanguage.hindi:   'आवाज़',
      AppLanguage.telugu:  'శబ్దాలు',
      AppLanguage.bengali: 'আওয়াজ',
    },
    valueLabels: {
      AppLanguage.english: {'none': 'No issues', 'present': 'Has noise'},
      AppLanguage.hindi:   {'none': 'कोई आवाज़ नहीं', 'present': 'आवाज़ है'},
      AppLanguage.telugu:  {'none': 'శబ్దాలు లేవు', 'present': 'శబ్దం ఉంది'},
      AppLanguage.bengali: {'none': 'কোনো আওয়াজ নেই', 'present': 'আওয়াজ আছে'},
    },
  ),
];

/// Final, open-ended overall-feedback prompt. Gets a longer listen
/// window than the categorical questions because the driver may want
/// to give a few sentences of context.
const TestDriveOverallPrompt kTestDriveOverall = TestDriveOverallPrompt(
  listenDuration: Duration(seconds: 20),
  spokenSsml: {
    AppLanguage.english:
        '<speak>Last question. <break time="300ms"/> Overall, how did the car feel on this drive? <break time="400ms"/> Share anything that stood out — good or bad. <break time="500ms"/> You have twenty seconds.</speak>',
    AppLanguage.hindi:
        '<speak>आखरी सवाल। <break time="300ms"/> Overall गाड़ी कैसी लगी इस drive में? <break time="400ms"/> कोई भी अच्छी या ख़राब बात जो ध्यान में आई वो बताइए। <break time="500ms"/> आपके पास बीस seconds हैं।</speak>',
    AppLanguage.telugu:
        '<speak>చివరి ప్రశ్న. <break time="300ms"/> మొత్తంగా ఈ డ్రైవ్‌లో కారు ఎలా అనిపించింది? <break time="400ms"/> మంచి లేదా చెడు ఏదైనా గుర్తింపదగినది ఉంటే చెప్పండి. <break time="500ms"/> మీకు ఇరవై సెకన్లు ఉన్నాయి.</speak>',
    AppLanguage.bengali:
        '<speak>শেষ প্রশ্ন। <break time="300ms"/> Overall এই drive-এ গাড়িটি কেমন লাগল? <break time="400ms"/> ভালো বা খারাপ যা কিছু লক্ষ্য করেছেন বলুন। <break time="500ms"/> আপনার কাছে কুড়ি সেকেন্ড আছে।</speak>',
  },
  display: {
    AppLanguage.english: 'Last question — Overall, how did the car feel on this drive?',
    AppLanguage.hindi:   'आखरी सवाल — Overall गाड़ी कैसी लगी?',
    AppLanguage.telugu:  'చివరి ప్రశ్న — మొత్తంగా కారు ఎలా అనిపించింది?',
    AppLanguage.bengali: 'শেষ প্রশ্ন — Overall গাড়িটি কেমন লাগল?',
  },
  shortLabel: {
    AppLanguage.english: 'Overall feedback',
    AppLanguage.hindi:   'Overall राय',
    AppLanguage.telugu:  'మొత్తం అభిప్రాయం',
    AppLanguage.bengali: 'সামগ্রিক মতামত',
  },
);
