
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeController extends ChangeNotifier {
  AppThemeController._(this._preferences);

  static const String _themeKey = 'sokopoa_theme_mode';

  final SharedPreferences _preferences;

  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  bool get isDark => _themeMode == ThemeMode.dark;

  static Future<AppThemeController> create() async {
    final preferences = await SharedPreferences.getInstance();
    final controller = AppThemeController._(preferences);

    final savedTheme = preferences.getString(_themeKey);

    if (savedTheme == 'dark') {
      controller._themeMode = ThemeMode.dark;
    } else {
      controller._themeMode = ThemeMode.light;
    }

    return controller;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;

    await _preferences.setString(
      _themeKey,
      mode == ThemeMode.dark ? 'dark' : 'light',
    );

    notifyListeners();
  }
}
