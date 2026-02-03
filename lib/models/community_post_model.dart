import 'package:cloud_firestore/cloud_firestore.dart';

/// Community post model (separate from recipe posts).
/// Stored in Firestore collection: community_posts.
class CommunityPostModel {
  final String id;
  final String userId;
  final String authorName;
  final String? authorProfileImage;
  final String title;
  final String content;
  /// Image URL(s). Single image stored as list of one element.
  final List<String> imageUrls;
  final String category;
  final int likes;
  final List<String> likedBy;
  final int commentCount;
  final DateTime createdAt;

  CommunityPostModel({
    required this.id,
    required this.userId,
    required this.authorName,
    this.authorProfileImage,
    required this.title,
    required this.content,
    this.imageUrls = const [],
    this.category = 'general',
    this.likes = 0,
    this.likedBy = const [],
    this.commentCount = 0,
    required this.createdAt,
  });

  /// First image URL for backward compatibility / single-image UI.
  String? get imageUrl => imageUrls.isNotEmpty ? imageUrls.first : null;

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'authorName': authorName,
      'authorProfileImage': authorProfileImage,
      'title': title,
      'content': content,
      'imageUrls': imageUrls,
      'category': category,
      'likes': likes,
      'likedBy': likedBy,
      'commentCount': commentCount,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory CommunityPostModel.fromJson(Map<String, dynamic> json) {
    DateTime createdAt;
    if (json['createdAt'] is Timestamp) {
      createdAt = (json['createdAt'] as Timestamp).toDate();
    } else if (json['createdAt'] is DateTime) {
      createdAt = json['createdAt'] as DateTime;
    } else {
      createdAt = DateTime.now();
    }

    List<String> imageUrls = [];
    if (json['imageUrls'] != null && json['imageUrls'] is List) {
      imageUrls = (json['imageUrls'] as List<dynamic>)
          .map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (json['imageUrl'] != null && json['imageUrl'] is String) {
      final single = (json['imageUrl'] as String).trim();
      if (single.isNotEmpty) imageUrls = [single];
    }

    return CommunityPostModel(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      authorName: json['authorName'] as String? ?? '',
      authorProfileImage: json['authorProfileImage'] as String?,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      imageUrls: imageUrls,
      category: json['category'] as String? ?? json['type'] as String? ?? 'general',
      likes: json['likes'] as int? ?? 0,
      likedBy: (json['likedBy'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      commentCount: json['commentCount'] as int? ?? json['answers'] as int? ?? 0,
      createdAt: createdAt,
    );
  }

  factory CommunityPostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CommunityPostModel.fromJson({
      ...data,
      'id': doc.id,
    });
  }
}
