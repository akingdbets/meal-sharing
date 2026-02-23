import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/community_post_model.dart';
import '../repositories/community_repository.dart';
import '../repositories/user_repository.dart';
import '../services/auth_service.dart';
import '../services/safety_service.dart';
import '../services/hidden_content_service.dart';
import 'create_community_post_screen.dart';
import 'community_post_detail_screen.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final CommunityRepository _repository = CommunityRepository();
  final AuthService _auth = AuthService();
  final UserRepository _userRepo = UserRepository();
  final SafetyService _safetyService = SafetyService();
  final HiddenContentService _hiddenContentService = HiddenContentService();

  List<String> _getBlockedIds(dynamic userData) {
    final list = userData?['blockedUserIds'] as List<dynamic>?;
    return list?.map((e) => e.toString()).toList() ?? [];
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

  void _showReportBlockBottomSheet(BuildContext context, CommunityPostModel post) {
    final user = _auth.currentUser;
    if (user == null) return;
    final targetUid = post.userId;
    final contentId = post.id;

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
                    type: 'post',
                    reason: reasonText,
                  );
                  await _hiddenContentService.addHiddenPost(contentId);
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
                    setState(() {});
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const PageStorageKey('community_list'),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더: 간소한 타이틀 (냉장고 파먹기와 동일 위치·스타일)
              Row(
                children: [
                  Text(
                    '자유게시판 🤝',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: Colors.grey[900],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 전체 글 리스트 (단일 리스트) — 차단한 사용자 게시글 제외
              StreamBuilder<DocumentSnapshot>(
                stream: _auth.currentUser != null ? _userRepo.streamUser(_auth.currentUser!.uid) : null,
                builder: (context, userSnap) {
                  final blockedIds = userSnap.hasData ? _getBlockedIds(userSnap.data?.data()) : <String>[];
                  return StreamBuilder<List<CommunityPostModel>>(
                    stream: _repository.streamAllPosts(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              '오류: ${snapshot.error}',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                        );
                      }

                      final postsRaw = snapshot.data ?? [];
                      final postsBlocked = blockedIds.isEmpty
                          ? postsRaw
                          : postsRaw.where((p) => !blockedIds.contains(p.userId)).toList();

                      return ListenableBuilder(
                        listenable: _hiddenContentService,
                        builder: (context, _) {
                          final posts = postsBlocked
                              .where((p) => !_hiddenContentService.isPostHidden(p.id))
                              .toList();

                  if (posts.isEmpty) {
                    // Empty State: 화면 정중앙에 배치
                    return SizedBox(
                      width: double.infinity,
                      child: Container(
                        constraints: BoxConstraints(
                          minHeight: MediaQuery.of(context).size.height * 0.4,
                        ),
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '아직 글이 없어요',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '첫 번째 글을 등록해보세요!',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: posts.map((post) {
                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CommunityPostDetailScreen(post: post),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: _CommunityPostCard(
                          post: post,
                          theme: theme,
                          currentUserId: _auth.currentUser?.uid ?? '',
                          repo: _repository,
                          onMorePressed: _auth.currentUser?.uid != null &&
                                  _auth.currentUser?.uid != post.userId
                              ? (ctx) => _showReportBlockBottomSheet(ctx, post)
                              : null,
                        ),
                      );
                    }).toList(),
                  );
                },
              );
            },
            );
          },
        ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'community_fab',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CreateCommunityPostScreen(),
            ),
          );
        },
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _CommunityPostCard extends StatelessWidget {
  final CommunityPostModel post;
  final ThemeData theme;
  final String currentUserId;
  final CommunityRepository repo;
  final void Function(BuildContext context)? onMorePressed;

  const _CommunityPostCard({
    required this.post,
    required this.theme,
    required this.currentUserId,
    required this.repo,
    this.onMorePressed,
  });

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return DateFormat('M월 d일').format(dateTime);
    } else if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.5),
                backgroundImage: post.authorProfileImage != null
                    ? NetworkImage(post.authorProfileImage!)
                    : null,
                child: post.authorProfileImage == null
                    ? Text(
                        post.authorName.isNotEmpty
                            ? post.authorName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.authorName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTimestamp(post.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              if (onMorePressed != null)
                IconButton(
                  icon: Icon(Icons.more_vert, size: 20, color: Colors.grey[600]),
                  onPressed: () => onMorePressed!(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Content (에브리타임 스타일 굵기)
          Text(
            post.content,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: Colors.grey[800],
              height: 1.4,
              fontSize: 15,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),

          // Image thumbnail (if any)
          if (post.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                post.imageUrls.first,
                width: double.infinity,
                height: 160,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 80,
                    color: Colors.grey[200],
                    child: Icon(Icons.broken_image, color: Colors.grey[400]),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Footer (공감 + 댓글)
          Row(
            children: [
              _CommunityPostLikeButton(
                postId: post.id,
                initialLikes: post.likes,
                initialLikedBy: post.likedBy,
                userId: currentUserId,
                repo: repo,
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.comment_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                '댓글 ${post.commentCount}개',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 공감 버튼 (부분만 리빌드해 스크롤 튐 방지)
class _CommunityPostLikeButton extends StatefulWidget {
  final String postId;
  final int initialLikes;
  final List<String> initialLikedBy;
  final String userId;
  final CommunityRepository repo;

  const _CommunityPostLikeButton({
    required this.postId,
    required this.initialLikes,
    required this.initialLikedBy,
    required this.userId,
    required this.repo,
  });

  @override
  State<_CommunityPostLikeButton> createState() => _CommunityPostLikeButtonState();
}

class _CommunityPostLikeButtonState extends State<_CommunityPostLikeButton> {
  late int _likes;
  late bool _isLiked;

  @override
  void initState() {
    super.initState();
    _likes = widget.initialLikes;
    _isLiked = widget.userId.isNotEmpty && widget.initialLikedBy.contains(widget.userId);
  }

  @override
  void didUpdateWidget(_CommunityPostLikeButton oldWidget) {
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
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }
}
