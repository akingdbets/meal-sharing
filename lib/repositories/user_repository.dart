import 'package:cloud_firestore/cloud_firestore.dart';

/// Repository for user follow/following and user profile data.
/// Structure: users/{uid}, users/{uid}/followers/{followerUid}, users/{uid}/following/{followingUid}
class UserRepository {
  static final UserRepository _instance = UserRepository._internal();
  factory UserRepository() => _instance;
  UserRepository._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _usersPath = 'users';

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _firestore.collection(_usersPath).doc(uid);

  /// users/{uid}/followers/{followerUid}
  CollectionReference<Map<String, dynamic>> _followersRef(String uid) =>
      _firestore.collection(_usersPath).doc(uid).collection('followers');

  /// users/{uid}/following/{followingUid}
  CollectionReference<Map<String, dynamic>> _followingRef(String uid) =>
      _firestore.collection(_usersPath).doc(uid).collection('following');

  /// Follow target user. Transaction: add to my following, their followers, increment counts.
  Future<void> followUser(String currentUid, String targetUid) async {
    if (currentUid == targetUid) return;
    final now = FieldValue.serverTimestamp();
    await _firestore.runTransaction((tx) async {
      final myFollowingRef = _followingRef(currentUid).doc(targetUid);
      final theirFollowersRef = _followersRef(targetUid).doc(currentUid);
      final myUserRef = _userRef(currentUid);
      final theirUserRef = _userRef(targetUid);

      tx.set(myFollowingRef, {'createdAt': now});
      tx.set(theirFollowersRef, {'createdAt': now});
      tx.set(myUserRef, {'followingCount': FieldValue.increment(1)}, SetOptions(merge: true));
      tx.set(theirUserRef, {'followersCount': FieldValue.increment(1)}, SetOptions(merge: true));
    });
  }

  /// Unfollow target user.
  Future<void> unfollowUser(String currentUid, String targetUid) async {
    if (currentUid == targetUid) return;
    await _firestore.runTransaction((tx) async {
      final myFollowingRef = _followingRef(currentUid).doc(targetUid);
      final theirFollowersRef = _followersRef(targetUid).doc(currentUid);
      final myUserRef = _userRef(currentUid);
      final theirUserRef = _userRef(targetUid);

      tx.delete(myFollowingRef);
      tx.delete(theirFollowersRef);
      tx.set(myUserRef, {'followingCount': FieldValue.increment(-1)}, SetOptions(merge: true));
      tx.set(theirUserRef, {'followersCount': FieldValue.increment(-1)}, SetOptions(merge: true));
    });
  }

  /// Check if current user follows target user.
  Future<bool> isFollowing(String currentUid, String targetUid) async {
    if (currentUid == targetUid) return false;
    final doc = await _followingRef(currentUid).doc(targetUid).get();
    return doc.exists;
  }

  /// Stream: is current user following target?
  Stream<bool> streamIsFollowing(String currentUid, String targetUid) {
    if (currentUid == targetUid) return Stream.value(false);
    return _followingRef(currentUid).doc(targetUid).snapshots().map((d) => d.exists);
  }

  /// Follower UIDs (stream).
  Stream<List<String>> streamFollowers(String uid) {
    return _followersRef(uid).snapshots().map((snap) =>
        snap.docs.map((d) => d.id).toList());
  }

  /// Following UIDs (stream).
  Stream<List<String>> streamFollowing(String uid) {
    return _followingRef(uid).snapshots().map((snap) =>
        snap.docs.map((d) => d.id).toList());
  }

  /// Get follower UIDs once.
  Future<List<String>> getFollowers(String uid) async {
    final snap = await _followersRef(uid).get();
    return snap.docs.map((d) => d.id).toList();
  }

  /// Get following UIDs once.
  Future<List<String>> getFollowing(String uid) async {
    final snap = await _followingRef(uid).get();
    return snap.docs.map((d) => d.id).toList();
  }

  /// Get a single user's public info (displayName, profileImageUrl, followersCount, followingCount).
  Future<Map<String, dynamic>?> getUserInfo(String uid) async {
    final doc = await _userRef(uid).get();
    if (!doc.exists) return null;
    return doc.data();
  }

  /// Stream a single user doc (for counts and displayName).
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamUser(String uid) {
    return _userRef(uid).snapshots();
  }

  /// Update user profile (displayName, profileImageUrl). Firestore only; call Auth.updateDisplayName separately for Auth.
  Future<void> updateProfile(String uid, {String? displayName, String? profileImageUrl}) async {
    final ref = _userRef(uid);
    final updates = <String, dynamic>{};
    if (displayName != null) updates['displayName'] = displayName;
    if (profileImageUrl != null) updates['profileImageUrl'] = profileImageUrl;
    if (updates.isEmpty) return;
    await ref.set(updates, SetOptions(merge: true));
  }

  /// Batch get user info for multiple UIDs (for follow list display).
  Future<List<Map<String, dynamic>>> getUsersByIds(List<String> uids) async {
    if (uids.isEmpty) return [];
    final out = <Map<String, dynamic>>[];
    for (final uid in uids) {
      final data = await getUserInfo(uid);
      if (data != null) {
        out.add({'uid': uid, ...data});
      } else {
        out.add({'uid': uid, 'displayName': '알 수 없음', 'profileImageUrl': null});
      }
    }
    return out;
  }
}
