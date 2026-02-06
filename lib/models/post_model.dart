import 'package:cloud_firestore/cloud_firestore.dart';

/// Ingredient model for post ingredients
class Ingredient {
  final String name;
  final String coupangLink;
  final String? quantity; // Quantity (e.g., "2", "500")
  final String? unit; // Unit (e.g., "개", "g", "ml")

  Ingredient({
    required this.name,
    required this.coupangLink,
    this.quantity,
    this.unit,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'coupangLink': coupangLink,
      'quantity': quantity,
      'unit': unit,
    };
  }

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      name: json['name'] as String? ?? '',
      coupangLink: json['coupangLink'] as String? ?? '',
      quantity: json['quantity'] as String?,
      unit: json['unit'] as String?,
    );
  }
}

/// Post model for feed posts
class PostModel {
  final String id;
  final String userId;
  final String authorName;
  final String? authorProfileImage;
  final String content;
  final List<String> recipeSteps; // Recipe steps as list
  final String? mainImageUrl;
  final List<String> tags;
  final bool isSurvival; // true: Survival Mode, false: Housewife Mode
  final int savedAmount; // Calculated: deliveryPricePerServing * servings
  final List<Ingredient> ingredients;
  // Delivery-related fields
  final String? deliveryMenuName; // Menu name for delivery comparison
  final int servings; // Number of servings
  final int deliveryPricePerServing; // Average delivery price per serving
  final int? cookingTime; // Cooking time in minutes
  final int likes; // Number of likes
  final int comments; // Number of comments
  final List<String> likedBy; // List of user IDs who liked this post
  final DateTime createdAt;
  final String? youtubeVideoId; // YouTube video ID for in-app playback
  final String? cookingTips; // Optional cooking tips / notes

  PostModel({
    required this.id,
    required this.userId,
    required this.authorName,
    this.authorProfileImage,
    required this.content,
    required this.recipeSteps,
    this.mainImageUrl,
    required this.tags,
    required this.isSurvival,
    required this.savedAmount,
    required this.ingredients,
    this.deliveryMenuName,
    this.servings = 1,
    this.deliveryPricePerServing = 0,
    this.cookingTime,
    this.likes = 0,
    this.comments = 0,
    this.likedBy = const [],
    required this.createdAt,
    this.youtubeVideoId,
    this.cookingTips,
  });

  /// Convert PostModel to JSON for Firestore
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'authorName': authorName,
      'authorProfileImage': authorProfileImage,
      'content': content,
      'recipeSteps': recipeSteps,
      'mainImageUrl': mainImageUrl,
      'tags': tags,
      'isSurvival': isSurvival,
      'savedAmount': savedAmount,
      'ingredients': ingredients.map((ing) => ing.toJson()).toList(),
      'deliveryMenuName': deliveryMenuName,
      'servings': servings,
      'deliveryPricePerServing': deliveryPricePerServing,
      'cookingTime': cookingTime,
      'likes': likes,
      'comments': comments,
      'likedBy': likedBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'youtubeVideoId': youtubeVideoId,
      'cookingTips': cookingTips,
    };
  }

  /// Create PostModel from Firestore document
  factory PostModel.fromJson(Map<String, dynamic> json) {
    // Handle Timestamp from Firestore
    DateTime createdAt;
    if (json['createdAt'] is Timestamp) {
      createdAt = (json['createdAt'] as Timestamp).toDate();
    } else if (json['createdAt'] is DateTime) {
      createdAt = json['createdAt'] as DateTime;
    } else {
      createdAt = DateTime.now();
    }

    // Handle recipeSteps - support both old 'recipe' (String) and new 'recipeSteps' (List)
    List<String> recipeSteps = [];
    if (json['recipeSteps'] != null) {
      recipeSteps = (json['recipeSteps'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
    } else if (json['recipe'] != null) {
      // Legacy support: convert old String recipe to List
      final recipeStr = json['recipe'] as String?;
      if (recipeStr != null && recipeStr.isNotEmpty) {
        recipeSteps = recipeStr.split('\n').where((s) => s.trim().isNotEmpty).toList();
      }
    }

    return PostModel(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      authorName: json['authorName'] as String? ?? '',
      authorProfileImage: json['authorProfileImage'] as String?,
      content: json['content'] as String? ?? '',
      recipeSteps: recipeSteps,
      mainImageUrl: json['mainImageUrl'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      isSurvival: json['isSurvival'] as bool? ?? false,
      savedAmount: json['savedAmount'] as int? ?? 0,
      ingredients: (json['ingredients'] as List<dynamic>?)
              ?.map((ing) => Ingredient.fromJson(ing as Map<String, dynamic>))
              .toList() ??
          [],
      deliveryMenuName: json['deliveryMenuName'] as String?,
      servings: json['servings'] as int? ?? 1,
      deliveryPricePerServing: json['deliveryPricePerServing'] as int? ?? 0,
      cookingTime: json['cookingTime'] as int?,
      likes: json['likes'] as int? ?? 0,
      comments: json['comments'] as int? ?? 0,
      likedBy: (json['likedBy'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: createdAt,
      youtubeVideoId: json['youtubeVideoId'] as String?,
      cookingTips: json['cookingTips'] as String?,
    );
  }

  /// Create PostModel from Firestore DocumentSnapshot
  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PostModel.fromJson({
      ...data,
      'id': doc.id,
    });
  }

  /// Create a copy of PostModel with updated fields
  PostModel copyWith({
    String? id,
    String? userId,
    String? authorName,
    String? authorProfileImage,
    String? content,
    List<String>? recipeSteps,
    String? mainImageUrl,
    List<String>? tags,
    bool? isSurvival,
    int? savedAmount,
    List<Ingredient>? ingredients,
    String? deliveryMenuName,
    int? servings,
    int? deliveryPricePerServing,
    int? cookingTime,
    int? likes,
    int? comments,
    List<String>? likedBy,
    DateTime? createdAt,
    String? youtubeVideoId,
    String? cookingTips,
  }) {
    return PostModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      authorName: authorName ?? this.authorName,
      authorProfileImage: authorProfileImage ?? this.authorProfileImage,
      content: content ?? this.content,
      recipeSteps: recipeSteps ?? this.recipeSteps,
      mainImageUrl: mainImageUrl ?? this.mainImageUrl,
      tags: tags ?? this.tags,
      isSurvival: isSurvival ?? this.isSurvival,
      savedAmount: savedAmount ?? this.savedAmount,
      ingredients: ingredients ?? this.ingredients,
      deliveryMenuName: deliveryMenuName ?? this.deliveryMenuName,
      servings: servings ?? this.servings,
      deliveryPricePerServing: deliveryPricePerServing ?? this.deliveryPricePerServing,
      cookingTime: cookingTime ?? this.cookingTime,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      likedBy: likedBy ?? this.likedBy,
      createdAt: createdAt ?? this.createdAt,
      youtubeVideoId: youtubeVideoId ?? this.youtubeVideoId,
      cookingTips: cookingTips ?? this.cookingTips,
    );
  }
}
