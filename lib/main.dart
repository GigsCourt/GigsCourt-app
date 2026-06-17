import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/wizard_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/main_shell.dart';
import 'screens/provider_profile_screen.dart';
import 'screens/chat_conversation_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/support_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'theme/app_theme.dart';
import 'screens/verify_email_screen.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await Supabase.initialize(
    url: 'https://ucwffnukedmowwxedqzv.supabase.co',
    publishableKey: 'sb_publishable_mNwlLP9omXRkPNIQzaVKRg_yFUsW6xZ',
  );

  final remoteConfig = FirebaseRemoteConfig.instance;
  await remoteConfig.setConfigSettings(RemoteConfigSettings(
    fetchTimeout: const Duration(seconds: 10),
    minimumFetchInterval: const Duration(hours: 1),
  ));
  await remoteConfig.setDefaults({
    'subscriptions_enforced': false,
  });
  await remoteConfig.fetchAndActivate();

  runApp(const GigsCourtApp());
}

class GigsCourtApp extends StatelessWidget {
  const GigsCourtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GigsCourt',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/wizard': (context) => const WizardScreen(),
        '/signup': (context) => SignUpScreen(),
        '/login': (context) => const LoginScreen(),
        '/verify-email': (context) => const VerifyEmailScreen(),
        '/setup': (context) => SetupScreen(),
        '/home': (context) => const MainShell(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/provider-profile') {
          final providerId = settings.arguments as String;
          return MaterialPageRoute(
            builder: (context) => ProviderProfileScreen(providerId: providerId),
          );
        }
        if (settings.name == '/chat-conversation') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => ChatConversationScreen(
              chatId: args['chatId'],
              otherUserId: args['otherUserId'],
              otherUserName: args['otherUserName'],
            ),
          );
        }
        if (settings.name == '/settings') {
          return MaterialPageRoute(builder: (context) => const SettingsScreen());
        }
        if (settings.name == '/notifications') {
          return MaterialPageRoute(builder: (context) => const NotificationsScreen());
        }
        if (settings.name == '/subscription') {
          return MaterialPageRoute(builder: (context) => const SubscriptionScreen());
        }
        if (settings.name == '/support') {
          return MaterialPageRoute(builder: (context) => const SupportScreen());
        }
        if (settings.name == '/edit-profile') {
          return MaterialPageRoute(builder: (context) => const EditProfileScreen());
        }
        return null;
      },
    );
  }
}