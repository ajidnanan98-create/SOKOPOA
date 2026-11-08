
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sokopoa/core/app_shell.dart';
import 'package:sokopoa/core/app_theme.dart';
import 'package:sokopoa/core/app_theme_controller.dart';
import 'package:sokopoa/data/local_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LocalDatabase.instance.initialize();

  final themeController = await AppThemeController.create();

  runApp(SokoPoaApp(themeController: themeController));
}

class SokoPoaApp extends StatelessWidget {
  const SokoPoaApp({
    super.key,
    required this.themeController,
  });

  final AppThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, child) {
        return MaterialApp(
          title: 'SOKOPOA',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeController.themeMode,
          home: SokoPoaSplashScreen(
            themeController: themeController,
          ),
        );
      },
    );
  }
}

class SokoPoaSplashScreen extends StatefulWidget {
  const SokoPoaSplashScreen({
    super.key,
    required this.themeController,
  });

  final AppThemeController themeController;

  @override
  State<SokoPoaSplashScreen> createState() => _SokoPoaSplashScreenState();
}

class _SokoPoaSplashScreenState extends State<SokoPoaSplashScreen> {
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    _navigationTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => AppShell(
            themeController: widget.themeController,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/branding/sokopoa_logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.storefront_rounded,
                        size: 104,
                        color: Theme.of(context).colorScheme.primary,
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF16834A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'SMART WHOLESALE MANAGEMENT',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark
                          ? AppTheme.darkText
                          : AppTheme.navy,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
