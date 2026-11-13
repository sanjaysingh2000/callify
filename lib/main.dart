import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vapi/vapi.dart';
import 'core/constants/app_constants.dart';
import 'core/network/network_handler.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/profile/presentation/pages/profile_gate_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.initialize();
  await VapiClient.platformInitialized.future;
  runApp(const QuickCallApp());
}

class QuickCallApp extends StatelessWidget {
  const QuickCallApp({super.key, this.home, this.enableNetworkHandler = true});

  final Widget? home;
  final bool enableNetworkHandler;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light.copyWith(
        textTheme: GoogleFonts.outfitTextTheme(AppTheme.light.textTheme),
      ),
      builder: (context, child) {
        final appContent = child ?? const SizedBox.shrink();
        return enableNetworkHandler
            ? NetworkHandler(child: appContent)
            : appContent;
      },
      home: home ?? const ProfileGatePage(),
    );
  }
}
