import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../repositories/post_repository.dart';
import '../repositories/community_repository.dart';
import '../repositories/user_repository.dart';
import '../services/notification_history_service.dart';
import 'post_detail_screen.dart';
import 'community_post_detail_screen.dart';
import 'user_profile_screen.dart';

class NotificationHistoryScreen extends StatelessWidget {
  const NotificationHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final historyService = NotificationHistoryService();
    final postRepository = PostRepository();
    final communityRepository = CommunityRepository();
    final userRepository = UserRepository();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('알림 내역', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey[800],
        elevation: 0,
      ),
      body: ListenableBuilder(
        listenable: historyService,
        builder: (context, _) {
          final items = historyService.items;
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '아직 받은 알림이 없어요',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              final canGoToPost = item.canNavigateToPost;
              final canGoToProfile = item.canNavigateToProfile;
              return InkWell(
                onTap: canGoToProfile
                    ? () async {
                        final senderId = item.senderId!;
                        final userInfo =
                            await userRepository.getUserInfo(senderId);
                        if (!context.mounted) return;
                        final displayName = userInfo?['displayName'] as String? ??
                            '알 수 없음';
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserProfileScreen(
                              userId: senderId,
                              userName: displayName,
                              userImageUrl:
                                  userInfo?['profileImageUrl'] as String?,
                            ),
                          ),
                        );
                      }
                    : canGoToPost
                        ? () async {
                            final postId = item.postId!;
                            if (item.isCommunityType) {
                              final communityPost =
                                  await communityRepository.getPostById(postId);
                              if (!context.mounted) return;
                              if (communityPost != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        CommunityPostDetailScreen(
                                            post: communityPost),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('해당 게시글을 찾을 수 없습니다')),
                                );
                              }
                            } else {
                              final post =
                                  await postRepository.getPostById(postId);
                              if (!context.mounted) return;
                              if (post != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        PostDetailScreen(post: post),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('해당 게시글을 찾을 수 없습니다')),
                                );
                              }
                            }
                          }
                        : () {},
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
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
                      if (item.title.isNotEmpty)
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                        ),
                      if (item.title.isNotEmpty && item.body.isNotEmpty) const SizedBox(height: 6),
                      if (item.body.isNotEmpty)
                        Text(
                          item.body,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            DateFormat('M/d HH:mm').format(item.createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                          if (canGoToProfile) ...[
                            const Spacer(),
                            Text(
                              '프로필 보기',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 10,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ] else if (canGoToPost) ...[
                            const Spacer(),
                            Text(
                              '게시글로 이동',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 10,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
