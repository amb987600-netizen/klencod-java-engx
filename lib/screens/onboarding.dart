import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import '../data/db.dart';

/// شاشة الترحيب: اللغة والوضع والاسم، وبعدها "ابدأ الآن".
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController(text: AppState.i.userName);

  @override
  Widget build(BuildContext context) {
    final st = AppState.i;
    return Scaffold(
      backgroundColor: Brand.petrol,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: st,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 24),
              const Icon(Icons.precision_manufacturing, size: 84, color: Colors.white),
              const SizedBox(height: 12),
              const Text('EngX',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              Text(tr('كل أجهزتك وصيانتك في مكان واحد', 'All your devices and maintenance in one place'),
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: Colors.white70)),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(tr('اللغة', 'Language'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'ar', label: Text('العربية')),
                        ButtonSegment(value: 'en', label: Text('English')),
                      ],
                      selected: {st.lang},
                      onSelectionChanged: (v) => st.setLang(v.first),
                    ),
                    const SizedBox(height: 16),
                    Text(tr('الوضع', 'Mode'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<ThemeMode>(
                      segments: [
                        ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode), label: Text(tr('فاتح', 'Light'))),
                        ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode), label: Text(tr('داكن', 'Dark'))),
                      ],
                      selected: {st.themeMode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light},
                      onSelectionChanged: (v) => st.setTheme(v.first),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _name,
                      decoration: InputDecoration(
                        labelText: tr('اسمك', 'Your name'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(tr('المجال', 'Field'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      ChoiceChip(label: Text(tr('الأجهزة الطبية', 'Medical devices')), selected: true, onSelected: (_) {}),
                      for (final f in [tr('أجهزة منزلية', 'Home appliances'), tr('موبايلات', 'Mobiles'), tr('سيارات', 'Cars')])
                        ChoiceChip(label: Text('$f (${tr('قريبًا', 'soon')})'), selected: false, onSelected: null),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Brand.teal, minimumSize: const Size(64, 56)),
                onPressed: () async {
                  final name = _name.text.trim();
                  if (name.isNotEmpty) {
                    await Db.i.raw.update('members', {'user_name': name},
                        where: 'id = ?', whereArgs: [Db.i.memberId]);
                  }
                  await st.completeOnboarding(name);
                },
                child: Text(tr('ابدأ الآن', 'Start now'), style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 12),
              Text(
                tr('بياناتك بتتحفظ على جهازك بس. مفيش حاجة بتترفع على الإنترنت إلا لو انت فعّلت ده من الإعدادات.',
                    'Your data stays on your device. Nothing is uploaded unless you turn it on in Settings.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
