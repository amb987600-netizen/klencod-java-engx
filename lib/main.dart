import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/app_state.dart';
import 'core/theme.dart';
import 'data/db.dart';
import 'screens/onboarding.dart';
import 'screens/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.i.load();
  await Db.i.open();
  runApp(const EngXApp());
}

class EngXApp extends StatelessWidget {
  const EngXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.i,
      builder: (context, _) {
        final st = AppState.i;
        return MaterialApp(
          title: 'EngX',
          debugShowCheckedModeBanner: false,
          locale: Locale(st.lang),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: st.themeMode,
          home: st.onboarded ? const Shell() : const OnboardingScreen(),
        );
      },
    );
  }
}
