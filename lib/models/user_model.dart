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
  final String? profileImage; // [추가됨] 프로필 이미지 URL (AuthService 에러 해결용)

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
    this.profileImage, // [추가됨] 생성자 파라미터
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
      'followersCount': followersCount, // [보완] DB 저장 시 누락되지 않도록 추가
      'followingCount': followingCount, // [보완] DB 저장 시 누락되지 않도록 추가
      'profileImage': profileImage, // [추가됨] DB 저장 시 프로필 이미지 포함
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
      scrappedPostIds:
          (map['scrappedPostIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      followersCount: (map['followersCount'] as int?) ?? 0,
      followingCount: (map['followingCount'] as int?) ?? 0,
      profileImage: map['profileImage'] as String?, // [추가됨] 불러오기 로직
    );
  }

  /// Create UserModel from Firestore DocumentSnapshot
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    // 데이터가 없는 경우를 대비해 안전하게 처리
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserModel.fromMap({...data, 'uid': doc.id});
  }
}
