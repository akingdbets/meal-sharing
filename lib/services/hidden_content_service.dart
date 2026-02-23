import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 사용자가 신고한 게시물/댓글 ID를 로컬에 저장해 해당 사용자 화면에서만 숨김 (Optimistic UI).
class HiddenContentService extends ChangeNotifier {
  static final HiddenContentService _instance = HiddenContentService._internal();
  factory HiddenContentService() => _instance;
  HiddenContentService._internal() {
    _load();
  }

  static const String _keyHiddenPosts = 'hidden_post_ids';
  static const String _keyHiddenComments = 'hidden_comment_ids';

  final Set<String> _hiddenPostIds = {};
  final Set<String> _hiddenCommentIds = {};

  Set<String> get hiddenPostIds => Set.unmodifiable(_hiddenPostIds);
  Set<String> get hiddenCommentIds => Set.unmodifiable(_hiddenCommentIds);

  bool isPostHidden(String postId) => _hiddenPostIds.contains(postId);
  bool isCommentHidden(String commentId) => _hiddenCommentIds.contains(commentId);

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final posts = prefs.getStringList(_keyHiddenPosts);
      final comments = prefs.getStringList(_keyHiddenComments);
      if (posts != null) _hiddenPostIds.addAll(posts);
      if (comments != null) _hiddenCommentIds.addAll(comments);
    } catch (e) {
      debugPrint('HiddenContentService load error: $e');
    }
  }

  Future<void> addHiddenPost(String postId) async {
    if (_hiddenPostIds.contains(postId)) return;
    _hiddenPostIds.add(postId);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyHiddenPosts, _hiddenPostIds.toList());
    } catch (e) {
      debugPrint('HiddenContentService save posts error: $e');
    }
  }

  Future<void> addHiddenComment(String commentId) async {
    if (_hiddenCommentIds.contains(commentId)) return;
    _hiddenCommentIds.add(commentId);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyHiddenComments, _hiddenCommentIds.toList());
    } catch (e) {
      debugPrint('HiddenContentService save comments error: $e');
    }
  }
}
