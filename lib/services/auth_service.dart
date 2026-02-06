import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

/// Singleton service for handling authentication
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _usersCollection = 'users';

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Sign in with Kakao
  Future<UserCredential?> signInWithKakao() async {
    try {
      print('Kakao Login Pressed');
      // TODO: Implement Kakao login
      return null;
    } catch (e) {
      print('Kakao login error: $e');
      return null;
    }
  }

  /// Sign in with Naver
  Future<UserCredential?> signInWithNaver() async {
    try {
      print('Naver Login Pressed');
      // TODO: Implement Naver login
      return null;
    } catch (e) {
      print('Naver login error: $e');
      return null;
    }
  }

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      print('Google Login Pressed');

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        print('Google sign-in was canceled');
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      print('Google login successful: ${userCredential.user?.uid}');

      if (userCredential.user != null) {
        await saveUserToFirestore(userCredential.user!);
      }

      return userCredential;
    } catch (e) {
      print('Google login error: $e');
      rethrow;
    }
  }

  /// 🍎 Sign in with Apple
  Future<UserCredential?> signInWithApple() async {
    try {
      print('Apple Login Pressed');

      // 1. 보안을 위한 Nonce(난수) 생성
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      // 2. 애플 로그인 요청 (iOS 기본 UI 호출)
      final appleIdCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      // 3. 파이어베이스 인증 자격 증명 생성
      final OAuthCredential credential = OAuthProvider("apple.com").credential(
        idToken: appleIdCredential.identityToken,
        accessToken: appleIdCredential.authorizationCode,
        rawNonce: rawNonce,
      );

      // 4. 파이어베이스에 로그인
      final userCredential = await _auth.signInWithCredential(credential);
      print('Apple login successful: ${userCredential.user?.uid}');

      // 5. Firestore에 유저 정보 저장
      if (userCredential.user != null) {
        // 애플은 '최초 로그인 시에만' 이름 정보를 줍니다.
        // 따라서 이름 정보가 있다면 Firebase User 프로필을 업데이트합니다.
        if (appleIdCredential.givenName != null) {
          final fullName =
              "${appleIdCredential.familyName ?? ''}${appleIdCredential.givenName}";
          await userCredential.user!.updateDisplayName(fullName);
        }
        await saveUserToFirestore(userCredential.user!);
      }

      return userCredential;
    } catch (e) {
      print('Apple login error: $e');
      // 사용자가 취소한 경우 (예외 처리)
      if (e is SignInWithAppleAuthorizationException &&
          e.code == AuthorizationErrorCode.canceled) {
        print('User canceled Apple Sign In');
        return null;
      }
      rethrow;
    }
  }

  /// Sign in anonymously (Guest mode)
  Future<UserCredential?> signInAnonymously() async {
    try {
      print('Guest Mode Pressed');
      final userCredential = await _auth.signInAnonymously();
      print('Anonymous login successful: ${userCredential.user?.uid}');

      if (userCredential.user != null) {
        await saveUserToFirestore(userCredential.user!);
      }

      return userCredential;
    } catch (e) {
      print('Anonymous login error: $e');
      return null;
    }
  }

  /// Update display name in Firebase Auth
  Future<void> updateDisplayName(String displayName) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.updateDisplayName(displayName);
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      // 구글 로그아웃
      try {
        await _googleSignIn.signOut();
      } catch (e) {
        // 구글 로그인 상태가 아니면 무시
      }

      // 파이어베이스 로그아웃 (애플, 게스트 등 포함)
      await _auth.signOut();
      print('User signed out');
    } catch (e) {
      print('Sign out error: $e');
      rethrow;
    }
  }

  /// Save or update user data in Firestore
  Future<void> saveUserToFirestore(User user) async {
    try {
      final userDocRef = _firestore.collection(_usersCollection).doc(user.uid);
      final userDoc = await userDocRef.get();

      final now = DateTime.now();

      if (!userDoc.exists) {
        // 신규 유저
        final userModel = UserModel(
          uid: user.uid,
          email: user.email ?? '',
          displayName: user.displayName ?? '', // 애플/구글에서 가져온 이름
          userType: '',
          createdAt: now,
          lastLoginAt: now,
          profileImage: user.photoURL,
        );

        await userDocRef.set(userModel.toMap());
        print('New user saved to Firestore: ${user.uid}');
      } else {
        // 기존 유저
        await userDocRef.update({'lastLoginAt': Timestamp.fromDate(now)});
        print('User lastLoginAt updated: ${user.uid}');
      }
    } catch (e) {
      print('Error saving user to Firestore: $e');
      // 로그인은 성공했으므로 Firestore 저장은 실패해도 넘어가거나 필요시 처리
    }
  }

  /// Delete user account
  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인된 사용자가 없습니다.');
      }

      final userId = user.uid;

      // 0. 재인증 (계정 삭제 전 보안 확인)
      // 구글 계정인 경우
      if (user.providerData.any((p) => p.providerId == 'google.com')) {
        final GoogleSignInAccount? googleUser = await _googleSignIn
            .signInSilently();
        if (googleUser != null) {
          final GoogleSignInAuthentication googleAuth =
              await googleUser.authentication;
          final credential = GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          );
          await user.reauthenticateWithCredential(credential);
        }
      }
      // 애플 계정인 경우 (Apple은 재인증 절차가 복잡하여, 실패 시 '다시 로그인 해주세요' 에러 발생시킴)
      // 별도 재인증 로직 없이 진행 -> 오래된 세션이면 delete()에서 에러 발생

      // 1. Delete user's posts
      try {
        final postsSnapshot = await _firestore
            .collection('posts')
            .where('userId', isEqualTo: userId)
            .get();
        final batch = _firestore.batch();
        for (var doc in postsSnapshot.docs) batch.delete(doc.reference);
        await batch.commit();
      } catch (e) {
        print('Error deleting posts: $e');
      }

      // 2. Delete user's meal logs
      try {
        final logsSnapshot = await _firestore
            .collection('meal_logs')
            .where('userId', isEqualTo: userId)
            .get();
        final batch = _firestore.batch();
        for (var doc in logsSnapshot.docs) batch.delete(doc.reference);
        await batch.commit();
      } catch (e) {
        print('Error deleting meal logs: $e');
      }

      // 3. Delete user's community posts
      try {
        final communitySnapshot = await _firestore
            .collection('community_posts')
            .where('userId', isEqualTo: userId)
            .get();
        final batch = _firestore.batch();
        for (var doc in communitySnapshot.docs) batch.delete(doc.reference);
        await batch.commit();
      } catch (e) {
        print('Error deleting community posts: $e');
      }

      // 4. Delete user document
      try {
        await _firestore.collection(_usersCollection).doc(userId).delete();
      } catch (e) {
        print('Error deleting user document: $e');
      }

      // 5. Delete Firebase Auth account
      await user.delete();

      // 6. Sign out locally
      await _googleSignIn.signOut();
      await _auth.signOut();

      print('Account deleted successfully');
    } catch (e) {
      print('Error deleting account: $e');
      rethrow;
    }
  }

  // ================= 헬퍼 함수 (Apple Login용) =================

  /// 난수 문자열 생성 (Nonce)
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  /// 문자열을 SHA256으로 해시
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
