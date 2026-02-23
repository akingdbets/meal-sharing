import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/login/login_screen.dart';
import '../screens/main_navigation_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';

/// 루트 인증/온보딩 분기. 로그인 성공 후 이 위젯으로 이동하면 온보딩 여부를 다시 검사한다.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return OnboardingChecker(user: snapshot.data!);
        }
        return const LoginScreen();
      },
    );
  }
}

/// 로그인된 유저의 온보딩 완료 여부를 Firestore로 확인 후 온보딩/메인 화면 분기
class OnboardingChecker extends StatefulWidget {
  final User user;

  const OnboardingChecker({super.key, required this.user});

  @override
  State<OnboardingChecker> createState() => _OnboardingCheckerState();
}

class _OnboardingCheckerState extends State<OnboardingChecker> {
  bool? _onboardingComplete;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    try {
      final usersRef = FirebaseFirestore.instance.collection('users').doc(widget.user.uid);
      final doc = await usersRef.get();

      if (!mounted) return;

      if (!doc.exists) {
        // 신규 가입자: 빈 값/기본값으로 users 문서 먼저 생성 후 온보딩으로 이동
        await usersRef.set({
          'uid': widget.user.uid,
          'email': widget.user.email ?? '',
          'displayName': '',
          'displayNameLower': '',
          'profileImageUrl': null,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (!mounted) return;
        setState(() {
          _onboardingComplete = false;
          _isLoading = false;
        });
        return;
      }

      final userData = doc.data();
      final displayName = userData?['displayName'] as String?;
      final userType = userData?['userType'] as String?;

      final needsOnboarding =
          displayName == null ||
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_onboardingComplete == true) {
      return const MainNavigationScreen();
    }
    return const OnboardingScreen();
  }
}
