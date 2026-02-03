import 'package:cloud_firestore/cloud_firestore.dart';

/// User model for Firestore user data
class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String userType; // 'housewife' or 'single'
  final DateTime createdAt;
  final DateTime lastLoginAt;
  final List<String> scrappedPostIds; // 스크랩한 게시물 ID 리스트
  final int followersCount;
  final int followingCount;

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.userType,
    required this.createdAt,
    required this.lastLoginAt,
    this.scrappedPostIds = const [],
    this.followersCount = 0,
    this.followingCount = 0,
  });

  /// Convert UserModel to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'userType': userType,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLoginAt': Timestamp.fromDate(lastLoginAt),
      'scrappedPostIds': scrappedPostIds,
    };
  }

  /// Create UserModel from Firestore document
  factory UserModel.fromMap(Map<String, dynamic> map) {
    DateTime createdAt;
    if (map['createdAt'] is Timestamp) {
      createdAt = (map['createdAt'] as Timestamp).toDate();
    } else if (map['createdAt'] is DateTime) {
      createdAt = map['createdAt'] as DateTime;
    } else {
      createdAt = DateTime.now();
    }

    DateTime lastLoginAt;
    if (map['lastLoginAt'] is Timestamp) {
      lastLoginAt = (map['lastLoginAt'] as Timestamp).toDate();
    } else if (map['lastLoginAt'] is DateTime) {
      lastLoginAt = map['lastLoginAt'] as DateTime;
    } else {
      lastLoginAt = DateTime.now();
    }

    return UserModel(
      uid: map['uid'] as String? ?? '',
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      userType: map['userType'] as String? ?? 'housewife',
      createdAt: createdAt,
      lastLoginAt: lastLoginAt,
      scrappedPostIds: (map['scrappedPostIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      followersCount: (map['followersCount'] as int?) ?? 0,
      followingCount: (map['followingCount'] as int?) ?? 0,
    );
  }

  /// Create UserModel from Firestore DocumentSnapshot
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel.fromMap({
      ...data,
      'uid': doc.id,
    });
  }
}
