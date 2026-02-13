import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for Report and Block functionality (User Safety System).
/// - Report: Creates documents in 'reports' collection for admin review.
/// - Block: Adds target UID to current user's blockedUserIds in Firestore.
class SafetyService {
  static final SafetyService _instance = SafetyService._internal();
  factory SafetyService() => _instance;
  SafetyService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _reportsPath = 'reports';
  static const String _usersPath = 'users';

  /// Create a report document.
  /// Fields: reporterUid, targetUid, contentId, type (post/comment), reason, createdAt.
  Future<void> report({
    required String reporterUid,
    required String targetUid,
    required String contentId,
    required String type,
    String? reason,
  }) async {
    try {
      await _firestore.collection(_reportsPath).add({
        'reporterUid': reporterUid,
        'targetUid': targetUid,
        'contentId': contentId,
        'type': type,
        'reason': reason ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error creating report: $e');
      rethrow;
    }
  }

  /// Block a user: add targetUid to current user's blockedUserIds.
  /// Uses FieldValue.arrayUnion to avoid duplicates.
  Future<void> blockUser({
    required String currentUid,
    required String targetUid,
  }) async {
    if (currentUid == targetUid) return;
    try {
      await _firestore.collection(_usersPath).doc(currentUid).update({
        'blockedUserIds': FieldValue.arrayUnion([targetUid]),
      });
    } catch (e) {
      print('Error blocking user: $e');
      rethrow;
    }
  }

  /// Unblock a user (optional, for future use).
  Future<void> unblockUser({
    required String currentUid,
    required String targetUid,
  }) async {
    try {
      await _firestore.collection(_usersPath).doc(currentUid).update({
        'blockedUserIds': FieldValue.arrayRemove([targetUid]),
      });
    } catch (e) {
      print('Error unblocking user: $e');
      rethrow;
    }
  }

  /// Get current user's blocked user IDs.
  Future<List<String>> getBlockedUserIds(String uid) async {
    try {
      final doc = await _firestore.collection(_usersPath).doc(uid).get();
      if (!doc.exists) return [];
      final data = doc.data();
      final list = data?['blockedUserIds'] as List<dynamic>?;
      return list?.map((e) => e.toString()).toList() ?? [];
    } catch (e) {
      print('Error getting blocked users: $e');
      return [];
    }
  }

  /// Stream blocked user IDs (for real-time filtering).
  Stream<List<String>> streamBlockedUserIds(String uid) {
    return _firestore
        .collection(_usersPath)
        .doc(uid)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return <String>[];
      final data = doc.data();
      final list = data?['blockedUserIds'] as List<dynamic>?;
      return list?.map((e) => e.toString()).toList() ?? [];
    });
  }
}
