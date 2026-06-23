import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'screens/reviews_screen.dart';
import 'screens/following_screen.dart';
import 'theme/app_theme.dart';
import 'screens/verify_email_screen.dart';
import 'screens/login_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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

  // Initialize FCM (works on iOS/Android only)
  try {
    await _initFCM();
  } catch (_) {
    // FCM not supported on this platform
  }

  runApp(const GigsCourtApp());
}

Future<void> _initFCM() async {
  final messaging = FirebaseMessaging.instance;

  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  final token = await messaging.getToken();
  if (token != null) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'fcmToken': token,
      });
    }

    messaging.onTokenRefresh.listen((newToken) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'fcmToken': newToken,
        });
      }
    });
  }

  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    _handleNotificationTap(message.data);
  });

  final initialMessage = await messaging.getInitialMessage();
  if (initialMessage != null) {
    _handleNotificationTap(initialMessage.data);
  }

  FirebaseMessaging.onMessage.listen((message) {
    // Show local notification or in-app banner
  });
}

void _handleNotificationTap(Map<String, dynamic> data) {
  final type = data['type'];
  final referenceId = data['referenceId'];

  switch (type) {
    case 'chat':
      if (referenceId != null) {
        navigatorKey.currentState?.pushNamed('/chat-conversation', arguments: {
          'chatId': referenceId,
          'otherUserId': data['senderId'] ?? '',
          'otherUserName': data['senderName'] ?? '',
        });
      }
      break;
    case 'subscription':
      navigatorKey.currentState?.pushNamed('/subscription');
      break;
    case 'review':
      if (referenceId != null) {
        navigatorKey.currentState?.pushNamed('/provider-profile', arguments: referenceId);
      }
      break;
    case 'locked':
      navigatorKey.currentState?.pushNamed('/subscription');
      break;
  }
}

class GigsCourtApp extends StatefulWidget {
  const GigsCourtApp({super.key});

  @override
  State<GigsCourtApp> createState() => _GigsCourtAppState();
}

class _GigsCourtAppState extends State<GigsCourtApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (state == AppLifecycleState.resumed) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } else if (state == AppLifecycleState.paused) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
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
        if (settings.name == '/reviews') {
          final providerId = settings.arguments as String;
          return MaterialPageRoute(
            builder: (context) => ReviewsScreen(providerId: providerId),
          );
        }
        if (settings.name == '/following') {
          return MaterialPageRoute(builder: (context) => const FollowingScreen());
        }
        return null;
      },
    );
  }
}