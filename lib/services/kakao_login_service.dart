import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;

/// 카카오 로그인 서비스 (Flutter)
/// - 카카오톡 앱 있음: loginWithKakaoTalk()
/// - 카카오톡 앱 없음: loginWithKakaoAccount()
/// - 성공 시 Firebase 커스텀 인증으로 signInWithCustomToken 수행 → FirebaseAuth.currentUser 설정
class KakaoLoginService {
  /// Cloud Functions 리전. 배포된 createCustomToken 함수 리전과 일치해야 함.
  /// (functions/src/index.ts 에서 region: "asia-northeast3" 사용)
  static const String _functionsRegion = 'asia-northeast3';

  /// 앱 실행 시 호출: Android 키 해시(Key Hash)를 콘솔에 출력합니다.
  /// 카카오 개발자 콘솔에 등록한 키 해시와 일치해야 로그인이 됩니다.
  static Future<void> printKeyHashForDebug() async {
    if (!Platform.isAndroid) return;
    try {
      final origin = await kakao.KakaoSdk.origin;
      // ignore: avoid_print
      print('[Kakao] Android Key Hash (등록용): $origin');
    } catch (e) {
      // ignore: avoid_print
      print('[Kakao] Key Hash 출력 실패: $e');
    }
  }

  /// 카카오 로그인 수행 후 Firebase 커스텀 인증으로 로그인.
  /// 1) 카카오 로그인 → 2) Cloud Functions createCustomToken 호출 → 3) signInWithCustomToken
  /// 성공 시 [UserCredential] 반환 (FirebaseAuth.currentUser 설정됨).
  static Future<UserCredential?> login() async {
    try {
      try {
        await kakao.UserApi.instance.loginWithKakaoTalk();
      } catch (_) {
        await kakao.UserApi.instance.loginWithKakaoAccount();
      }

      final kakaoUser = await kakao.UserApi.instance.me();
      _printUserInfo(kakaoUser);

      // Firebase 커스텀 토큰 발급 후 로그인
      final functions = FirebaseFunctions.instanceFor(region: _functionsRegion);
      Map<String, dynamic> callableData;
      try {
        final result = await functions.httpsCallable('createCustomToken').call<Map<String, dynamic>>(
          <String, dynamic>{'kakaoUserId': 'kakao_${kakaoUser.id}'},
        );
        callableData = result.data;
      } on FirebaseFunctionsException catch (e) {
        // ignore: avoid_print
        print('[Kakao] createCustomToken Cloud Functions 에러:');
        // ignore: avoid_print
        print('  - code: ${e.code}');
        // ignore: avoid_print
        print('  - message: ${e.message}');
        // ignore: avoid_print
        print('  - details: ${e.details}');
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

  static void _printUserInfo(kakao.User user) {
    // ignore: avoid_print
    print('[Kakao 로그인 성공] 사용자 정보:');
    // ignore: avoid_print
    print('  - id: ${user.id}');
    // ignore: avoid_print
    print('  - nickname: ${user.kakaoAccount?.profile?.nickname}');
    // ignore: avoid_print
    print('  - profileImageUrl: ${user.kakaoAccount?.profile?.profileImageUrl}');
    // ignore: avoid_print
    print('  - thumbnailImageUrl: ${user.kakaoAccount?.profile?.thumbnailImageUrl}');
    // ignore: avoid_print
    print('  - email: ${user.kakaoAccount?.email}');
  }
}
