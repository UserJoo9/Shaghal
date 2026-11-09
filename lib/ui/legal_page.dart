import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'glass.dart';

// ───── املأ القيم دي قبل الرفع على App Store ─────
const kDeveloperName = 'Youssef Alkhodary';
const kContactEmail = 'yalkhodary1@gmail.com';
const kGoverningLaw = 'Egypt';
const kTermsUpdated = '2026-11-09';

class _Sec {
  const _Sec(this.title, this.body, [this.bullets = const []]);
  final String title;
  final String body;
  final List<String> bullets;
}

List<_Sec> _sections(bool ar) => ar
    ? const [
        _Sec(
            '1. الترخيص',
            'يمنحك المطوّر ($kDeveloperName) ترخيصًا شخصيًا وغير حصري وغير قابل للنقل وقابلًا للإلغاء لاستخدام التطبيق على أجهزة Apple التي تملكها أو تتحكم بها، وفق هذه الشروط وشروط خدمات الوسائط من Apple. الكود المصدري منشور برخصة MIT، وهي تحكم الكود المصدري، بينما تحكم هذه الشروط استخدامك للتطبيق الموزَّع.'),
        _Sec('2. ملفاتك وخصوصيتك',
            'يشغّل شغل ملفات الوسائط المخزّنة على جهازك. لا توجد حسابات ولا إعلانات ولا أدوات تحليل، ولا يرفع التطبيق ملفاتك ولا يجمع بيانات شخصية. تبقى مكتبتك ومفضلتك وإعداداتك على جهازك. أنت وحدك المسؤول عن الملفات التي تستوردها وعن امتلاكك الحق في تشغيلها.'),
        _Sec('3. الاستخدام المقبول', 'توافق على عدم:', [
          'استخدام التطبيق لانتهاك حقوق النشر أو أي حقوق أخرى لأي شخص.',
          'نسخ التطبيق أو تعديله أو عكس هندسته أو إعادة توزيعه إلا بما تسمح به رخصة MIT.',
          'استخدام التطبيق بما يخالف أي قانون معمول به.',
        ]),
        _Sec('4. البرمجيات التابعة لجهات خارجية',
            'يتضمن التطبيق مكوّنات مفتوحة المصدر، منها Flutter وmedia_kit وlibmpv. تُقدَّم هذه المكوّنات برخصها الخاصة التي تسري عليها.'),
        _Sec('5. إخلاء الضمانات',
            'يُقدَّم التطبيق "كما هو" و"حسب التوفر" دون أي ضمانات، صريحة أو ضمنية، بما فيها الملاءمة لغرض معين أو عمل التطبيق دون انقطاع أو أخطاء. لا نضمن تشغيل كل صيغة ملف على كل جهاز.'),
        _Sec('6. تحديد المسؤولية',
            'بأقصى حد يسمح به القانون، لا يتحمل المطوّر المسؤولية عن أي أضرار غير مباشرة أو عرضية أو تبعية، ولا عن فقدان البيانات أو الملفات، الناتجة عن استخدامك التطبيق. لا تحدّ هذه الشروط من أي مسؤولية لا يجوز تحديدها قانونًا.'),
        _Sec('7. الإنهاء',
            'يمكنك التوقف عن استخدام التطبيق في أي وقت بحذفه. تنتهي هذه الشروط تلقائيًا إذا خالفتها، وتبقى البنود 5 و6 سارية بعد الإنهاء.'),
        _Sec('8. التعديلات',
            'قد يحدّث المطوّر هذه الشروط. يبيّن تاريخ "آخر تحديث" النسخة الحالية، ويعني استمرارك في الاستخدام بعد التحديث موافقتك عليه.'),
        _Sec('9. القانون الواجب التطبيق',
            'تخضع هذه الشروط لقوانين $kGoverningLaw دون اعتبار لقواعد تنازع القوانين، ولا يُسقط ذلك حقوق المستهلك الإلزامية في بلد إقامتك.'),
        _Sec('10. شروط خاصة بـ Apple', 'تنطبق هذه البنود لأن التطبيق موزَّع عبر App Store:', [
          'هذه الشروط بينك وبين المطوّر فقط وليست مع Apple. المطوّر، لا Apple، هو المسؤول عن التطبيق ومحتواه.',
          'لا تلتزم Apple بتقديم أي صيانة أو دعم للتطبيق.',
          'إذا لم يطابق التطبيق أي ضمان، يمكنك إبلاغ Apple لاسترداد ثمن الشراء (إن وُجد)، ولا تتحمل Apple أي التزام آخر بالضمان.',
          'المطوّر، لا Apple، يتولى أي مطالبات تتعلق بالتطبيق، ومنها المسؤولية عن المنتج والامتثال القانوني وحقوق الملكية الفكرية.',
          'شركة Apple وشركاتها التابعة أطراف ثالثة مستفيدة من هذه الشروط ويحق لها إنفاذها عليك.',
          'تقر بأنك لست في دولة خاضعة لحظر من حكومة الولايات المتحدة ولست مدرجًا ضمن الأطراف المقيَّدة.',
        ]),
        _Sec('11. التواصل', 'للاستفسار عن هذه الشروط: $kContactEmail'),
      ]
    : const [
        _Sec('1. License',
            'The Developer ($kDeveloperName) grants you a personal, non-exclusive, non-transferable, revocable license to use the App on Apple devices you own or control, subject to these Terms and the Apple Media Services Terms. The App\'s source code is released under the MIT License; that license governs the source code, while these Terms govern your use of the distributed App.'),
        _Sec('2. Your files and privacy',
            'Shaghal plays media files stored on your device. It has no accounts, no ads and no analytics, and it does not upload your files or collect personal data. Your library, favorites and settings stay on your device. You remain solely responsible for the files you import and for having the right to play them.'),
        _Sec('3. Acceptable use', 'You agree not to:', [
          'use the App to infringe copyright or other rights of anyone;',
          'copy, modify, reverse engineer or redistribute the App except as the MIT License allows;',
          'use the App in violation of any applicable law.',
        ]),
        _Sec('4. Third-party software',
            'The App includes open-source components, including Flutter, media_kit and libmpv. They are provided under their own licenses, which apply to those components.'),
        _Sec('5. Disclaimer of warranties',
            'The App is provided "as is" and "as available", without warranties of any kind, express or implied, including fitness for a particular purpose and uninterrupted or error-free operation. Playback of every file format on every device is not guaranteed.'),
        _Sec('6. Limitation of liability',
            'To the maximum extent permitted by law, the Developer is not liable for any indirect, incidental or consequential damages, or for loss of data or files, arising from your use of the App. Nothing in these Terms limits liability that cannot be limited by law.'),
        _Sec('7. Termination',
            'You may stop using the App at any time by deleting it. These Terms end automatically if you breach them, and Sections 5 and 6 survive termination.'),
        _Sec('8. Changes',
            'The Developer may update these Terms. The "Last updated" date shows the current version; continued use after an update means you accept it.'),
        _Sec('9. Governing law',
            'These Terms are governed by the laws of $kGoverningLaw, without regard to conflict-of-law rules. This does not remove mandatory consumer rights you have in your country of residence.'),
        _Sec('10. Apple-specific terms', 'These apply because the App is distributed through the App Store:', [
          'These Terms are between you and the Developer only, not Apple. The Developer, not Apple, is responsible for the App and its content.',
          'Apple has no obligation to provide maintenance or support for the App.',
          'If the App fails to conform to any warranty, you may notify Apple for a refund of the purchase price (if any); Apple has no other warranty obligation.',
          'The Developer, not Apple, handles any claims about the App, including product liability, legal compliance and intellectual property claims.',
          'Apple and its subsidiaries are third-party beneficiaries of these Terms and may enforce them against you.',
          'You confirm you are not located in a country under a U.S. government embargo or listed as a restricted party.',
        ]),
        _Sec('11. Contact', 'Questions about these Terms: $kContactEmail'),
      ];

class TermsPage extends ConsumerWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final secs = _sections(s.ar);

    return Rtl(
      child: Scaffold(
        body: GlassBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Row(
                    textDirection: TextDirection.ltr,
                    children: [
                      GlassIconButton(
                        icon: Icons.chevron_left_rounded,
                        size: 46,
                        iconSize: 30,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          s.t('شروط الخدمة', 'Terms of Service'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                        20, 8, 20, 40 + MediaQuery.paddingOf(context).bottom),
                    children: [
                      Text(
                        s.t('آخر تحديث: $kTermsUpdated',
                            'Last updated: $kTermsUpdated'),
                        style: TextStyle(fontSize: 13, color: context.fg54),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        s.t(
                            'تحكم هذه الشروط استخدامك لتطبيق شغل، وهو مشغّل صوت وفيديو يعمل دون إنترنت على iOS. باستخدامك التطبيق فأنت توافق عليها.',
                            'These Terms govern your use of Shaghal, an offline audio and video player for iOS. By using the App you agree to them.'),
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
                      for (final sec in secs) ...[
                        const SizedBox(height: 22),
                        Text(
                          sec.title,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(sec.body,
                            style: const TextStyle(fontSize: 15, height: 1.5)),
                        for (final b in sec.bullets)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('•  ',
                                    style: TextStyle(fontSize: 15)),
                                Expanded(
                                  child: Text(b,
                                      style: const TextStyle(
                                          fontSize: 15, height: 1.5)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
