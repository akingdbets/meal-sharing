import 'package:cloud_firestore/cloud_firestore.dart';

/// Comment model for community_posts/{postId}/comments subcollection.
class CommunityCommentModel {
  final String id;
  final String userId;
  final String authorName;
  final String? authorProfileImage;
  final String content;
  final String? parentCommentId;
  final int likes;
  final List<String> likedBy;
  final DateTime createdAt;
  final bool isDeleted;

  CommunityCommentModel({
    required this.id,
    required this.userId,
    required this.authorName,
    this.authorProfileImage,
    required this.content,
    this.parentCommentId,
    this.likes = 0,
    this.likedBy = const [],
    required this.createdAt,
    this.isDeleted = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'authorName': authorName,
      'authorProfileImage': authorProfileImage,
      'content': content,
      'parentCommentId': parentCommentId,
      'likes': likes,
      'likedBy': likedBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'isDeleted': isDeleted,
    };
  }

  factory CommunityCommentModel.fromJson(Map<String, dynamic> json) {
    DateTime createdAt;
    if (json['createdAt'] is Timestamp) {
      createdAt = (json['createdAt'] as Timestamp).toDate();
    } else if (json['createdAt'] is DateTime) {
      createdAt = json['createdAt'] as DateTime;
    } else {
      createdAt = DateTime.now();
    }
    return CommunityCommentModel(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      authorName: json['authorName'] as String? ?? '',
      authorProfileImage: json['authorProfileImage'] as String?,
      content: json['content'] as String? ?? '',
      parentCommentId: json['parentCommentId'] as String?,
      likes: json['likes'] as int? ?? 0,
      likedBy: (json['likedBy'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: createdAt,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

  factory CommunityCommentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CommunityCommentModel.fromJson({...data, 'id': doc.id});
  }
}
