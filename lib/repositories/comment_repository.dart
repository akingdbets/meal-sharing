import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';
import '../models/comment_model.dart';

/// Repository for managing comments from Firestore
class CommentRepository {
  static final CommentRepository _instance = CommentRepository._internal();
  factory CommentRepository() => _instance;
  CommentRepository._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionPath = 'comments';

  /// Stream comments for a post (top-level comments only)
  /// Note: Removed limit to show all comments
  Stream<List<CommentModel>> streamComments(String postId) {
    return _firestore
        .collection(_collectionPath)
        .where('postId', isEqualTo: postId)
        .where('parentCommentId', isNull: true)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
      final comments = snapshot.docs
          .map((doc) => CommentModel.fromFirestore(doc))
          .toList();
      return comments;
    }).handleError((error) {
      print('Error streaming comments: $error');
      return <CommentModel>[];
    });
  }

  /// Stream replies for a comment
  Stream<List<CommentModel>> streamReplies(String parentCommentId) {
    return _firestore
        .collection(_collectionPath)
        .where('parentCommentId', isEqualTo: parentCommentId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
      final replies = snapshot.docs
          .map((doc) => CommentModel.fromFirestore(doc))
          .toList();
      return replies;
    }).handleError((error) {
      print('Error streaming replies: $error');
      return <CommentModel>[];
    });
  }

  /// Create a new comment (Transaction: 댓글 + 게시글 카운트 + 알림 문서를 한 번에 처리)
  /// 본인 글에 댓글(authorId == currentUserId)인 경우 알림 미생성.
  /// 알림 경로: users/{authorId}/notifications
  Future<String> createComment(CommentModel comment) async {
    try {
      final commentData = comment.toJson();
      if (commentData['authorId'] == null || (commentData['authorId'] as String).isEmpty) {
        commentData['authorId'] = comment.userId;
      }

      final commentRef = _firestore.collection(_collectionPath).doc();
      final postRef = _firestore.collection('posts').doc(comment.postId);

      final commentId = await _firestore.runTransaction<String>((transaction) async {
        // 1. 게시글 조회 → 작성자(authorId) 확인
        final postSnap = await transaction.get(postRef);
        if (!postSnap.exists) throw Exception('Post not found');
        final authorId = postSnap.data()?['userId'] as String?;
        if (authorId == null) throw Exception('Post author not found');

        // 2. 댓글 문서 생성
        transaction.set(commentRef, commentData);

        // 3. 게시글 댓글 수 증가
        transaction.update(postRef, {'comments': FieldValue.increment(1)});

        // 4. 최상위 댓글: 게시글 작성자에게 알림
        if (comment.parentCommentId == null && authorId != comment.userId) {
          final postData = postSnap.data()!;
          final postContent = postData['content'] as String? ?? '';
          final postPreview = postContent.length > 40
              ? '${postContent.replaceAll('\n', ' ').trim().substring(0, 40)}...'
              : postContent.replaceAll('\n', ' ').trim();
          final contentPreview = comment.content.length > 50
              ? '${comment.content.substring(0, 50)}...'
              : comment.content;
          final notifRef = _firestore
              .collection('users')
              .doc(authorId)
              .collection('notifications')
              .doc();
          final bodyText = postPreview.isEmpty
              ? '${comment.authorName}님이 댓글을 달았습니다'
              : '게시글 \'$postPreview\'에 ${comment.authorName}님이 댓글을 달았습니다';
          transaction.set(notifRef, {
            'type': 'COMMENT',
            'senderId': comment.userId,
            'postId': comment.postId,
            'content': contentPreview,
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
            'title': '새 댓글',
            'body': bodyText,
          });
        }

        // 5. 답글: 부모 댓글 작성자에게 알림
        if (comment.parentCommentId != null) {
          final parentRef = _firestore.collection(_collectionPath).doc(comment.parentCommentId);
          final parentSnap = await transaction.get(parentRef);
          if (parentSnap.exists) {
            final parentUserId = parentSnap.data()?['userId'] as String?;
            if (parentUserId != null && parentUserId != comment.userId) {
              final notifRef = _firestore
                  .collection('users')
                  .doc(parentUserId)
                  .collection('notifications')
                  .doc();
              transaction.set(notifRef, {
                'type': 'COMMENT',
                'senderId': comment.userId,
                'postId': comment.postId,
                'content': comment.content.length > 50 ? '${comment.content.substring(0, 50)}...' : comment.content,
                'isRead': false,
                'createdAt': FieldValue.serverTimestamp(),
                'title': '새 답글',
                'body': '${comment.authorName}님이 답글을 달았습니다',
              });
            }
          }
        }

        return commentRef.id;
      });

      return commentId;
    } catch (e) {
      print('Error creating comment: $e');
      rethrow;
    }
  }

  /// Update a comment's content (only content; imageUrl etc. unchanged)
  Future<void> updateComment(String commentId, String newContent) async {
    if (commentId.trim().isEmpty) {
      throw Exception('댓글 ID가 없어 수정할 수 없습니다.');
    }
    try {
      final docRef = _firestore.collection(_collectionPath).doc(commentId);
      final doc = await docRef.get();
      if (!doc.exists) {
        throw Exception('해당 댓글을 찾을 수 없습니다.');
      }
      await docRef.update({
        'content': newContent,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating comment: $e');
      rethrow;
    }
  }

  /// Delete a comment
  /// If the comment has replies, it will be soft-deleted (isDeleted = true)
  /// Otherwise, it will be hard-deleted
  /// Comment count: Decrement for deleted comments (top-level or reply)
  Future<void> deleteComment(String commentId, String postId) async {
    try {
      // Get the comment to check if it's a top-level comment or reply
      final commentDoc = await _firestore.collection(_collectionPath).doc(commentId).get();
      if (!commentDoc.exists) {
        throw Exception('Comment not found');
      }
      
      final commentData = commentDoc.data()!;
      final parentCommentId = commentData['parentCommentId'];
      final isTopLevel = parentCommentId == null;
      
      // Check if comment has replies
      final repliesSnapshot = await _firestore
          .collection(_collectionPath)
          .where('parentCommentId', isEqualTo: commentId)
          .get();
      
      if (repliesSnapshot.docs.isNotEmpty && isTopLevel) {
        // Soft delete: Top-level comment with replies - mark as deleted but keep the comment and replies
        await _firestore.collection(_collectionPath).doc(commentId).update({
          'isDeleted': true,
          'content': '[삭제된 댓글입니다]',
          'imageUrl': null, // Remove image when deleted
        });
        
        // Decrement count only for the deleted top-level comment (replies remain counted)
        await _firestore.collection('posts').doc(postId).update({
          'comments': FieldValue.increment(-1),
        });
      } else {
        // Hard delete: No replies or it's a reply - delete completely
        await _firestore.collection(_collectionPath).doc(commentId).delete();
        
        // Decrement count (for both top-level comments and replies)
        await _firestore.collection('posts').doc(postId).update({
          'comments': FieldValue.increment(-1),
        });
      }
    } catch (e) {
      print('Error deleting comment: $e');
      rethrow;
    }
  }

  /// 닉네임 변경 시 해당 유저의 모든 댓글에 authorName 반영 (userId / authorId 둘 다 검사)
  Future<void> updateAuthorNameForUser(String userId, String newAuthorName) async {
    try {
      final byAuthorId = await _firestore
          .collection(_collectionPath)
          .where('authorId', isEqualTo: userId)
          .get();
      final byUserId = await _firestore
          .collection(_collectionPath)
          .where('userId', isEqualTo: userId)
          .get();
      final docIds = <String>{};
      for (final doc in byAuthorId.docs) {
        docIds.add(doc.id);
      }
      for (final doc in byUserId.docs) {
        docIds.add(doc.id);
      }
      if (docIds.isEmpty) return;
      final batch = _firestore.batch();
      for (final id in docIds) {
        batch.update(_firestore.collection(_collectionPath).doc(id), {'authorName': newAuthorName});
      }
      await batch.commit();
    } catch (e) {
      print('Error updating authorName for comments: $e');
      rethrow;
    }
  }

  /// Delete all comments for a post (used when deleting a post)
  Future<void> deleteAllCommentsForPost(String postId) async {
    try {
      final commentsSnapshot = await _firestore
          .collection(_collectionPath)
          .where('postId', isEqualTo: postId)
          .get();

      final batch = _firestore.batch();
      for (var doc in commentsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      print('Deleted ${commentsSnapshot.docs.length} comments for post $postId');
    } catch (e) {
      print('Error deleting comments for post: $e');
      rethrow;
    }
  }

  /// Toggle like on a comment
  Future<void> toggleLike(String commentId, String userId, bool isLiked) async {
    try {
      if (isLiked) {
        // Unlike
        await _firestore.collection(_collectionPath).doc(commentId).update({
          'likes': FieldValue.increment(-1),
          'likedBy': FieldValue.arrayRemove([userId]),
        });
      } else {
        // Like
        await _firestore.collection(_collectionPath).doc(commentId).update({
          'likes': FieldValue.increment(1),
          'likedBy': FieldValue.arrayUnion([userId]),
        });
      }
    } catch (e) {
      print('Error toggling comment like: $e');
      rethrow;
    }
  }

  /// Get all comments by a user
  /// Checks both authorId and userId fields for backward compatibility
  /// Note: If you get an index error, click the link in the console to create the required index
  /// The index should be on: collection 'comments', fields: ['authorId', 'createdAt']
  Future<List<CommentModel>> getUserComments(String userId) async {
    try {
      // Try to get comments by authorId first (new comments)
      final authorIdQuery = _firestore
          .collection(_collectionPath)
          .where('authorId', isEqualTo: userId);
      
      // Also get comments by userId (old comments without authorId)
      final userIdQuery = _firestore
          .collection(_collectionPath)
          .where('userId', isEqualTo: userId);
      
      // Execute both queries
      final authorIdSnapshot = await authorIdQuery.get();
      final userIdSnapshot = await userIdQuery.get();
      
      // Combine results and remove duplicates
      final allDocs = <String, DocumentSnapshot>{};
      
      // Add authorId results
      for (var doc in authorIdSnapshot.docs) {
        allDocs[doc.id] = doc;
      }
      
      // Add userId results (only if not already in authorId results)
      for (var doc in userIdSnapshot.docs) {
        if (!allDocs.containsKey(doc.id)) {
          allDocs[doc.id] = doc;
        }
      }
      
      // Convert to CommentModel list and sort by createdAt
      final comments = allDocs.values
          .map((doc) => CommentModel.fromFirestore(doc))
          .toList();
      
      comments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      return comments;
    } catch (e) {
      print('Error getting user comments: $e');
      // If index error occurs, try fallback query without orderBy
      try {
        final fallbackQuery = await _firestore
            .collection(_collectionPath)
            .where('userId', isEqualTo: userId)
            .get();
        
        final comments = fallbackQuery.docs
            .map((doc) => CommentModel.fromFirestore(doc))
            .toList();
        
        comments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return comments;
      } catch (fallbackError) {
        print('Error in fallback query: $fallbackError');
        return [];
      }
    }
  }

  /// Stream all comments by a user (for real-time updates)
  /// Checks both authorId and userId fields for backward compatibility
  Stream<List<CommentModel>> streamUserComments(String userId) {
    // Stream comments by authorId (new comments)
    final authorIdStream = _firestore
        .collection(_collectionPath)
        .where('authorId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => CommentModel.fromFirestore(doc)).toList());
    
    // Stream comments by userId (old comments without authorId)
    final userIdStream = _firestore
        .collection(_collectionPath)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => CommentModel.fromFirestore(doc)).toList());
    
    // Combine both streams and remove duplicates using Rx.combineLatest2
    return Rx.combineLatest2<List<CommentModel>, List<CommentModel>, List<CommentModel>>(
      authorIdStream,
      userIdStream,
      (authorIdComments, userIdComments) {
        // Combine and remove duplicates by comment ID
        final allComments = <String, CommentModel>{};
        
        for (var comment in authorIdComments) {
          allComments[comment.id] = comment;
        }
        
        for (var comment in userIdComments) {
          if (!allComments.containsKey(comment.id)) {
            allComments[comment.id] = comment;
          }
        }
        
        // Sort by createdAt descending
        final sortedComments = allComments.values.toList();
        sortedComments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        
        return sortedComments;
      },
    ).handleError((error) {
      print('Error streaming user comments: $error');
      return <CommentModel>[];
    });
  }
}
