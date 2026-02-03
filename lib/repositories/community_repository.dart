import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/community_post_model.dart';
import '../models/community_comment_model.dart';

/// Repository for community posts (separate from recipe posts).
/// Firestore collection: community_posts.
/// Comments: community_posts/{postId}/comments (subcollection).
class CommunityRepository {
  static final CommunityRepository _instance = CommunityRepository._internal();
  factory CommunityRepository() => _instance;
  CommunityRepository._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionPath = 'community_posts';

  /// Create a new community post
  Future<String> createPost(CommunityPostModel post) async {
    try {
      final docRef = await _firestore.collection(_collectionPath).add(post.toJson());
      return docRef.id;
    } catch (e) {
      print('Error creating community post: $e');
      rethrow;
    }
  }

  /// Get posts (latest first) with optional pagination
  Future<List<CommunityPostModel>> getPosts({
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection(_collectionPath)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final querySnapshot = await query.get();
      final posts = querySnapshot.docs
          .map((doc) => CommunityPostModel.fromFirestore(doc))
          .toList();
      return posts;
    } catch (e) {
      print('Error fetching community posts: $e');
      return [];
    }
  }

  /// Stream community posts written by a user (for "내 게시글")
  Stream<List<CommunityPostModel>> streamPostsByUserId(String userId) {
    return _firestore
        .collection(_collectionPath)
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CommunityPostModel.fromFirestore(doc))
            .toList())
        .handleError((e) {
      print('Error streaming user community posts: $e');
      return <CommunityPostModel>[];
    });
  }

  /// Stream all community posts (latest first, single list)
  Stream<List<CommunityPostModel>> streamAllPosts() {
    return _firestore
        .collection(_collectionPath)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          final posts = snapshot.docs
              .map((doc) => CommunityPostModel.fromFirestore(doc))
              .toList();
          return posts;
        })
        .handleError((error) {
          print('Error streaming community posts: $error');
          return <CommunityPostModel>[];
        });
  }

  /// 닉네임 변경 시 해당 유저의 모든 커뮤니티 게시물에 authorName 반영
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
      print('Error updating authorName for community posts: $e');
      rethrow;
    }
  }

  /// 닉네임 변경 시 해당 유저의 모든 커뮤니티 댓글에 authorName 반영 (컬렉션 그룹 인덱스 없이 게시물별 서브컬렉션 조회)
  Future<void> updateCommentAuthorNameForUser(String userId, String newAuthorName) async {
    try {
      final postsSnapshot = await _firestore.collection(_collectionPath).get();
      final toUpdate = <DocumentReference<Map<String, dynamic>>>[];
      for (final postDoc in postsSnapshot.docs) {
        final commentsSnapshot = await _commentsRef(postDoc.id)
            .where('userId', isEqualTo: userId)
            .get();
        for (final commentDoc in commentsSnapshot.docs) {
          toUpdate.add(commentDoc.reference);
        }
      }
      if (toUpdate.isEmpty) return;
      const batchLimit = 500;
      for (var i = 0; i < toUpdate.length; i += batchLimit) {
        final batch = _firestore.batch();
        final chunk = toUpdate.skip(i).take(batchLimit);
        for (final ref in chunk) {
          batch.update(ref, {'authorName': newAuthorName});
        }
        await batch.commit();
      }
    } catch (e) {
      print('Error updating authorName for community comments: $e');
      rethrow;
    }
  }

  /// Delete a community post and all its comments (so they disappear from "내 댓글" too).
  Future<void> deletePost(String id) async {
    try {
      final commentsRef = _commentsRef(id);
      final commentsSnap = await commentsRef.get();
      final batch = _firestore.batch();
      for (final doc in commentsSnap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      await _firestore.collection(_collectionPath).doc(id).delete();
    } catch (e) {
      print('Error deleting community post: $e');
      rethrow;
    }
  }

  /// Get a single post by ID
  Future<CommunityPostModel?> getPostById(String id) async {
    try {
      final doc = await _firestore.collection(_collectionPath).doc(id).get();
      if (doc.exists) {
        return CommunityPostModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('Error fetching community post by id: $e');
      return null;
    }
  }

  /// Toggle 공감(like) on a community post. List and detail stay in sync via Firestore stream.
  Future<void> togglePostLike(String postId, String userId, bool isLiked) async {
    try {
      final ref = _firestore.collection(_collectionPath).doc(postId);
      if (isLiked) {
        await ref.update({
          'likes': FieldValue.increment(-1),
          'likedBy': FieldValue.arrayRemove([userId]),
        });
      } else {
        await ref.update({
          'likes': FieldValue.increment(1),
          'likedBy': FieldValue.arrayUnion([userId]),
        });
      }
    } catch (e) {
      print('Error toggling community post like: $e');
      rethrow;
    }
  }

  // ---------- Comments subcollection: community_posts/{postId}/comments ----------

  CollectionReference<Map<String, dynamic>> _commentsRef(String postId) {
    return _firestore.collection(_collectionPath).doc(postId).collection('comments');
  }

  /// Stream top-level comments (no parentCommentId). Sort by createdAt in memory to avoid composite index.
  Stream<List<CommunityCommentModel>> streamComments(String postId) {
    return _commentsRef(postId)
        .where('parentCommentId', isNull: true)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => CommunityCommentModel.fromFirestore(doc))
              .toList();
          list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return list;
        })
        .handleError((e) {
          print('Error streaming community comments: $e');
          return <CommunityCommentModel>[];
        });
  }

  /// Stream replies for a comment. Sort by createdAt in memory.
  Stream<List<CommunityCommentModel>> streamReplies(String postId, String parentCommentId) {
    return _commentsRef(postId)
        .where('parentCommentId', isEqualTo: parentCommentId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => CommunityCommentModel.fromFirestore(doc))
              .toList();
          list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return list;
        })
        .handleError((e) {
          print('Error streaming community replies: $e');
          return <CommunityCommentModel>[];
        });
  }

  /// Create comment (top-level or reply). Increments post commentCount.
  Future<String> createComment(String postId, CommunityCommentModel comment) async {
    final ref = _commentsRef(postId);
    final data = comment.toJson();
    data.remove('id');
    final docRef = await ref.add(data);
    await _firestore.collection(_collectionPath).doc(postId).update({
      'commentCount': FieldValue.increment(1),
    });
    return docRef.id;
  }

  /// Delete comment: if has replies → soft delete (isDeleted=true); else hard delete. Decrements post commentCount.
  Future<void> deleteComment(String postId, String commentId) async {
    final ref = _commentsRef(postId);
    final commentDoc = await ref.doc(commentId).get();
    if (!commentDoc.exists) throw Exception('Comment not found');
    final parentCommentId = commentDoc.data()?['parentCommentId'];
    final isTopLevel = parentCommentId == null;

    final repliesSnap = await ref.where('parentCommentId', isEqualTo: commentId).get();

    if (repliesSnap.docs.isNotEmpty && isTopLevel) {
      await ref.doc(commentId).update({'isDeleted': true, 'content': '[삭제된 댓글입니다]'});
    } else {
      await ref.doc(commentId).delete();
    }
    await _firestore.collection(_collectionPath).doc(postId).update({
      'commentCount': FieldValue.increment(-1),
    });
  }

  /// Toggle like on a comment
  Future<void> toggleCommentLike(String postId, String commentId, String userId, bool isLiked) async {
    final ref = _commentsRef(postId).doc(commentId);
    if (isLiked) {
      await ref.update({
        'likes': FieldValue.increment(-1),
        'likedBy': FieldValue.arrayRemove([userId]),
      });
    } else {
      await ref.update({
        'likes': FieldValue.increment(1),
        'likedBy': FieldValue.arrayUnion([userId]),
      });
    }
  }

  /// Get all community comments by a user (for "My Comments").
  /// Uses collectionGroup('comments') and filters by path containing 'community_posts'.
  Future<List<CommunityCommentWithPostId>> getUserCommunityComments(String userId) async {
    try {
      final snapshot = await _firestore
          .collectionGroup('comments')
          .where('userId', isEqualTo: userId)
          .get();
      final list = <CommunityCommentWithPostId>[];
      for (final doc in snapshot.docs) {
        final path = doc.reference.path;
        if (!path.contains('community_posts')) continue;
        final segments = path.split('/');
        if (segments.length >= 4 && segments[0] == 'community_posts' && segments[2] == 'comments') {
          final postId = segments[1];
          final comment = CommunityCommentModel.fromFirestore(doc);
          list.add(CommunityCommentWithPostId(postId: postId, comment: comment));
        }
      }
      list.sort((a, b) => b.comment.createdAt.compareTo(a.comment.createdAt));
      return list;
    } catch (e) {
      print('Error getting user community comments: $e');
      return [];
    }
  }

  /// Stream all community comments by a user (for "My Comments").
  Stream<List<CommunityCommentWithPostId>> streamUserCommunityComments(String userId) {
    return _firestore
        .collectionGroup('comments')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final list = <CommunityCommentWithPostId>[];
          for (final doc in snapshot.docs) {
            final path = doc.reference.path;
            if (!path.contains('community_posts')) continue;
            final segments = path.split('/');
            if (segments.length >= 4 && segments[0] == 'community_posts' && segments[2] == 'comments') {
              final postId = segments[1];
              final comment = CommunityCommentModel.fromFirestore(doc);
              list.add(CommunityCommentWithPostId(postId: postId, comment: comment));
            }
          }
          list.sort((a, b) => b.comment.createdAt.compareTo(a.comment.createdAt));
          return list;
        })
        .handleError((e) {
          print('Error streaming user community comments: $e');
          return <CommunityCommentWithPostId>[];
        });
  }
}

/// Wrapper for a community comment with its post ID (for "My Comments" list).
class CommunityCommentWithPostId {
  final String postId;
  final CommunityCommentModel comment;
  CommunityCommentWithPostId({required this.postId, required this.comment});
}
