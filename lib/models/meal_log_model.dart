import 'package:cloud_firestore/cloud_firestore.dart';

/// Meal log entry model
class MealLogModel {
  final String id;
  final String userId;
  final String mealTitle;
  final String? imageUrl;
  final String? postId; // Link to post ID
  final DateTime date;
  final DateTime createdAt;

  MealLogModel({
    required this.id,
    required this.userId,
    required this.mealTitle,
    this.imageUrl,
    this.postId,
    required this.date,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'mealTitle': mealTitle,
      'imageUrl': imageUrl,
      'postId': postId,
      'date': Timestamp.fromDate(date),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory MealLogModel.fromJson(Map<String, dynamic> json) {
    DateTime date;
    if (json['date'] is Timestamp) {
      date = (json['date'] as Timestamp).toDate();
    } else if (json['date'] is DateTime) {
      date = json['date'] as DateTime;
    } else {
      date = DateTime.now();
    }

    DateTime createdAt;
    if (json['createdAt'] is Timestamp) {
      createdAt = (json['createdAt'] as Timestamp).toDate();
    } else if (json['createdAt'] is DateTime) {
      createdAt = json['createdAt'] as DateTime;
    } else {
      createdAt = DateTime.now();
    }

    return MealLogModel(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      mealTitle: json['mealTitle'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      postId: json['postId'] as String?,
      date: date,
      createdAt: createdAt,
    );
  }

  factory MealLogModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MealLogModel.fromJson({
      ...data,
      'id': doc.id,
    });
  }
}
