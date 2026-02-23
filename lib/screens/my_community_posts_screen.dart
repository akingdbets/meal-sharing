import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import '../models/community_post_model.dart';
import '../repositories/community_repository.dart';
import '../models/post_model.dart';
import '../repositories/post_repository.dart';
import '../services/auth_service.dart';
import 'community_post_detail_screen.dart';
import 'post_detail_screen.dart';

/// 마이페이지 > 내 게시글 (내가 쓴 커뮤니티 및 레시피 게시글 목록)
class MyCommunityPostsScreen extends StatefulWidget {
  const MyCommunityPostsScreen({super.key});

  @override
  State<MyCommunityPostsScreen> createState() => _MyCommunityPostsScreenState();
}

class _MyCommunityPostsScreenState extends State<MyCommunityPostsScreen> {
  final _auth = AuthService();
  final _communityRepo = CommunityRepository();
  final _postRepo = PostRepository();
  Future<List<PostModel>>? _recipePostsFuture;

  @override
  void initState() {
    super.initState();
    _refreshRecipePosts();
  }

  void _refreshRecipePosts() {
    final user = _auth.currentUser;
    if (user != null) {
      setState(() {
        _recipePostsFuture = _postRepo.getPostsByUserId(user.uid);
      });
    }
  }

  Future<void> _deleteCommunityPost(CommunityPostModel post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('게시글 삭제'),
        content: const Text('정말로 이 게시글을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _communityRepo.deletePost(post.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('게시글이 삭제되었습니다'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 중 오류가 발생했습니다: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteRecipePost(PostModel post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('게시글 삭제'),
        content: const Text('정말로 이 게시글을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _postRepo.deletePost(post.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('게시글이 삭제되었습니다'), backgroundColor: Colors.green),
        );
        _refreshRecipePosts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 중 오류가 발생했습니다: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _auth.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        appBar: AppBar(
          title: const Text(
            '내 게시글',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black87,
        ),
        body: const Center(
          child: Text('로그인이 필요합니다.', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        appBar: AppBar(
          title: const Text(
            '내 게시글',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black87,
          bottom: const TabBar(
            labelColor: Colors.black87,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.black87,
            tabs: [
              Tab(text: '자유게시판'),
              Tab(text: '레시피'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Community Posts
            StreamBuilder<List<CommunityPostModel>>(
              stream: _communityRepo.streamPostsByUserId(user.uid).startWith(<CommunityPostModel>[]),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      '오류: ${snapshot.error}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  );
                }
                final posts = snapshot.data ?? [];
                if (posts.isEmpty && snapshot.connectionState != ConnectionState.waiting) {
                  return _buildEmptyState(theme, '자유게시판 글이 없습니다', '자유게시판에서 첫 글을 올려보세요!');
                }
                if (posts.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index];
                    return _CommunityPostTile(
                      post: post,
                      theme: theme,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CommunityPostDetailScreen(post: post),
                          ),
                        );
                      },
                      onDelete: () => _deleteCommunityPost(post),
                    );
                  },
                );
              },
            ),
            // Tab 2: Recipe / Survival Posts
            FutureBuilder<List<PostModel>>(
              future: _recipePostsFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      '오류: ${snapshot.error}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final posts = snapshot.data ?? [];
                if (posts.isEmpty) {
                  return _buildEmptyState(theme, '레시피 글이 없습니다', '나만의 레시피를 공유해보세요!');
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index];
                    return _RecipePostTile(
                      post: post,
                      theme: theme,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PostDetailScreen(post: post),
                          ),
                        ).then((_) {
                           // Re-fetch posts when coming back from detail screen in case it was deleted or edited
                           _refreshRecipePosts();
                        });
                      },
                      onDelete: () => _deleteRecipePost(post),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.edit_note, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityPostTile extends StatelessWidget {
  final CommunityPostModel post;
  final ThemeData theme;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _CommunityPostTile({
    required this.post,
    required this.theme,
    required this.onTap,
    required this.onDelete,
  });

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inDays > 7) return DateFormat('M/d').format(dateTime);
    if (diff.inDays > 0) return '${diff.inDays}일 전';
    if (diff.inHours > 0) return '${diff.inHours}시간 전';
    if (diff.inMinutes > 0) return '${diff.inMinutes}분 전';
    return '방금 전';
  }

  @override
  Widget build(BuildContext context) {
    final title = post.title.isNotEmpty ? post.title : null;
    final contentPreview = post.content.length > 80
        ? '${post.content.substring(0, 80)}...'
        : post.content;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[900],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
            ],
            Text(
              contentPreview,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[700],
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.favorite, size: 14, color: Colors.redAccent),
                const SizedBox(width: 4),
                Text(
                  '${post.likes}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(width: 12),
                Icon(Icons.chat_bubble_outline, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  '${post.commentCount}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const Spacer(),
                Text(
                  _formatTimestamp(post.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: '삭제',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipePostTile extends StatelessWidget {
  final PostModel post;
  final ThemeData theme;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _RecipePostTile({
    required this.post,
    required this.theme,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final contentPreview = post.content.length > 80
        ? '${post.content.substring(0, 80)}...'
        : post.content;
    final isSurvival = post.isSurvival;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSurvival ? Colors.orange[50] : theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isSurvival ? '생존템' : '자취 요리',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSurvival ? Colors.orange[800] : theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (post.mainImageUrl != null && post.mainImageUrl!.isNotEmpty) ...[
               ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                     post.mainImageUrl!,
                     width: double.infinity,
                     height: 140,
                     fit: BoxFit.cover,
                     errorBuilder: (_, __, ___) => Container(
                        width: double.infinity,
                        height: 140,
                        color: Colors.grey[200],
                        child: Icon(Icons.broken_image, color: Colors.grey[400]),
                     ),
                  ),
               ),
               const SizedBox(height: 12),
            ],
            Text(
              contentPreview,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[700],
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            if (post.tags.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: post.tags.take(3).map((tag) {
                  return Text(
                    '#$tag',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                }).toList(),
              ),
            if (post.tags.isNotEmpty) const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.favorite, size: 14, color: Colors.redAccent),
                const SizedBox(width: 4),
                Text(
                  '${post.likes}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(width: 12),
                Icon(Icons.chat_bubble_outline, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  '${post.comments}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: '삭제',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
