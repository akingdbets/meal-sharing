import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // [추가] 푸시 알림 패키지
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'firebase_options.dart';
import 'widgets/auth_wrapper.dart';
import 'services/notification_service.dart'; // [추가] 알림 서비스
import 'services/kakao_login_service.dart';
import 'services/ingredient_loader.dart';

// [추가] 백그라운드 메시지 핸들러 (반드시 main 함수 밖, 최상위에 있어야 함)
// 앱이 꺼져있거나 백그라운드 상태일 때 알림을 수신 처리합니다.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("🌙 백그라운드 메시지 수신: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await IngredientLoader().loadIngredients();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 카카오 SDK 초기화 (runApp 호출 전)
  KakaoSdk.init(nativeAppKey: 'b785f709e61469f09acd5316978c0511');
  await KakaoLoginService.printKeyHashForDebug();

  // [추가] 백그라운드 핸들러 등록
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // [추가] 알림 서비스 초기화 (권한 요청 및 채널 설정)
  try {
    await NotificationService().initialize();
  } catch (e) {
    print("알림 서비스 초기화 실패: $e");
  }

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
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          elevation: 4,
        ),
        textTheme: GoogleFonts.notoSansKrTextTheme(Theme.of(context).textTheme),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}
