import 'strings.dart';

/// How one sign is made, shown on the help page. The steps were written from the
/// videos of the Saudi Sign Language dictionary (sshi.sa). signs_guide.md and
/// new_words.md have the longer versions.
class SignGuide {
  const SignGuide({
    required this.video,
    required this.arabicName,
    required this.englishName,
    required this.arabic,
    required this.english,
    this.bothHands = false,
  });

  /// The end of the sign's page address in the dictionary: category, then word id.
  final String video;
  final String arabicName;
  final String englishName;
  final String arabic;
  final String english;
  final bool bothHands;

  Uri get videoPage => Uri.https('sshi.sa', '/category/$video');

  String name(Language language) =>
      language == Language.ar ? arabicName : englishName;

  String steps(Language language) => language == Language.ar ? arabic : english;
}

/// Gesture label -> how to make it, in the order of labels_translation.json. The names
/// are repeated here so the page works before the app has reached app.py; a test keeps
/// them the same as that file.
const signGuides = <String, SignGuide>{
  'hello': SignGuide(
    video: '14/4857',
    arabicName: 'السلام عليكم',
    englishName: 'Hello',
    arabic: 'اليد اليمنى مفرودة والإبهام مثني. تلمس أطراف الأصابع جانب الجبهة مثل التحية العسكرية، ثم تنزل اليد إلى أمام الصدر وتتحول إلى قبضة.',
    english: 'Right hand flat with the thumb folded. The fingertips touch the side of the forehead like a salute, then the hand comes down in front of the chest and closes into a fist.',
  ),
  'thank_you': SignGuide(
    video: '14/5018',
    arabicName: 'شكراً',
    englishName: 'Thank you',
    arabic: 'تبدأ مثل «السلام عليكم»: تلمس أطراف الأصابع الجبهة فوق الحاجب الأيمن. ثم تبتعد اليد للأمام وقليلاً إلى اليمين، وتبقى مفتوحة بمستوى الرأس.',
    english: 'It starts like “Hello”: the fingertips touch the forehead above the right eyebrow. Then the hand moves forward and slightly right, and stays open at head height.',
  ),
  'yes': SignGuide(
    video: '23/972',
    arabicName: 'نعم',
    englishName: 'Yes',
    arabic: 'اليد مفتوحة والأصابع متباعدة بجانب الوجه، وراحتها للأمام. ثم تنزل إلى مستوى الصدر، وتنقلب راحتها للأسفل، وتنثني الأصابع مثل المخلب.',
    english: 'Open hand with spread fingers beside the face, palm forward. It comes down to chest height, the palm turns down, and the fingers bend like a claw.',
  ),
  'no': SignGuide(
    video: '23/938',
    arabicName: 'لا',
    englishName: 'No',
    arabic: 'السبابة والخنصر ممدودان، والوسطى والبنصر مثنيتان والإبهام فوقهما. تبدأ اليد أمام منتصف الصدر والسبابة تشير إلى اليسار، ثم ترتفع إلى جانب الكتف الأيمن والأصابع للأعلى.',
    english: 'Index and little fingers straight, the other two bent with the thumb over them. The hand starts in front of the chest with the index finger pointing left, then rises beside the right shoulder with the fingers up.',
  ),
  'please': SignGuide(
    video: '14/4945',
    arabicName: 'لو سمحت',
    englishName: 'Please',
    arabic: 'اليد مفتوحة تمسك الذقن، ثم تنزل إلى أسفله وتنقبض. بعدها تُرفع السبابة وحدها أمام أعلى الصدر، وظهر اليد للأمام.',
    english: 'An open hand holds the chin, then moves below it and closes. Then the index finger alone goes up in front of the upper chest, with the back of the hand facing forward.',
  ),
  'help': SignGuide(
    video: '38/11081',
    arabicName: 'مساعدة',
    englishName: 'Help',
    bothHands: true,
    arabic: 'اليدان مفرودتان أمام البطن: اليسرى في الأسفل وراحتها للأعلى، واليمنى فوقها وراحتها للأسفل. ثم ترتفعان معاً إلى أسفل الصدر وتثبتان قرابة ثانية.',
    english: 'Both hands flat in front of the stomach: the left below with its palm up, the right above with its palm down. They rise together to the lower chest and hold for about a second.',
  ),
  'water': SignGuide(
    video: '35/9173',
    arabicName: 'ماء',
    englishName: 'Water',
    arabic: 'اليد مفرودة والإبهام مثني. تُرفع إلى جانب الفم والخد الأيمن، وراحتها للوجه وأطراف الأصابع للأعلى، وتبقى نصف ثانية.',
    english: 'Flat hand with the thumb folded. It rises beside the mouth and right cheek, palm toward the face and fingertips up, and stays for half a second.',
  ),
  'sorry': SignGuide(
    video: '38/10625',
    arabicName: 'آسف',
    englishName: 'Sorry',
    arabic: 'اليد مفتوحة والأصابع متباعدة. توضع راحتها على الجهة اليسرى من الصدر، مكان القلب، وتثبت قرابة ثانية بدون حركة.',
    english: 'Open hand with spread fingers. The palm rests on the left side of the chest, over the heart, and stays still for about a second.',
  ),
  'good_morning': SignGuide(
    video: '14/4858',
    arabicName: 'صباح الخير',
    englishName: 'Good morning',
    arabic: 'حركة طويلة، ومشاهدة الفيديو تفيد فيها. تبدأ اليد اليمنى عند الصدر، ثم ترتفع بجانب الرأس والأصابع مفتوحة، ثم تلمس الذقن، وتنتهي مفتوحة وراحتها للأعلى أمام الصدر.',
    english: 'A long sign, so the video helps. The right hand starts at the chest, rises beside the head with open fingers, touches the chin, and ends open with the palm up in front of the chest.',
  ),
  'goodbye': SignGuide(
    video: '14/5059',
    arabicName: 'مع السلامة',
    englishName: 'Goodbye',
    arabic: 'اليد اليمنى مفتوحة ومرفوعة بجانب الرأس، وتلوّح يميناً ويساراً.',
    english: 'Right hand open and raised beside the head, waving side to side.',
  ),
  'how_are_you': SignGuide(
    video: '14/5051',
    arabicName: 'كيف حالك',
    englishName: 'How are you',
    arabic:
        'اليد اليمنى مفتوحة على الصدر، ثم تتحول إلى إبهام مرفوع أمام الصدر.',
    english: 'Right hand open on the chest, then it changes to a thumb up in front of the chest.',
  ),
  'fine': SignGuide(
    video: '38/10672',
    arabicName: 'بخير',
    englishName: 'Fine',
    arabic: 'اليد اليمنى تمر أمام الصدر، ثم تثبت بإبهام مرفوع بجانب الكتف. والفرق عن «كيف حالك» أنها لا تبدأ على الصدر، وتنتهي أعلى.',
    english: 'The right hand passes in front of the chest, then holds a thumb up beside the shoulder. Unlike “How are you”, it doesn’t start on the chest and it ends higher.',
  ),
  'what': SignGuide(
    video: '35/9174',
    arabicName: 'ماذا',
    englishName: 'What',
    arabic: 'السبابة مرفوعة أمام الكتف الأيمن، وتهتز قليلاً يميناً ويساراً.',
    english: 'Index finger up in front of the right shoulder, shaking a little side to side.',
  ),
  'want': SignGuide(
    video: '5/5078',
    arabicName: 'أريد',
    englishName: 'I want',
    arabic: 'السبابة تشير إلى الصدر، ثم تتجه اليد للأمام مفتوحة وراحتها للأعلى، ثم تنقبض وتعود إلى الصدر.',
    english: 'The index finger points at the chest. Then the open hand moves forward with the palm up, closes, and comes back to the chest.',
  ),
  'come': SignGuide(
    video: '14/5041',
    arabicName: 'تعال',
    englishName: 'Come',
    arabic: 'اليد مفتوحة ومرفوعة للأمام، ثم تنثني وتشير نحو الجسم كأنها تنادي أحداً.',
    english: 'Open hand raised forward, then it bends toward the body as if calling someone over.',
  ),
  'stop': SignGuide(
    video: '38/10775',
    arabicName: 'توقف',
    englishName: 'Stop',
    bothHands: true,
    arabic: 'علامة ✌ (السبابة والوسطى) بكل يد أمام الصدر، مع هزة خفيفة.',
    english: 'A ✌ sign (index and middle fingers) with each hand in front of the chest, with a slight shake.',
  ),
  'doctor': SignGuide(
    video: '19/9533',
    arabicName: 'طبيب',
    englishName: 'Doctor',
    bothHands: true,
    arabic: 'بعد رفع اليد قليلاً، توضع أصابع اليد اليمنى على رسغ اليد اليسرى أمام الصدر، كأنها تقيس النبض.',
    english: 'After raising the hand a little, the right fingers rest on the left wrist in front of the chest, as if taking a pulse.',
  ),
  'hospital': SignGuide(
    video: '13/5591',
    arabicName: 'مستشفى',
    englishName: 'Hospital',
    bothHands: true,
    arabic: 'اليد على الذراع الأخرى، ثم تمر أمام الصدر، ثم تنفتح الذراعان للجانبين. يجب أن تظهر الذراعان كاملتين في الصورة.',
    english: 'One hand on the other arm, then it passes in front of the chest, then both arms open to the sides. Both arms need to be fully in the picture.',
  ),
  'sick': SignGuide(
    video: '13/5590',
    arabicName: 'مريض',
    englishName: 'Sick',
    arabic: 'اليد اليمنى على الجبهة والرأس مائل قليلاً، كأنها تتحسس الحرارة.',
    english: 'Right hand on the forehead with the head tilted a little, as if feeling for a fever.',
  ),
  'pain': SignGuide(
    video: '13/5476',
    arabicName: 'ألم',
    englishName: 'Pain',
    arabic: 'اليد اليمنى بأصابع مثنية مثل المخلب أمام الصدر، مع اهتزاز خفيف.',
    english: 'Right hand with the fingers bent like a claw in front of the chest, shaking slightly.',
  ),
  'medicine': SignGuide(
    video: '13/5521',
    arabicName: 'دواء',
    englishName: 'Medicine',
    arabic: 'اليد اليمنى تقترب من الفم وأطراف الأصابع عنده، كأنها تضع حبة دواء. وهي قريبة من إشارة «دورة المياه».',
    english: 'The right hand comes to the mouth with the fingertips there, as if placing a pill. It’s close to the “Bathroom” sign.',
  ),
  'bathroom': SignGuide(
    video: '10/4609',
    arabicName: 'دورة المياه',
    englishName: 'Bathroom',
    arabic: 'شكل اليد خاص، ومشاهدة الفيديو تفيد فيها. اليد اليمنى بجانب الفم والذقن، والإبهام للأعلى والسبابة للجانب، مع حركة خفيفة.',
    english: 'The handshape is unusual, so the video helps. The right hand is beside the mouth and chin, thumb up and index finger to the side, with a slight movement.',
  ),
  'hungry': SignGuide(
    video: '38/10786',
    arabicName: 'جائع',
    englishName: 'Hungry',
    arabic: 'السبابة تشير إلى الفم، ثم تنزل اليد وتمسح على البطن.',
    english: 'The index finger points at the mouth, then the hand comes down and rubs the stomach.',
  ),
  'sleep': SignGuide(
    video: '39/11380',
    arabicName: 'ينام',
    englishName: 'Sleep',
    bothHands: true,
    arabic: 'الكفّان مضمومتان تحت الخد والرأس مائل عليهما، مثل وضعية النوم.',
    english: 'Palms together under the cheek with the head resting on them, like sleeping.',
  ),
  'happy': SignGuide(
    video: '5/5147',
    arabicName: 'سعيد',
    englishName: 'Happy',
    bothHands: true,
    arabic: 'الكفّان مفتوحتان على الصدر، وتمسحان للأعلى بالتناوب.',
    english: 'Open palms on the chest, brushing upward in turns.',
  ),
  'home': SignGuide(
    video: '10/4586',
    arabicName: 'بيت',
    englishName: 'Home',
    bothHands: true,
    arabic: 'مشاهدة الفيديو تفيد في هذه الإشارة. يد مسطحة وقائمة بجانب الوجه، والأخرى بجانبها عند الفم.',
    english: 'The video helps with this sign. One flat hand stands upright beside the face, with the other next to it at the mouth.',
  ),
  'phone': SignGuide(
    video: '10/4676',
    arabicName: 'هاتف',
    englishName: 'Phone',
    arabic: 'السبابة تشير للأسفل أمام الجسم، ثم تكون اليد عند الأذن بشكل سماعة الهاتف.',
    english: 'The index finger points down in front of the body, then the hand goes to the ear in the shape of a phone receiver.',
  ),
  'car': SignGuide(
    video: '18/6515',
    arabicName: 'سيارة',
    englishName: 'Car',
    bothHands: true,
    arabic: 'قبضتان أمام الجسم تتحركان بالتناوب، كأنهما تمسكان مقود السيارة.',
    english: 'Two fists in front of the body moving in turns, as if holding a steering wheel.',
  ),
};
