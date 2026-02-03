import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'screens/login/login_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '오늘 뭐 먹지?',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF22C55E), // green-500
          primary: const Color(0xFF22C55E),
          secondary: const Color(0xFF16A34A), // green-600
          surface: Colors.white,
          background: const Color(0xFFF9FAFB), // gray-50
        ),
        scaffoldBackgroundColor: const Color(0xFFF9FAFB),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shadowColor: Colors.black.withOpacity(0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        textTheme: GoogleFonts.notoSansKrTextTheme(
          Theme.of(context).textTheme,
        ),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

/// Wrapper widget that checks authentication status
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading while checking auth state (only on initial load)
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // If user is logged in, check if onboarding is needed
        if (snapshot.hasData && snapshot.data != null) {
          return _OnboardingChecker(user: snapshot.data!);
        }

        // If user is not logged in, show login screen
        return const LoginScreen();
      },
    );
  }
}

/// Widget that checks if user needs onboarding
/// StatefulWidget으로 변경하여 MainNavigationScreen 상태를 보존
class _OnboardingChecker extends StatefulWidget {
  final User user;

  const _OnboardingChecker({required this.user});

  @override
  State<_OnboardingChecker> createState() => _OnboardingCheckerState();
}

class _OnboardingCheckerState extends State<_OnboardingChecker> {
  bool? _onboardingComplete;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .get();

      if (!mounted) return;

      if (!doc.exists) {
        setState(() {
          _onboardingComplete = false;
          _isLoading = false;
        });
        return;
      }

      final userData = doc.data();
      final displayName = userData?['displayName'] as String?;
      final userType = userData?['userType'] as String?;

      final needsOnboarding = displayName == null ||
          displayName.isEmpty ||
          displayName == '익명' ||
          userType == null ||
          userType.isEmpty;

      setState(() {
        _onboardingComplete = !needsOnboarding;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _onboardingComplete = false;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_onboardingComplete == true) {
      // 온보딩 완료 - MainNavigationScreen 표시
      // const로 유지하여 상태 보존
      return const MainNavigationScreen();
    }

    // 온보딩 필요
    return const OnboardingScreen();
  }
}

