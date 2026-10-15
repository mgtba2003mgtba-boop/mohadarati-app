import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'services/supabase_service.dart';
import 'services/auto_update_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة الاتصال السحابي بـ Supabase
  await SupabaseService.initialize();

  // تفعيل خدمة التحديث التلقائي الإجباري للآيفون والمتصفح
  AutoUpdateService().initialize();

  runApp(const NustStudentPortalApp());
}

class NustStudentPortalApp extends StatelessWidget {
  const NustStudentPortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'محاضراتي',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,

      // الدعم الكامل للغة العربية واتجاه النص (RTL)
      locale: const Locale('ar', 'IQ'),
      supportedLocales: const [
        Locale('ar', 'IQ'),
        Locale('ar', 'SA'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      home: const SplashScreen(),
    );
  }
}
