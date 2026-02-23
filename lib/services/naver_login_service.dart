import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_naver_login/flutter_naver_login.dart';
import 'package:flutter_naver_login/interface/types/naver_login_status.dart';

/// 네이버 로그인 서비스 (Flutter)
/// - FlutterNaverLogin.logIn() → Cloud Functions createCustomToken 호출 → signInWithCustomToken
/// - 성공 시 FirebaseAuth.currentUser 설정
class NaverLoginService {
  static const String _functionsRegion = 'asia-northeast3';

  /// 네이버 로그인 수행 후 Firebase 커스텀 인증으로 로그인.
  /// 1) 네이버 로그인 → 2) Cloud Functions createCustomToken 호출 → 3) signInWithCustomToken
  /// 성공 시 [UserCredential] 반환 (FirebaseAuth.currentUser 설정됨).
  static Future<UserCredential?> login() async {
    try {
      final result = await FlutterNaverLogin.logIn();
      if (result.status != NaverLoginStatus.loggedIn) {
        return null;
      }

      final account = result.account;
      if (account == null || account.id == null || account.id!.isEmpty) {
        return null;
      }

      final naverUserId = account.id!;

      // Firebase 커스텀 토큰 발급 후 로그인
      final functions = FirebaseFunctions.instanceFor(region: _functionsRegion);
      Map<String, dynamic> callableData;
      try {
        final callResult = await functions.httpsCallable('createCustomToken').call<Map<String, dynamic>>(
          <String, dynamic>{'kakaoUserId': 'naver_$naverUserId'},
        );
        callableData = callResult.data;
      } on FirebaseFunctionsException catch (e) {
        // ignore: avoid_print
        print('[Naver] createCustomToken Cloud Functions 에러:');
        // ignore: avoid_print
        print('  - code: ${e.code}');
        // ignore: avoid_print
        print('  - message: ${e.message}');
        rethrow;
      }

      final token = callableData['token'] as String?;
      if (token == null || token.isEmpty) {
        throw Exception('createCustomToken: token not returned');
      }
      final userCredential = await FirebaseAuth.instance.signInWithCustomToken(token);
      return userCredential;
    } catch (e) {
      rethrow;
    }
  }
}
