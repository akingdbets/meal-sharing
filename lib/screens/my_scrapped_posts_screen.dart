import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/post_repository.dart';
import '../services/auth_service.dart';
import '../widgets/post_card.dart';
import 'post_detail_screen.dart';
import '../models/post_model.dart';
import 'package:intl/intl.dart';

class MyScrappedPostsScreen extends StatefulWidget {
  const MyScrappedPostsScreen({super.key});

  @override
  State<MyScrappedPostsScreen> createState() => _MyScrappedPostsScreenState();
}

class _MyScrappedPostsScreenState extends State<MyScrappedPostsScreen> {
  final PostRepository _postRepository = PostRepository();
  final AuthService _authService = AuthService();
  List<PostModel> _scrappedPosts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadScrappedPosts();
  }

  Future<void> _loadScrappedPosts() async {
    final user = _authService.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Listen to user document changes to get real-time scrap updates
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final scrappedPostIds = (userData['scrappedPostIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];

        if (scrappedPostIds.isNotEmpty) {
          final posts = await _postRepository.getScrappedPosts(scrappedPostIds);
          if (mounted) {
            setState(() {
              _scrappedPosts = posts;
              _isLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _scrappedPosts = [];
              _isLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _scrappedPosts = [];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading scrapped posts: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('스크랩한 게시물을 불러오는 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

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
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text(
          '내 스크랩',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _scrappedPosts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bookmark_border,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '아직 스크랩한 게시물이 없습니다',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '마음에 드는 게시물을 스크랩해보세요',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadScrappedPosts,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _scrappedPosts.length,
                    itemBuilder: (context, index) {
                      final post = _scrappedPosts[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PostDetailScreen(post: post),
                              ),
                            ).then((_) {
                              // Reload when returning from detail screen
                              _loadScrappedPosts();
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: PostCard(
                            postId: post.id,
                            description: post.content,
                            author: post.authorName,
                            timestamp: _formatTimestamp(post.createdAt),
                            tags: post.tags,
                            savedMoney: post.savedAmount > 0 ? post.savedAmount : null,
                            likes: post.likes,
                            comments: post.comments,
                            imageUrl: post.mainImageUrl,
                            isLiked: post.likedBy.contains(_authService.currentUser?.uid ?? ''),
                            userId: post.userId,
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
