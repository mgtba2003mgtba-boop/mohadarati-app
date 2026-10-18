import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'services/supabase_service.dart';
import 'services/auto_update_service.dart';
import 'services/app_notification_service.dart';
import 'widgets/in_app_notification_overlay.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة الاتصال السحابي بـ Supabase
  await SupabaseService.initialize();

  // تفعيل خدمة التحديث التلقائي الإجباري للآيفون والمتصفح
  AutoUpdateService().initialize();

  // تفعيل خدمة الإشعارات والتنبيهات المباشرة للآيفون والأندرويد
  AppNotificationService.instance.initialize();

  runApp(const NustStudentPortalApp());
}

/// سلوك التمرير فائق السلاسة بنمط iOS التفاعلي على كافة الشاشات والمنصات
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

class NustStudentPortalApp extends StatelessWidget {
  const NustStudentPortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'محاضراتي',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      scrollBehavior: const AppScrollBehavior(),

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

      builder: (context, child) {
        return InAppNotificationOverlay(
          child: child ?? const SizedBox.shrink(),
        );
      },

      home: const SplashScreen(),
    );
  }
}
