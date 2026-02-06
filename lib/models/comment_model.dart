import 'package:cloud_firestore/cloud_firestore.dart';

/// Comment model for post comments
class CommentModel {
  final String id;
  final String postId;
  final String userId;
  final String authorId; // Author user ID (for querying user's comments)
  final String authorName;
  final String? authorProfileImage;
  final String content;
  final String? imageUrl; // Image URL for comment
  final String? parentCommentId; // For nested comments (replies)
  final int likes;
  final List<String> likedBy; // List of user IDs who liked this comment
  final DateTime createdAt;
  final bool isDeleted; // Whether the comment is deleted (soft delete)

  CommentModel({
    required this.id,
    required this.postId,
    required this.userId,
    required this.authorId, // Added authorId field
    required this.authorName,
    this.authorProfileImage,
    required this.content,
    this.imageUrl,
    this.parentCommentId,
    this.likes = 0,
    this.likedBy = const [],
    required this.createdAt,
    this.isDeleted = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'postId': postId,
      'userId': userId,
      'authorId': authorId.isNotEmpty ? authorId : userId, // Ensure authorId is always set (fallback to userId)
      'authorName': authorName,
      'authorProfileImage': authorProfileImage,
      'content': content,
      'imageUrl': imageUrl,
      'parentCommentId': parentCommentId,
      'likes': likes,
      'likedBy': likedBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'isDeleted': isDeleted,
    };
  }

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    DateTime createdAt;
    if (json['createdAt'] is Timestamp) {
      createdAt = (json['createdAt'] as Timestamp).toDate();
    } else if (json['createdAt'] is DateTime) {
      createdAt = json['createdAt'] as DateTime;
    } else {
      createdAt = DateTime.now();
    }

    return CommentModel(
      id: json['id'] as String? ?? '',
      postId: json['postId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      authorId: (json['authorId'] as String?)?.isNotEmpty == true 
          ? (json['authorId'] as String)
          : (json['userId'] as String? ?? ''), // Added authorId with fallback to userId for backward compatibility
      authorName: json['authorName'] as String? ?? '',
      authorProfileImage: json['authorProfileImage'] as String?,
      content: json['content'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      parentCommentId: json['parentCommentId'] as String?,
      likes: json['likes'] as int? ?? 0,
      likedBy: (json['likedBy'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: createdAt,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

  factory CommentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CommentModel.fromJson({
      ...data,
      'id': doc.id,
    });
  }
}
