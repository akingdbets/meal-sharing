import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
      // This is a placeholder for future implementation
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
      // This is a placeholder for future implementation
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
      
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        // User canceled the sign-in
        print('Google sign-in was canceled');
        return null;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      final userCredential = await _auth.signInWithCredential(credential);
      print('Google login successful: ${userCredential.user?.uid}');
      
      // Save user to Firestore
      if (userCredential.user != null) {
        await saveUserToFirestore(userCredential.user!);
      }
      
      return userCredential;
    } catch (e) {
      print('Google login error: $e');
      // If Google sign-in fails, show error message
      rethrow;
    }
  }

  /// Sign in anonymously (Guest mode)
  Future<UserCredential?> signInAnonymously() async {
    try {
      print('Guest Mode Pressed');
      final userCredential = await _auth.signInAnonymously();
      print('Anonymous login successful: ${userCredential.user?.uid}');
      
      // Save user to Firestore
      if (userCredential.user != null) {
        await saveUserToFirestore(userCredential.user!);
      }
      
      return userCredential;
    } catch (e) {
      print('Anonymous login error: $e');
      return null;
    }
  }

  /// Update display name in Firebase Auth (for global sync after profile edit).
  Future<void> updateDisplayName(String displayName) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.updateDisplayName(displayName);
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      // Sign out from Google Sign In first to allow account selection on next login
      await _googleSignIn.signOut();
      // Sign out from Firebase Auth
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
        // New user - create new document with empty values for onboarding
        // Onboarding screen will set displayName and userType
        final userModel = UserModel(
          uid: user.uid,
          email: user.email ?? '',
          displayName: '', // Empty - will be set in onboarding
          userType: '', // Empty - will be set in onboarding
          createdAt: now,
          lastLoginAt: now,
        );

        await userDocRef.set(userModel.toMap());
        print('New user saved to Firestore: ${user.uid}');
      } else {
        // Existing user - update only lastLoginAt
        await userDocRef.update({
          'lastLoginAt': Timestamp.fromDate(now),
        });
        print('User lastLoginAt updated: ${user.uid}');
      }
    } catch (e) {
      print('Error saving user to Firestore: $e');
      rethrow;
    }
  }

  /// Delete user account and all associated data.
  /// 재인증 성공 후에만 Firestore 삭제 및 user.delete()를 수행합니다.
  /// (requires-recent-login 방지: Google 등으로 먼저 재인증)
  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인된 사용자가 없습니다.');
      }

      final userId = user.uid;

      // 0. 재인증 (계정 삭제는 민감 작업이므로 최근 로그인 필요. 구글 계정 선택 창 없이 silent만 시도)
      final isGoogleUser = user.providerData.any((p) => p.providerId == 'google.com');
      if (!isGoogleUser) {
        throw FirebaseAuthException(
          code: 'requires-recent-login',
          message: '탈퇴하려면 Google로 로그인한 후 다시 시도해주세요.',
        );
      }
      // signInSilently()만 사용해 계정 선택 UI가 뜨지 않도록 함. 실패 시 로그인 페이지에서 다시 로그인 후 탈퇴 유도
      final GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();
      if (googleUser == null) {
        throw FirebaseAuthException(
          code: 'requires-recent-login',
          message: '보안을 위해 다시 로그인한 후 탈퇴해주세요.',
        );
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(credential);

      // 1. Delete user's posts (Firestore 삭제는 user.delete() 이전에 완료)
      try {
        final postsSnapshot = await _firestore
            .collection('posts')
            .where('userId', isEqualTo: userId)
            .get();
        
        final batch = _firestore.batch();
        for (var doc in postsSnapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        print('Deleted ${postsSnapshot.docs.length} posts');
      } catch (e) {
        print('Error deleting posts: $e');
        // Continue even if post deletion fails
      }

      // 2. Delete user's meal logs
      try {
        final mealLogsSnapshot = await _firestore
            .collection('meal_logs')
            .where('userId', isEqualTo: userId)
            .get();
        
        final batch = _firestore.batch();
        for (var doc in mealLogsSnapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        print('Deleted ${mealLogsSnapshot.docs.length} meal logs');
      } catch (e) {
        print('Error deleting meal logs: $e');
        // Continue even if meal log deletion fails
      }

      // 3. Delete user's community posts
      try {
        final communityPostsSnapshot = await _firestore
            .collection('community_posts')
            .where('userId', isEqualTo: userId)
            .get();
        
        final batch = _firestore.batch();
        for (var doc in communityPostsSnapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        print('Deleted ${communityPostsSnapshot.docs.length} community posts');
      } catch (e) {
        print('Error deleting community posts: $e');
        // Continue even if community post deletion fails
      }

      // 4. Delete user document from Firestore
      try {
        await _firestore.collection(_usersCollection).doc(userId).delete();
        print('Deleted user document from Firestore');
      } catch (e) {
        print('Error deleting user document: $e');
        // Continue even if user document deletion fails
      }

      // 5. Sign out from Google Sign In
      try {
        await _googleSignIn.signOut();
      } catch (e) {
        print('Error signing out from Google: $e');
        // Continue even if Google sign out fails
      }

      // 6. Delete Firebase Auth account (Firestore 삭제 완료 후에만 실행)
      await user.delete();
      print('User account deleted from Firebase Auth');

      // 7. Sign out from Firebase Auth
      await _auth.signOut();
      print('User signed out after account deletion');
    } catch (e) {
      print('Error deleting account: $e');
      rethrow;
    }
  }
}
