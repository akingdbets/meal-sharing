import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/community_post_model.dart';
import '../models/community_comment_model.dart';
import '../repositories/community_repository.dart';
import '../repositories/user_repository.dart';
import '../services/auth_service.dart';
import '../services/safety_service.dart';
import '../services/hidden_content_service.dart';
import '../utils/profanity_filter.dart';

class CommunityPostDetailScreen extends StatefulWidget {
  final CommunityPostModel post;

  const CommunityPostDetailScreen({super.key, required this.post});

  @override
  State<CommunityPostDetailScreen> createState() => _CommunityPostDetailScreenState();
}

class _CommunityPostDetailScreenState extends State<CommunityPostDetailScreen> {
  final CommunityRepository _repo = CommunityRepository();
  final UserRepository _userRepo = UserRepository();
  final AuthService _auth = AuthService();
  final SafetyService _safetyService = SafetyService();
  final HiddenContentService _hiddenContentService = HiddenContentService();

  List<String> _getBlockedIds(dynamic userData) {
    final list = userData?['blockedUserIds'] as List<dynamic>?;
    return list?.map((e) => e.toString()).toList() ?? [];
  }
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _replyingToCommentId;
  String? _replyingToAuthorName;

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final d = now.difference(dateTime);
    if (d.inDays > 7) return DateFormat('M월 d일').format(dateTime);
    if (d.inDays > 0) return '${d.inDays}일 전';
    if (d.inHours > 0) return '${d.inHours}시간 전';
    if (d.inMinutes > 0) return '${d.inMinutes}분 전';
    return '방금 전';
  }

  Future<void> _submitComment({String? parentCommentId}) async {
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('로그인이 필요합니다')));
      return;
    }
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    final badWord = ProfanityFilter().containsProfanity(content);
    if (badWord != null) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('부적절한 내용'),
            content: const Text(
              '입력한 내용에 부적절한 표현이 포함되어 있습니다.\n수정 후 다시 시도해 주세요.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
      return;
    }

    String authorName = user.displayName ?? '익명';
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        authorName = userData?['displayName'] as String? ?? authorName;
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error fetching user displayName: $e');
    }

    final comment = CommunityCommentModel(
      id: '',
      userId: user.uid,
      authorName: authorName,
      content: content,
      parentCommentId: parentCommentId,
      createdAt: DateTime.now(),
    );
    try {
      await _repo.createComment(widget.post.id, comment);
      _commentController.clear();
      setState(() {
        _replyingToCommentId = null;
        _replyingToAuthorName = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('댓글 작성 실패: $e')));
      }
    }
  }

  Future<void> _deletePost() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('게시글 삭제'),
        content: const Text('이 게시글을 삭제할까요? 삭제된 글은 복구할 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deletePost(widget.post.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('게시글이 삭제되었습니다')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }

  Future<String?> _showReportReasonDialog(BuildContext context) async {
    const reasons = [
      ('spam', '스팸'),
      ('inappropriate', '부적절한 콘텐츠'),
      ('hate', '혐오 발언'),
      ('privacy', '개인정보 유출'),
      ('other', '기타'),
    ];
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '신고 사유를 선택해주세요',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...reasons.map((e) => ListTile(
                title: Text(e.$2),
                onTap: () => Navigator.pop(ctx, e.$1),
              )),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReportBlockBottomSheet({
    required BuildContext context,
    required String targetUid,
    required String contentId,
    required String type,
    VoidCallback? onBlocked,
  }) {
    final user = _auth.currentUser;
    if (user == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('신고하기'),
              onTap: () async {
                Navigator.pop(ctx);
                final reasonKey = await _showReportReasonDialog(context);
                if (reasonKey == null || !mounted) return;
                final reasonLabels = {
                  'spam': '스팸',
                  'inappropriate': '부적절한 콘텐츠',
                  'hate': '혐오 발언',
                  'privacy': '개인정보 유출',
                  'other': '기타',
                };
                final reasonText = reasonLabels[reasonKey] ?? reasonKey;
                try {
                  await _safetyService.report(
                    reporterUid: user.uid,
                    targetUid: targetUid,
                    contentId: contentId,
                    type: type,
                    reason: reasonText,
                  );
                  if (type == 'post') {
                    await _hiddenContentService.addHiddenPost(contentId);
                    if (mounted) Navigator.pop(context);
                  } else {
                    await _hiddenContentService.addHiddenComment(contentId);
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('신고가 접수되었습니다. 해당 콘텐츠가 숨겨졌습니다.')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('신고 처리 중 오류: $e')),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('사용자 차단'),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await _safetyService.blockUser(
                    currentUid: user.uid,
                    targetUid: targetUid,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('사용자를 차단했습니다')),
                    );
                    onBlocked?.call();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('차단 처리 중 오류: $e')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteComment(CommunityCommentModel comment) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('댓글 삭제'),
        content: const Text('이 댓글을 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteComment(widget.post.id, comment.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제되었습니다')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('community_posts').doc(widget.post.id).snapshots(),
          builder: (context, snap) {
            String authorName = widget.post.authorName;
            if (snap.hasData && snap.data != null && (snap.data as DocumentSnapshot).exists) {
              final data = (snap.data as DocumentSnapshot).data() as Map<String, dynamic>?;
              if (data != null && data['authorName'] != null) authorName = data['authorName'] as String;
            }
            return Text(
              authorName,
              style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
        actions: [
          if (_auth.currentUser?.uid == widget.post.userId)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.black87),
              onSelected: (value) {
                if (value == 'delete') _deletePost();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 20, color: Colors.red), SizedBox(width: 8), Text('삭제', style: TextStyle(color: Colors.red))])),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.black87),
              onPressed: () => _showReportBlockBottomSheet(
                context: context,
                targetUid: widget.post.userId,
                contentId: widget.post.id,
                type: 'post',
                onBlocked: () => Navigator.pop(context),
              ),
              tooltip: '더보기',
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _auth.currentUser != null ? _userRepo.streamUser(_auth.currentUser!.uid) : null,
        builder: (context, userSnap) {
          final blockedIds = userSnap.hasData ? _getBlockedIds(userSnap.data?.data()) : <String>[];
          if (blockedIds.contains(widget.post.userId)) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.block, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      '차단한 사용자의 게시글입니다',
                      style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('돌아가기'),
                    ),
                  ],
                ),
              ),
            );
          }
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('community_posts').doc(widget.post.id).snapshots(),
            builder: (context, postSnap) {
              final post = (postSnap.hasData && postSnap.data!.exists)
                  ? CommunityPostModel.fromFirestore(postSnap.data!)
                  : widget.post;
              return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const PageStorageKey('community_post_detail_scroll'),
                  controller: _scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.5),
                            backgroundImage: post.authorProfileImage != null ? NetworkImage(post.authorProfileImage!) : null,
                            child: post.authorProfileImage == null
                                ? Text(
                                    post.authorName.isNotEmpty ? post.authorName[0].toUpperCase() : '?',
                                    style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w500),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(post.authorName, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
                                Text(_formatTimestamp(post.createdAt), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        post.content,
                        style: TextStyle(fontSize: 16, height: 1.5, color: Colors.black, fontWeight: FontWeight.w500),
                      ),
                      if (post.imageUrls.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            post.imageUrls.first,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              height: 120,
                              color: Colors.grey[200],
                              child: Icon(Icons.broken_image, color: Colors.grey[400]),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // 공감 (리스트와 연동: 같은 문서 스트림으로 실시간 반영)
                      Row(
                        children: [
                          _DetailPostLikeButton(
                            postId: post.id,
                            initialLikes: post.likes,
                            initialLikedBy: post.likedBy,
                            userId: _auth.currentUser?.uid ?? '',
                            repo: _repo,
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.comment_outlined, size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            '댓글 ${post.commentCount}개',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: theme.colorScheme.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 16),
                      Text('댓글 ${post.commentCount}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.grey[900])),
                      const SizedBox(height: 16),
                      StreamBuilder<List<CommunityCommentModel>>(
                        stream: _repo.streamComments(widget.post.id),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                            return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                          }
                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(24),
                              child: Center(child: Text('댓글을 불러올 수 없습니다.', style: TextStyle(color: Colors.grey[600]))),
                            );
                          }
                          final commentsRaw = snapshot.data ?? [];
                          final commentsBlocked = blockedIds.isEmpty
                              ? commentsRaw
                              : commentsRaw.where((c) => !blockedIds.contains(c.userId)).toList();
                          return ListenableBuilder(
                            listenable: _hiddenContentService,
                            builder: (context, _) {
                              final comments = commentsBlocked
                                  .where((c) => !_hiddenContentService.isCommentHidden(c.id))
                                  .toList();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: comments.map((comment) => _CommentBlock(
                                  postId: widget.post.id,
                                  comment: comment,
                                  currentUserId: _auth.currentUser?.uid,
                                  formatTimestamp: _formatTimestamp,
                                  onReply: () {
                                    setState(() {
                                      _replyingToCommentId = comment.id;
                                      _replyingToAuthorName = comment.authorName;
                                    });
                                  },
                                  onDelete: () => _deleteComment(comment),
                                  repo: _repo,
                                  onReportComment: (targetUid, commentId) => _showReportBlockBottomSheet(
                                    context: context,
                                    targetUid: targetUid,
                                    contentId: commentId,
                                    type: 'comment',
                                    onBlocked: () {},
                                  ),
                                  hiddenContentService: _hiddenContentService,
                                )).toList(),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              if (_replyingToAuthorName != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                  child: Row(
                    children: [
                      Text('${_replyingToAuthorName}님에게 답글 작성 중', style: TextStyle(fontSize: 13, color: theme.colorScheme.primary)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() { _replyingToCommentId = null; _replyingToAuthorName = null; }),
                        child: const Text('취소'),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, -2))]),
                child: SafeArea(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          decoration: InputDecoration(
                            hintText: _replyingToCommentId != null ? '답글 입력...' : '댓글 입력...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.grey[300]!)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submitComment(parentCommentId: _replyingToCommentId),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: () => _submitComment(parentCommentId: _replyingToCommentId),
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
        },
      ),
    );
  }
}

/// One top-level comment + its replies. Like button is isolated to avoid scroll jump.
class _CommentBlock extends StatelessWidget {
  final String postId;
  final CommunityCommentModel comment;
  final String? currentUserId;
  final String Function(DateTime) formatTimestamp;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final CommunityRepository repo;
  final void Function(String targetUid, String commentId)? onReportComment;
  final HiddenContentService hiddenContentService;

  const _CommentBlock({
    required this.postId,
    required this.comment,
    required this.currentUserId,
    required this.formatTimestamp,
    required this.onReply,
    required this.onDelete,
    required this.repo,
    this.onReportComment,
    required this.hiddenContentService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOwner = currentUserId == comment.userId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.5),
                child: Text(
                  comment.authorName.isNotEmpty ? comment.authorName[0].toUpperCase() : '?',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.primary, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(comment.authorName, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                        const SizedBox(width: 8),
                        Text(formatTimestamp(comment.createdAt), style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                        const Spacer(),
                        if (!isOwner && onReportComment != null)
                          IconButton(
                            icon: Icon(Icons.more_horiz, size: 18, color: Colors.grey[600]),
                            onPressed: () => onReportComment!(comment.userId, comment.id),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            tooltip: '신고하기',
                          ),
                        if (isOwner) ...[
                          IconButton(
                            icon: Icon(Icons.delete_outline, size: 18, color: Colors.grey[600]),
                            onPressed: onDelete,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    comment.isDeleted
                        ? Text('삭제된 댓글입니다.', style: TextStyle(fontSize: 14, color: Colors.grey[500], fontStyle: FontStyle.italic))
                        : Text(comment.content, style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4)),
                    const SizedBox(height: 6),
                    if (!comment.isDeleted)
                      Row(
                        children: [
                          _CommentLikeButton(
                            postId: postId,
                            commentId: comment.id,
                            initialLikes: comment.likes,
                            initialLikedBy: comment.likedBy,
                            userId: currentUserId ?? '',
                            repo: repo,
                          ),
                          const SizedBox(width: 16),
                          TextButton(
                            onPressed: onReply,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: Colors.grey[600],
                            ),
                            child: const Text('답글', style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Replies
          StreamBuilder<List<CommunityCommentModel>>(
            stream: repo.streamReplies(postId, comment.id),
            builder: (context, replySnap) {
              if (!replySnap.hasData || replySnap.data!.isEmpty) return const SizedBox.shrink();
              final repliesRaw = replySnap.data!;
              final replies = repliesRaw
                  .where((r) => !hiddenContentService.isCommentHidden(r.id))
                  .toList();
              if (replies.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(left: 42, top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: replies.map((reply) => _ReplyRow(
                    postId: postId,
                    reply: reply,
                    currentUserId: currentUserId,
                    formatTimestamp: formatTimestamp,
                    onDelete: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('답글 삭제'),
                          content: const Text('이 답글을 삭제할까요?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                      if (ok == true) {
                        try {
                          await repo.deleteComment(postId, reply.id);
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제되었습니다')));
                        } catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
                        }
                      }
                    },
                    repo: repo,
                    onReportComment: onReportComment,
                  )).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReplyRow extends StatelessWidget {
  final String postId;
  final CommunityCommentModel reply;
  final String? currentUserId;
  final String Function(DateTime) formatTimestamp;
  final VoidCallback onDelete;
  final CommunityRepository repo;
  final void Function(String targetUid, String commentId)? onReportComment;

  const _ReplyRow({
    required this.postId,
    required this.reply,
    required this.currentUserId,
    required this.formatTimestamp,
    required this.onDelete,
    required this.repo,
    this.onReportComment,
  });

  @override
  Widget build(BuildContext context) {
    final isOwner = currentUserId == reply.userId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.subdirectory_arrow_right, size: 16, color: Colors.grey[400]),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(reply.authorName, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                    const SizedBox(width: 6),
                    Text(formatTimestamp(reply.createdAt), style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    const Spacer(),
                    if (!isOwner && onReportComment != null)
                      IconButton(
                        icon: Icon(Icons.more_horiz, size: 16, color: Colors.grey[600]),
                        onPressed: () => onReportComment!(reply.userId, reply.id),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        tooltip: '신고하기',
                      ),
                    if (isOwner) ...[
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 16, color: Colors.grey[600]),
                        onPressed: onDelete,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                reply.isDeleted
                    ? Text('삭제된 댓글입니다.', style: TextStyle(fontSize: 13, color: Colors.grey[500], fontStyle: FontStyle.italic))
                    : Text(reply.content, style: TextStyle(fontSize: 13, color: Colors.grey[800], height: 1.4)),
                if (!reply.isDeleted)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _CommentLikeButton(
                      postId: postId,
                      commentId: reply.id,
                      initialLikes: reply.likes,
                      initialLikedBy: reply.likedBy,
                      userId: currentUserId ?? '',
                      repo: repo,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Isolated like button: only this widget rebuilds on tap, so scroll does not jump.
class _CommentLikeButton extends StatefulWidget {
  final String postId;
  final String commentId;
  final int initialLikes;
  final List<String> initialLikedBy;
  final String userId;
  final CommunityRepository repo;

  const _CommentLikeButton({
    required this.postId,
    required this.commentId,
    required this.initialLikes,
    required this.initialLikedBy,
    required this.userId,
    required this.repo,
  });

  @override
  State<_CommentLikeButton> createState() => _CommentLikeButtonState();
}

class _CommentLikeButtonState extends State<_CommentLikeButton> {
  late int _likes;
  late bool _isLiked;

  @override
  void initState() {
    super.initState();
    _likes = widget.initialLikes;
    _isLiked = widget.userId.isNotEmpty && widget.initialLikedBy.contains(widget.userId);
  }

  @override
  void didUpdateWidget(_CommentLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialLikes != widget.initialLikes || oldWidget.initialLikedBy != widget.initialLikedBy) {
      _likes = widget.initialLikes;
      _isLiked = widget.userId.isNotEmpty && widget.initialLikedBy.contains(widget.userId);
    }
  }

  Future<void> _toggle() async {
    if (widget.userId.isEmpty) return;
    setState(() {
      _isLiked = !_isLiked;
      _likes += _isLiked ? 1 : -1;
    });
    try {
      await widget.repo.toggleCommentLike(widget.postId, widget.commentId, widget.userId, !_isLiked);
    } catch (e) {
      setState(() {
        _isLiked = !_isLiked;
        _likes += _isLiked ? 1 : -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isLiked ? Icons.favorite : Icons.favorite_border,
              size: 18,
              color: _isLiked ? Colors.red : Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text('$_likes', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

/// 상세 페이지 공감 버튼 (리스트와 동일 문서 스트림으로 연동)
class _DetailPostLikeButton extends StatefulWidget {
  final String postId;
  final int initialLikes;
  final List<String> initialLikedBy;
  final String userId;
  final CommunityRepository repo;

  const _DetailPostLikeButton({
    required this.postId,
    required this.initialLikes,
    required this.initialLikedBy,
    required this.userId,
    required this.repo,
  });

  @override
  State<_DetailPostLikeButton> createState() => _DetailPostLikeButtonState();
}

class _DetailPostLikeButtonState extends State<_DetailPostLikeButton> {
  late int _likes;
  late bool _isLiked;

  @override
  void initState() {
    super.initState();
    _likes = widget.initialLikes;
    _isLiked = widget.userId.isNotEmpty && widget.initialLikedBy.contains(widget.userId);
  }

  @override
  void didUpdateWidget(_DetailPostLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialLikes != widget.initialLikes ||
        oldWidget.initialLikedBy != widget.initialLikedBy) {
      _likes = widget.initialLikes;
      _isLiked = widget.userId.isNotEmpty && widget.initialLikedBy.contains(widget.userId);
    }
  }

  Future<void> _toggle() async {
    if (widget.userId.isEmpty) return;
    setState(() {
      _isLiked = !_isLiked;
      _likes += _isLiked ? 1 : -1;
    });
    try {
      await widget.repo.togglePostLike(widget.postId, widget.userId, !_isLiked);
    } catch (e) {
      setState(() {
        _isLiked = !_isLiked;
        _likes += _isLiked ? 1 : -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isLiked ? Icons.favorite : Icons.favorite_border,
              size: 18,
              color: _isLiked ? Colors.red : Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              '$_likes',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }
}
