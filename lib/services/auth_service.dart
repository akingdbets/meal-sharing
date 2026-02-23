import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/user_model.dart';
import 'kakao_login_service.dart';
import 'naver_login_service.dart';

/// Singleton service for handling authentication
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _usersCollection = 'users';

  /// 프로필 사진 미설정 시 사용할 기본 아바타 URL (어느 플랫폼이든 동일)
  static const String defaultProfileImageUrl =
      'https://ui-avatars.com/api/?name=User&background=22C55E&color=ffffff&size=256';

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Sign in with Kakao (카카오 로그인 → Firebase 커스텀 토큰 → Firestore 유저 저장)
  Future<UserCredential?> signInWithKakao() async {
    try {
      final userCredential = await KakaoLoginService.login();
      if (userCredential != null && userCredential.user != null) {
        await saveUserToFirestore(userCredential.user!);
        return userCredential;
      }
      return null;
    } catch (e) {
      print('Kakao login error: $e');
      rethrow;
    }
  }

  /// Sign in with Naver (네이버 로그인 → Firebase 커스텀 토큰 → Firestore 유저 저장)
  Future<UserCredential?> signInWithNaver() async {
    try {
      final userCredential = await NaverLoginService.login();
      if (userCredential != null && userCredential.user != null) {
        await saveUserToFirestore(userCredential.user!);
        return userCredential;
      }
      return null;
    } catch (e) {
      print('Naver login error: $e');
      rethrow;
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
        // 신규 유저: 닉네임은 온보딩에서 설정하므로 비워 둠. 프로필 사진은 모두 기본 이미지로 통일
        final userModel = UserModel(
          uid: user.uid,
          email: user.email ?? '',
          displayName: '', // 온보딩에서 처음 정한 닉네임으로 설정됨
          userType: '',
          createdAt: now,
          lastLoginAt: now,
          profileImage: defaultProfileImageUrl,
        );

        await userDocRef.set(userModel.toMap());
        print('New user saved to Firestore: ${user.uid}');
      } else {
        // 기존 유저
        await userDocRef.update({'lastLoginAt': Timestamp.fromDate(now)});
        print('User lastLoginAt updated: ${user.uid}');
      }

      // [FCM] Save FCM token to user doc for push notifications
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          await userDocRef.update({'fcmToken': token});
          print('FCM token saved for user: ${user.uid}');
        }
      } catch (e) {
        print('Error saving FCM token: $e');
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

      // Firestore 배치 제한 500건 → 청크 단위로 삭제
      const int batchLimit = 500;

      // 1. Delete user's posts (청크)
      try {
        final postsSnapshot = await _firestore
            .collection('posts')
            .where('userId', isEqualTo: userId)
            .get();
        for (var i = 0; i < postsSnapshot.docs.length; i += batchLimit) {
          final batch = _firestore.batch();
          final end = (i + batchLimit < postsSnapshot.docs.length)
              ? i + batchLimit
              : postsSnapshot.docs.length;
          for (var j = i; j < end; j++) {
            batch.delete(postsSnapshot.docs[j].reference);
          }
          await batch.commit();
        }
      } catch (e) {
        print('Error deleting posts: $e');
      }

      // 2. Delete user's meal logs (청크)
      try {
        final logsSnapshot = await _firestore
            .collection('meal_logs')
            .where('userId', isEqualTo: userId)
            .get();
        for (var i = 0; i < logsSnapshot.docs.length; i += batchLimit) {
          final batch = _firestore.batch();
          final end = (i + batchLimit < logsSnapshot.docs.length)
              ? i + batchLimit
              : logsSnapshot.docs.length;
          for (var j = i; j < end; j++) {
            batch.delete(logsSnapshot.docs[j].reference);
          }
          await batch.commit();
        }
      } catch (e) {
        print('Error deleting meal logs: $e');
      }

      // 3. Delete user's community posts (청크)
      try {
        final communitySnapshot = await _firestore
            .collection('community_posts')
            .where('userId', isEqualTo: userId)
            .get();
        for (var i = 0; i < communitySnapshot.docs.length; i += batchLimit) {
          final batch = _firestore.batch();
          final end = (i + batchLimit < communitySnapshot.docs.length)
              ? i + batchLimit
              : communitySnapshot.docs.length;
          for (var j = i; j < end; j++) {
            batch.delete(communitySnapshot.docs[j].reference);
          }
          await batch.commit();
        }
      } catch (e) {
        print('Error deleting community posts: $e');
      }

      // 3b. 레시피 게시글에서 탈퇴 계정의 공감(likedBy) 제거
      try {
        final postsLiked = await _firestore
            .collection('posts')
            .where('likedBy', arrayContains: userId)
            .get();
        for (var i = 0; i < postsLiked.docs.length; i += batchLimit) {
          final batch = _firestore.batch();
          final end = (i + batchLimit < postsLiked.docs.length)
              ? i + batchLimit
              : postsLiked.docs.length;
          for (var j = i; j < end; j++) {
            final ref = postsLiked.docs[j].reference;
            batch.update(ref, {
              'likes': FieldValue.increment(-1),
              'likedBy': FieldValue.arrayRemove([userId]),
            });
          }
          await batch.commit();
        }
      } catch (e) {
        print('Error removing likes from posts: $e');
      }

      // 3c. 커뮤니티 게시글에서 탈퇴 계정의 공감(likedBy) 제거
      try {
        final communityLiked = await _firestore
            .collection('community_posts')
            .where('likedBy', arrayContains: userId)
            .get();
        for (var i = 0; i < communityLiked.docs.length; i += batchLimit) {
          final batch = _firestore.batch();
          final end = (i + batchLimit < communityLiked.docs.length)
              ? i + batchLimit
              : communityLiked.docs.length;
          for (var j = i; j < end; j++) {
            final ref = communityLiked.docs[j].reference;
            batch.update(ref, {
              'likes': FieldValue.increment(-1),
              'likedBy': FieldValue.arrayRemove([userId]),
            });
          }
          await batch.commit();
        }
      } catch (e) {
        print('Error removing likes from community posts: $e');
      }

      // 3d. 레시피 댓글에서 탈퇴 계정의 공감(likedBy) 제거
      try {
        final commentsLiked = await _firestore
            .collection('comments')
            .where('likedBy', arrayContains: userId)
            .get();
        for (var i = 0; i < commentsLiked.docs.length; i += batchLimit) {
          final batch = _firestore.batch();
          final end = (i + batchLimit < commentsLiked.docs.length)
              ? i + batchLimit
              : commentsLiked.docs.length;
          for (var j = i; j < end; j++) {
            final ref = commentsLiked.docs[j].reference;
            batch.update(ref, {
              'likes': FieldValue.increment(-1),
              'likedBy': FieldValue.arrayRemove([userId]),
            });
          }
          await batch.commit();
        }
      } catch (e) {
        print('Error removing likes from recipe comments: $e');
      }

      // 3e. 커뮤니티 댓글에서 탈퇴 계정의 공감(likedBy) 제거 (collectionGroup)
      try {
        final communityCommentsLiked = await _firestore
            .collectionGroup('comments')
            .where('likedBy', arrayContains: userId)
            .get();
        final communityOnly = communityCommentsLiked.docs
            .where((d) => d.reference.path.contains('community_posts'))
            .toList();
        for (var i = 0; i < communityOnly.length; i += batchLimit) {
          final batch = _firestore.batch();
          final end = (i + batchLimit < communityOnly.length)
              ? i + batchLimit
              : communityOnly.length;
          for (var j = i; j < end; j++) {
            final ref = communityOnly[j].reference;
            batch.update(ref, {
              'likes': FieldValue.increment(-1),
              'likedBy': FieldValue.arrayRemove([userId]),
            });
          }
          await batch.commit();
        }
      } catch (e) {
        print('Error removing likes from community comments: $e');
      }

      // 3f. 탈퇴 계정이 작성한 레시피 댓글 삭제 + 해당 게시글 댓글 수 감소 (userId / authorId 둘 다 조회)
      try {
        final byUserId = await _firestore
            .collection('comments')
            .where('userId', isEqualTo: userId)
            .get();
        final byAuthorId = await _firestore
            .collection('comments')
            .where('authorId', isEqualTo: userId)
            .get();
        final seen = <String>{};
        final myCommentDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        for (var d in byUserId.docs) {
          myCommentDocs[d.id] = d;
          seen.add(d.id);
        }
        for (var d in byAuthorId.docs) {
          if (!seen.contains(d.id)) myCommentDocs[d.id] = d;
        }
        final myCommentsList = myCommentDocs.values.toList();
        const opsPerComment = 2;
        final commentChunk = batchLimit ~/ opsPerComment;
        for (var i = 0; i < myCommentsList.length; i += commentChunk) {
          final batch = _firestore.batch();
          final end = (i + commentChunk < myCommentsList.length)
              ? i + commentChunk
              : myCommentsList.length;
          for (var j = i; j < end; j++) {
            final doc = myCommentsList[j];
            final postId = doc.data()['postId'] as String?;
            batch.delete(doc.reference);
            if (postId != null && postId.isNotEmpty) {
              batch.update(
                _firestore.collection('posts').doc(postId),
                {'comments': FieldValue.increment(-1)},
              );
            }
          }
          await batch.commit();
        }
      } catch (e) {
        print('Error deleting user recipe comments: $e');
      }

      // 3g. 탈퇴 계정이 작성한 커뮤니티 댓글 삭제 + 해당 커뮤니티 글 댓글 수 감소
      try {
        final myCommunityCommentsSnap = await _firestore
            .collectionGroup('comments')
            .where('userId', isEqualTo: userId)
            .get();
        final communityCommentDocs = myCommunityCommentsSnap.docs
            .where((d) => d.reference.path.contains('community_posts'))
            .toList();
        const opsPerComment = 2;
        final commentChunk = batchLimit ~/ opsPerComment;
        for (var i = 0; i < communityCommentDocs.length; i += commentChunk) {
          final batch = _firestore.batch();
          final end = (i + commentChunk < communityCommentDocs.length)
              ? i + commentChunk
              : communityCommentDocs.length;
          for (var j = i; j < end; j++) {
            final doc = communityCommentDocs[j];
            final path = doc.reference.path;
            final segments = path.split('/');
            if (segments.length >= 2 && segments[0] == 'community_posts') {
              final postId = segments[1];
              batch.delete(doc.reference);
              batch.update(
                _firestore.collection('community_posts').doc(postId),
                {'commentCount': FieldValue.increment(-1)},
              );
            }
          }
          await batch.commit();
        }
      } catch (e) {
        print('Error deleting user community comments: $e');
      }

      // 4. 팔로우 관계 정리 (4a·4b 각각 try-catch로 분리 → 한쪽 실패해도 다른 쪽은 실행되어 팔로워 목록에서 탈퇴자 제거)
      const opsPerPair = 2; // delete 1 + update 1
      final chunkSize = batchLimit ~/ opsPerPair; // 250

      // 4a. 나를 팔로우하던 사람들: 각자의 following에서 userId 삭제, followingCount -1
      try {
        final followingMeSnap = await _firestore
            .collectionGroup('following')
            .where(FieldPath.documentId, isEqualTo: userId)
            .get();
        for (var i = 0; i < followingMeSnap.docs.length; i += chunkSize) {
          final batch = _firestore.batch();
          final end = (i + chunkSize < followingMeSnap.docs.length)
              ? i + chunkSize
              : followingMeSnap.docs.length;
          for (var j = i; j < end; j++) {
            final doc = followingMeSnap.docs[j];
            final followerUid = doc.reference.parent.parent?.id; // users/{followerUid}/following/userId
            if (followerUid != null && followerUid.isNotEmpty) {
              batch.delete(doc.reference);
              batch.set(
                _firestore.collection(_usersCollection).doc(followerUid),
                {'followingCount': FieldValue.increment(-1)},
                SetOptions(merge: true),
              );
            }
          }
          await batch.commit();
        }
      } catch (e) {
        print('Error cleaning follow relations (4a following): $e');
      }

      // 4b. 내가 팔로우하던 사람들: 각자의 followers에서 userId 삭제 → 상대방 팔로워 목록에서 "알 수 없음" 제거
      try {
        final myFollowingSnap = await _firestore
            .collection(_usersCollection)
            .doc(userId)
            .collection('following')
            .get();
        for (var i = 0; i < myFollowingSnap.docs.length; i += chunkSize) {
          final batch = _firestore.batch();
          final end = (i + chunkSize < myFollowingSnap.docs.length)
              ? i + chunkSize
              : myFollowingSnap.docs.length;
          for (var j = i; j < end; j++) {
            final followedUid = myFollowingSnap.docs[j].id;
            batch.delete(
              _firestore
                  .collection(_usersCollection)
                  .doc(followedUid)
                  .collection('followers')
                  .doc(userId),
            );
            batch.set(
              _firestore.collection(_usersCollection).doc(followedUid),
              {'followersCount': FieldValue.increment(-1)},
              SetOptions(merge: true),
            );
          }
          await batch.commit();
        }
      } catch (e) {
        print('Error cleaning follow relations (4b followers): $e');
      }

      // 4.5. 유저 서브컬렉션 삭제 (문서 삭제 시 자동 삭제되지 않아 수동 삭제)
      try {
        final notificationsSnap = await _firestore
            .collection(_usersCollection)
            .doc(userId)
            .collection('notifications')
            .get();
        for (var i = 0; i < notificationsSnap.docs.length; i += batchLimit) {
          final batch = _firestore.batch();
          final end = (i + batchLimit < notificationsSnap.docs.length)
              ? i + batchLimit
              : notificationsSnap.docs.length;
          for (var j = i; j < end; j++) {
            batch.delete(notificationsSnap.docs[j].reference);
          }
          await batch.commit();
        }
        final fcmTokensSnap = await _firestore
            .collection(_usersCollection)
            .doc(userId)
            .collection('fcmTokens')
            .get();
        for (var i = 0; i < fcmTokensSnap.docs.length; i += batchLimit) {
          final batch = _firestore.batch();
          final end = (i + batchLimit < fcmTokensSnap.docs.length)
              ? i + batchLimit
              : fcmTokensSnap.docs.length;
          for (var j = i; j < end; j++) {
            batch.delete(fcmTokensSnap.docs[j].reference);
          }
          await batch.commit();
        }
        // followers / following 서브컬렉션도 삭제 (4a·4b에서 상대 문서는 이미 정리됨)
        for (final subName in ['followers', 'following']) {
          final snap = await _firestore
              .collection(_usersCollection)
              .doc(userId)
              .collection(subName)
              .get();
          for (var i = 0; i < snap.docs.length; i += batchLimit) {
            final batch = _firestore.batch();
            final end = (i + batchLimit < snap.docs.length)
                ? i + batchLimit
                : snap.docs.length;
            for (var j = i; j < end; j++) {
              batch.delete(snap.docs[j].reference);
            }
            await batch.commit();
          }
        }
      } catch (e) {
        print('Error deleting user subcollections: $e');
      }

      // 5. Delete user document (서브컬렉션은 위에서 삭제)
      try {
        await _firestore.collection(_usersCollection).doc(userId).delete();
      } catch (e) {
        print('Error deleting user document: $e');
      }

      // 6. Delete Firebase Auth account
      await user.delete();

      // 7. Sign out locally
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
