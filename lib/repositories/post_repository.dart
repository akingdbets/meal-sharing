import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post_model.dart';
import 'comment_repository.dart';

/// Repository for managing post data from Firestore
class PostRepository {
  static final PostRepository _instance = PostRepository._internal();
  factory PostRepository() => _instance;
  PostRepository._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionPath = 'posts';

  /// Get all posts from Firestore
  Future<List<PostModel>> getAllPosts() async {
    try {
      final querySnapshot = await _firestore
          .collection(_collectionPath)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Error fetching posts: $e');
      return [];
    }
  }

  /// Get posts filtered by survival mode
  Future<List<PostModel>> getPostsByMode({required bool isSurvival}) async {
    try {
      final querySnapshot = await _firestore
          .collection(_collectionPath)
          .where('isSurvival', isEqualTo: isSurvival)
          .get();

      final posts = querySnapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
      // Sort by createdAt in memory to avoid index requirement
      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return posts;
    } catch (e) {
      print('Error fetching posts by mode: $e');
      return [];
    }
  }

  /// Get a single post by ID
  Future<PostModel?> getPostById(String id) async {
    try {
      final doc = await _firestore.collection(_collectionPath).doc(id).get();
      if (doc.exists) {
        return PostModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('Error fetching post by id: $e');
      return null;
    }
  }

  /// Stream posts for real-time updates
  Stream<List<PostModel>> streamAllPosts() {
    return _firestore
        .collection(_collectionPath)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PostModel.fromFirestore(doc))
            .toList());
  }

  /// Stream posts filtered by survival mode
  Stream<List<PostModel>> streamPostsByMode({required bool isSurvival}) {
    return _firestore
        .collection(_collectionPath)
        .where('isSurvival', isEqualTo: isSurvival)
        .snapshots()
        .map((snapshot) {
          final posts = snapshot.docs
              .map((doc) => PostModel.fromFirestore(doc))
              .toList();
          // Sort by createdAt in memory to avoid index requirement
          posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return posts;
        })
        .handleError((error) {
          print('Error streaming posts by mode: $error');
          return <PostModel>[];
        });
  }

  /// Create a new post
  Future<String> createPost(PostModel post) async {
    try {
      // Validate required fields
      if (post.userId.isEmpty || post.content.isEmpty) {
        throw Exception('필수 필드가 누락되었습니다.');
      }

      final docRef = await _firestore.collection(_collectionPath).add({
        'userId': post.userId,
        'authorName': post.authorName,
        'authorProfileImage': post.authorProfileImage,
        'content': post.content,
        'recipeSteps': post.recipeSteps,
        'mainImageUrl': post.mainImageUrl,
        'tags': post.tags,
        'isSurvival': post.isSurvival,
        'savedAmount': post.savedAmount,
        'ingredients': post.ingredients.map((ing) => ing.toJson()).toList(),
        'deliveryMenuName': post.deliveryMenuName,
        'servings': post.servings,
        'deliveryPricePerServing': post.deliveryPricePerServing,
        'cookingTime': post.cookingTime,
        'likes': post.likes,
        'comments': post.comments,
        'likedBy': post.likedBy,
        'createdAt': Timestamp.fromDate(post.createdAt),
        'youtubeVideoId': post.youtubeVideoId,
        'cookingTips': post.cookingTips,
      });
      
      print('Post created successfully with ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('Error creating post: $e');
      rethrow;
    }
  }

  /// Toggle like on a post
  Future<void> toggleLike(String postId, String userId, bool isLiked) async {
    try {
      if (isLiked) {
        // Unlike
        await _firestore.collection(_collectionPath).doc(postId).update({
          'likes': FieldValue.increment(-1),
          'likedBy': FieldValue.arrayRemove([userId]),
        });
      } else {
        // Like
        await _firestore.collection(_collectionPath).doc(postId).update({
          'likes': FieldValue.increment(1),
          'likedBy': FieldValue.arrayUnion([userId]),
        });
      }
    } catch (e) {
      print('Error toggling post like: $e');
      rethrow;
    }
  }

  /// Delete a post and all its comments
  Future<void> deletePost(String postId) async {
    try {
      final commentRepository = CommentRepository();
      await commentRepository.deleteAllCommentsForPost(postId);
      await _firestore.collection(_collectionPath).doc(postId).delete();
      print('Post $postId and its comments deleted');
    } catch (e) {
      print('Error deleting post: $e');
      rethrow;
    }
  }

  /// Update an existing post
  Future<void> updatePost(String postId, PostModel post) async {
    try {
      // Validate required fields
      if (post.userId.isEmpty || post.content.isEmpty) {
        throw Exception('필수 필드가 누락되었습니다.');
      }

      await _firestore.collection(_collectionPath).doc(postId).update({
        'content': post.content,
        'recipeSteps': post.recipeSteps,
        'mainImageUrl': post.mainImageUrl,
        'tags': post.tags,
        'isSurvival': post.isSurvival,
        'savedAmount': post.savedAmount,
        'ingredients': post.ingredients.map((ing) => ing.toJson()).toList(),
        'deliveryMenuName': post.deliveryMenuName,
        'servings': post.servings,
        'deliveryPricePerServing': post.deliveryPricePerServing,
        'cookingTime': post.cookingTime,
        'youtubeVideoId': post.youtubeVideoId,
        'cookingTips': post.cookingTips,
      });
      
      print('Post updated successfully: $postId');
    } catch (e) {
      print('Error updating post: $e');
      rethrow;
    }
  }

  /// 닉네임 변경 시 해당 유저의 모든 게시물에 authorName 반영
  Future<void> updateAuthorNameForUser(String userId, String newAuthorName) async {
    try {
      final snapshot = await _firestore
          .collection(_collectionPath)
          .where('userId', isEqualTo: userId)
          .get();
      if (snapshot.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'authorName': newAuthorName});
      }
      await batch.commit();
    } catch (e) {
      print('Error updating authorName for user posts: $e');
      rethrow;
    }
  }

  /// Get posts by user ID
  Future<List<PostModel>> getPostsByUserId(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection(_collectionPath)
          .where('userId', isEqualTo: userId)
          .get();

      final posts = querySnapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return posts;
    } catch (e) {
      print('Error fetching posts by user ID: $e');
      return [];
    }
  }

  /// Get posts by date range
  Future<List<PostModel>> getPostsByDateRange(DateTime startDate, DateTime endDate) async {
    try {
      final querySnapshot = await _firestore
          .collection(_collectionPath)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      final posts = querySnapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return posts;
    } catch (e) {
      print('Error fetching posts by date range: $e');
      return [];
    }
  }

  /// Get total saved amount for a user this month
  Future<int> getUserTotalSavedThisMonth(String userId) async {
    try {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, 1);
      final endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      
      final posts = await getPostsByDateRange(startDate, endDate);
      final userPosts = posts.where((post) => post.userId == userId).toList();
      
      int totalSaved = 0;
      for (var post in userPosts) {
        totalSaved += post.savedAmount;
      }
      
      return totalSaved;
    } catch (e) {
      print('Error calculating total saved: $e');
      return 0;
    }
  }

  /// Stream total saved amount for a user this month.
  /// 복합 인덱스 없이 userId만으로 조회 후 메모리에서 이번 달 필터.
  Stream<int> streamUserTotalSavedThisMonth(String userId) {
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, 1);
    final endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    return _firestore
        .collection(_collectionPath)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          int totalSaved = 0;
          for (var doc in snapshot.docs) {
            final post = PostModel.fromFirestore(doc);
            final createdAt = post.createdAt;
            if (!createdAt.isBefore(startDate) && !createdAt.isAfter(endDate)) {
              totalSaved += post.savedAmount;
            }
          }
          return totalSaved;
        })
        .handleError((error) {
          print('Error streaming total saved: $error');
          return 0;
        });
  }

  /// Get recent tags from latest posts
  /// Returns a list of unique tags sorted by frequency (most used first)
  Future<List<String>> getRecentTags({int limit = 50}) async {
    try {
      // Get recent posts (limit to avoid performance issues)
      final querySnapshot = await _firestore
          .collection(_collectionPath)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      // Collect all tags from posts
      final tagFrequency = <String, int>{};
      
      for (var doc in querySnapshot.docs) {
        final post = PostModel.fromFirestore(doc);
        for (var tag in post.tags) {
          // Ensure tag starts with # and is not empty
          final normalizedTag = tag.trim();
          if (normalizedTag.isNotEmpty) {
            // Count frequency
            tagFrequency[normalizedTag] = (tagFrequency[normalizedTag] ?? 0) + 1;
          }
        }
      }

      // Sort by frequency (descending), then alphabetically
      final sortedTags = tagFrequency.entries.toList()
        ..sort((a, b) {
          // First sort by frequency (descending)
          final freqCompare = b.value.compareTo(a.value);
          if (freqCompare != 0) return freqCompare;
          // If frequency is same, sort alphabetically
          return a.key.compareTo(b.key);
        });

      // Return top 15 tags
      return sortedTags.take(15).map((e) => e.key).toList();
    } catch (e) {
      print('Error fetching recent tags: $e');
      return [];
    }
  }

  /// Search posts by query string
  /// Searches in content, recipeSteps, and ingredient names
  Future<List<PostModel>> searchPosts(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      // Get recent 100 posts to search in memory (avoid Firestore query limitations)
      final querySnapshot = await _firestore
          .collection(_collectionPath)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();

      final allPosts = querySnapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();

      final lowerQuery = query.toLowerCase().trim();
      final matchingPosts = <PostModel>[];

      for (var post in allPosts) {
        // Search in content
        if (post.content.toLowerCase().contains(lowerQuery)) {
          matchingPosts.add(post);
          continue;
        }

        // Search in recipe steps
        final recipeText = post.recipeSteps.join(' ').toLowerCase();
        if (recipeText.contains(lowerQuery)) {
          matchingPosts.add(post);
          continue;
        }

        // Search in ingredient names
        final ingredientNames = post.ingredients.map((ing) => ing.name.toLowerCase()).join(' ');
        if (ingredientNames.contains(lowerQuery)) {
          matchingPosts.add(post);
          continue;
        }

        // Search in tags
        final tagsText = post.tags.join(' ').toLowerCase();
        if (tagsText.contains(lowerQuery)) {
          matchingPosts.add(post);
          continue;
        }
      }

      // Sort by createdAt (most recent first)
      matchingPosts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return matchingPosts;
    } catch (e) {
      print('Error searching posts: $e');
      return [];
    }
  }

  /// Get all tags with their counts
  /// Returns a list of maps with 'tag' and 'count' keys, sorted by count (descending)
  Future<List<Map<String, dynamic>>> getTagsWithCounts() async {
    try {
      // Get recent 100 posts to analyze
      final querySnapshot = await _firestore
          .collection(_collectionPath)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();

      // Count tag frequency
      final tagFrequency = <String, int>{};
      
      for (var doc in querySnapshot.docs) {
        final post = PostModel.fromFirestore(doc);
        for (var tag in post.tags) {
          final normalizedTag = tag.trim();
          if (normalizedTag.isNotEmpty) {
            tagFrequency[normalizedTag] = (tagFrequency[normalizedTag] ?? 0) + 1;
          }
        }
      }

      // Convert to list of maps and sort by count (descending)
      final tagList = tagFrequency.entries.map((entry) {
        return {
          'tag': entry.key,
          'count': entry.value,
        };
      }).toList();

      tagList.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
      
      return tagList;
    } catch (e) {
      print('Error getting tags with counts: $e');
      return [];
    }
  }

  /// Get posts by tag
  Future<List<PostModel>> getPostsByTag(String tag) async {
    if (tag.trim().isEmpty) return [];

    try {
      // Get recent 100 posts and filter by tag
      final querySnapshot = await _firestore
          .collection(_collectionPath)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();

      final allPosts = querySnapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();

      final normalizedTag = tag.trim().toLowerCase();
      final matchingPosts = allPosts.where((post) {
        return post.tags.any((postTag) => 
          postTag.trim().toLowerCase() == normalizedTag ||
          postTag.trim().toLowerCase().contains(normalizedTag)
        );
      }).toList();

      matchingPosts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return matchingPosts;
    } catch (e) {
      print('Error getting posts by tag: $e');
      return [];
    }
  }

  /// Toggle scrap status for a post
  Future<void> toggleScrap(String postId, String userId) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);
      final userDoc = await userRef.get();
      
      if (!userDoc.exists) {
        throw Exception('User document not found');
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final scrappedPostIds = (userData['scrappedPostIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      if (scrappedPostIds.contains(postId)) {
        // Remove from scraps
        await userRef.update({
          'scrappedPostIds': FieldValue.arrayRemove([postId]),
        });
      } else {
        // Add to scraps
        await userRef.update({
          'scrappedPostIds': FieldValue.arrayUnion([postId]),
        });
      }
    } catch (e) {
      print('Error toggling scrap: $e');
      rethrow;
    }
  }

  /// Get scrapped posts by post IDs
  Future<List<PostModel>> getScrappedPosts(List<String> postIds) async {
    if (postIds.isEmpty) return [];

    try {
      // Firestore 'whereIn' has a limit of 10 items, so we need to batch
      final List<PostModel> allPosts = [];
      final int batchSize = 10;

      for (int i = 0; i < postIds.length; i += batchSize) {
        final batch = postIds.skip(i).take(batchSize).toList();
        final querySnapshot = await _firestore
            .collection(_collectionPath)
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        final posts = querySnapshot.docs
            .map((doc) => PostModel.fromFirestore(doc))
            .toList();
        allPosts.addAll(posts);
      }

      // Sort by createdAt descending
      allPosts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return allPosts;
    } catch (e) {
      print('Error getting scrapped posts: $e');
      return [];
    }
  }

  /// Search posts by ingredients
  /// Returns posts that contain at least one of the specified ingredients
  /// 
  /// Note: Firestore's array-contains-any has a limit of 10 items.
  /// Since ingredients are stored as objects (not arrays), we filter in memory.
  /// For better performance, consider adding an 'ingredientNames' array field to posts.
  Future<List<PostModel>> searchPostsByIngredients(List<String> ingredients) async {
    if (ingredients.isEmpty) {
      return [];
    }

    try {
      // Normalize and limit ingredients (Firestore array-contains-any limit is 10)
      final normalizedIngredients = ingredients
          .map((ing) => ing.toLowerCase().trim())
          .where((ing) => ing.isNotEmpty)
          .toSet()
          .toList()
          .take(10) // Limit to 10 for potential future array-contains-any optimization
          .toList();

      // Get recent posts to limit data transfer
      // Since ingredients are stored as objects, we filter in memory
      final querySnapshot = await _firestore
          .collection(_collectionPath)
          .orderBy('createdAt', descending: true)
          .limit(200) // Limit to recent 200 posts for performance
          .get();

      final allPosts = querySnapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();

      // Filter posts that contain at least one of the specified ingredients
      final matchingPosts = allPosts.where((post) {
        // Extract ingredient names from post
        final postIngredientNames = post.ingredients
            .map((ing) => ing.name.toLowerCase().trim())
            .toSet();

        // Check if any of the selected ingredients match any post ingredient
        return normalizedIngredients.any((selectedIng) {
          return postIngredientNames.any((postIng) {
            // Exact match or partial match (e.g., "파" matches "대파")
            return postIng == selectedIng ||
                postIng.contains(selectedIng) ||
                selectedIng.contains(postIng);
          });
        });
      }).toList();

      // Sort by createdAt (most recent first)
      matchingPosts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return matchingPosts;
    } catch (e) {
      print('Error searching posts by ingredients: $e');
      return [];
    }
  }

  /// Sync comment count for a post (self-healing)
  /// Counts: non-deleted top-level comments + all replies (regardless of deletion status)
  Future<void> syncCommentCount(String postId) async {
    try {
      // Get all comments for this post
      final allCommentsSnapshot = await _firestore
          .collection('comments')
          .where('postId', isEqualTo: postId)
          .get();

      int count = 0;
      
      for (var doc in allCommentsSnapshot.docs) {
        final data = doc.data();
        final parentCommentId = data['parentCommentId'];
        final isDeleted = data['isDeleted'] as bool? ?? false;
        
        if (parentCommentId == null) {
          // Top-level comment: count only if not deleted
          if (!isDeleted) {
            count++;
          }
        } else {
          // Reply: count regardless of deletion status
          count++;
        }
      }

      // Update the post's comment count field
      await _firestore
          .collection(_collectionPath)
          .doc(postId)
          .update({
        'comments': count,
      });

      print('Synced comment count for post $postId: $count (non-deleted top-level + all replies)');
    } catch (e) {
      print('Error syncing comment count: $e');
      rethrow;
    }
  }
}
