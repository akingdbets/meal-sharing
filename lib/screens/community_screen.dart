import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/community_post_model.dart';
import '../repositories/community_repository.dart';
import '../services/auth_service.dart';
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
                    '커뮤니티 🤝',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: Colors.grey[900],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 전체 글 리스트 (단일 리스트)
              StreamBuilder<List<CommunityPostModel>>(
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

                  final posts = snapshot.data ?? [];

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
                        ),
                      );
                    }).toList(),
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

  const _CommunityPostCard({
    required this.post,
    required this.theme,
    required this.currentUserId,
    required this.repo,
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
