import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// إعدادات التطبيق (اللغة، الوضع، الاسم). بتتحفظ على الجهاز.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState i = AppState._();

  SharedPreferences? _p;
  String lang = 'ar';
  ThemeMode themeMode = ThemeMode.system;
  String userName = '';
  bool onboarded = false;

  /// المزامنة السحابية مقفولة افتراضيًا: التطبيق بيشتغل محليًا بالكامل.
  bool syncEnabled = false;

  bool get isAr => lang == 'ar';

  Future<void> load() async {
    final p = _p = await SharedPreferences.getInstance();
    lang = p.getString('lang') ?? 'ar';
    userName = p.getString('userName') ?? '';
    onboarded = p.getBool('onboarded') ?? false;
    syncEnabled = p.getBool('syncEnabled') ?? false;
    switch (p.getString('theme')) {
      case 'light':
        themeMode = ThemeMode.light;
        break;
      case 'dark':
        themeMode = ThemeMode.dark;
        break;
      default:
        themeMode = ThemeMode.system;
    }
  }

  Future<void> setLang(String v) async {
    lang = v;
    await _p?.setString('lang', v);
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    await _p?.setString('theme', m == ThemeMode.light ? 'light' : m == ThemeMode.dark ? 'dark' : 'system');
    notifyListeners();
  }

  Future<void> setUserName(String v) async {
    userName = v;
    await _p?.setString('userName', v);
    notifyListeners();
  }

  Future<void> completeOnboarding(String name) async {
    userName = name;
    onboarded = true;
    await _p?.setString('userName', name);
    await _p?.setBool('onboarded', true);
    notifyListeners();
  }

  Future<void> signOut() async {
    onboarded = false;
    await _p?.setBool('onboarded', false);
    notifyListeners();
  }

  Future<void> setSync(bool v) async {
    syncEnabled = v;
    await _p?.setBool('syncEnabled', v);
    notifyListeners();
  }
}

/// اختصار للنص ثنائي اللغة: tr('عربي', 'English')
String tr(String ar, String en) => AppState.i.isAr ? ar : en;
