import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/post_card.dart';
import '../models/post_model.dart';
import '../repositories/post_repository.dart';
import '../repositories/user_repository.dart';
import '../services/auth_service.dart';
import '../services/like_sync_service.dart';
import '../services/hidden_content_service.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';
import 'search_screen.dart';
import 'notification_history_screen.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.initialTabIndex});

  /// 온보딩 직후 등에서 전달: 0 = 현실 집밥, 1 = 자취 밥상 (스트림 도착 전 첫 화면용)
  final int? initialTabIndex;

  /// 온보딩에서 선택한 userType(현실 집밥=housewife, 자취 밥상=single)에 따라 초기 탭 인덱스 반환
  static int _initialTabIndexForUserType(String? userType) {
    return (userType == 'single') ? 1 : 0; // single → 자취 밥상(survival), housewife → 현실 집밥
  }

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final currentUser = authService.currentUser;
    final userRepo = UserRepository();

    return StreamBuilder(
      stream: currentUser != null ? userRepo.streamUser(currentUser.uid) : null,
      builder: (context, snapshot) {
        final userType = snapshot.data?.data()?['userType'] as String?;
        final indexFromStream = _initialTabIndexForUserType(userType);
        final initialIndex = initialTabIndex ?? indexFromStream;
        return DefaultTabController(
          length: 2,
          initialIndex: initialIndex,
          child: _HomeContent(
            initialIndex: initialIndex,
          ),
        );
      },
    );
  }
}

/// StatefulWidget that holds selectedTag for tag filtering.
/// Tag toggle: click selected tag -> deselect (null), click other -> select.
class _HomeContent extends StatefulWidget {
  final int initialIndex;

  const _HomeContent({required this.initialIndex});

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> {
  String? selectedTag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          children: [
            // Custom AppBar with Search
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '오늘의 식탁',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 25,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificationHistoryScreen(),
                        ),
                      );
                    },
                    icon: Icon(Icons.notifications_outlined, color: Colors.grey[700]),
                    tooltip: '알림 내역',
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SearchScreen(),
                        ),
                      );
                    },
                    icon: Icon(Icons.search, color: Colors.grey[700]),
                    tooltip: '검색',
                  ),
                ],
              ),
            ),
            // TabBar
            Container(
              color: Colors.white,
              child: TabBar(
                tabs: const [
                  Tab(text: '현실 집밥'),
                  Tab(text: '자취 밥상'),
                ],
                labelColor: Colors.black,
                unselectedLabelColor: Colors.grey[600],
                labelStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                ),
                indicatorColor: Theme.of(context).colorScheme.primary,
                indicatorWeight: 3.0,
                indicatorSize: TabBarIndicatorSize.tab,
              ),
            ),
            // Tag List with selection state
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: _TagList(
                selectedTag: selectedTag,
                onTagSelected: (tag) {
                  setState(() {
                    selectedTag = (selectedTag == tag) ? null : tag;
                  });
                },
              ),
            ),
            // TabBarView Content
            Expanded(
              child: TabBarView(
                children: [
                  _PostListView(category: 'housewife', selectedTag: selectedTag),
                  _PostListView(category: 'survival', selectedTag: selectedTag),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Builder(
        builder: (context) {
          return FloatingActionButton.extended(
            heroTag: 'home_fab',
            onPressed: () {
              final tabController = DefaultTabController.of(context);
              final isSurvival = tabController.index == 1;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CreatePostScreen(
                    isSurvival: isSurvival,
                  ),
                ),
              );
            },
            backgroundColor: Theme.of(context).colorScheme.primary,
            icon: const Icon(Icons.edit_note, color: Colors.white),
            label: const Text(
              '글쓰기',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TagList extends StatefulWidget {
  final String? selectedTag;
  final ValueChanged<String> onTagSelected;

  const _TagList({
    required this.selectedTag,
    required this.onTagSelected,
  });

  @override
  State<_TagList> createState() => _TagListState();
}

class _TagListState extends State<_TagList> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _selectedTagKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _TagList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 선택된 태그가 바뀌었을 때 해당 태그를 가로 중앙으로 스크롤
    if (oldWidget.selectedTag != widget.selectedTag && widget.selectedTag != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = _selectedTagKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        try {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.5,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        } catch (_) {
          // RenderObject may be detached (e.g. user navigated away)
        }
      });
    }
  }

  void _handleTagSelection(BuildContext context, String tag) {
    widget.onTagSelected(tag);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final postRepository = PostRepository();

    return FutureBuilder<List<String>>(
      future: postRepository.getRecentTags(limit: 50),
      builder: (context, snapshot) {
        // Loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 40,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        // Error state
        if (snapshot.hasError) {
          return const SizedBox(height: 40);
        }

        // Empty state or no tags
        final tags = snapshot.data ?? [];
        if (tags.isEmpty) {
          return const SizedBox(height: 40);
        }

        // Display tags — ScrollController를 유지해 선택 시 스크롤 위치가 초기화되지 않음
        return SizedBox(
          height: 40,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            itemCount: tags.length,
            itemBuilder: (context, index) {
              final tag = tags[index];
              final isSelected = widget.selectedTag == tag;
              // GlobalKey는 선택된 태그 하나에만 부여 (중복 방지: 동일 태그가 여러 개여도 첫 번째만)
              final useScrollKey = isSelected && tags.indexOf(tag) == index;
              return Padding(
                key: useScrollKey ? _selectedTagKey : ValueKey('tag_$index'),
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(tag),
                  selected: isSelected,
                  onSelected: (selected) {
                    _handleTagSelection(context, tag);
                  },
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                  backgroundColor: Colors.white,
                  selectedColor: theme.colorScheme.primaryContainer,
                  side: BorderSide(
                    color: Colors.grey[300]!,
                    width: 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _PostListView extends StatefulWidget {
  final String category;
  final String? selectedTag;

  const _PostListView({
    required this.category,
    this.selectedTag,
  });

  @override
  State<_PostListView> createState() => _PostListViewState();
}

class _PostListViewState extends State<_PostListView> with AutomaticKeepAliveClientMixin {
  final PostRepository _repository = PostRepository();
  final AuthService _authService = AuthService();
  final LikeSyncService _likeSyncService = LikeSyncService();
  late Stream<List<PostModel>> _postsStream;
  
  // 좋아요 상태 캐시 (postId -> isLiked, likeCount)
  final Map<String, bool> _likeStatusCache = {};
  final Map<String, int> _likeCountCache = {};
  
  // LikeSyncService 구독
  StreamSubscription<LikeUpdateEvent>? _likeSubscription;

  @override
  bool get wantKeepAlive => true;

  void _updatePostsStream() {
    final isSurvival = widget.category == 'survival';
    _postsStream = _repository.streamPostsByMode(
      isSurvival: isSurvival,
      selectedTag: widget.selectedTag,
    );
  }

  @override
  void initState() {
    super.initState();
    _updatePostsStream();

    // 좋아요 상태 변경 이벤트 구독
    _likeSubscription = _likeSyncService.stream.listen((event) {
      if (mounted) {
        setState(() {
          // 캐시 업데이트
          _likeStatusCache[event.postId] = event.isLiked;
          _likeCountCache[event.postId] = event.likeCount;
        });
      }
    });
  }
  
  @override
  void didUpdateWidget(covariant _PostListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTag != widget.selectedTag) {
      _updatePostsStream();
    }
  }

  @override
  void dispose() {
    // 구독 취소하여 메모리 누수 방지
    _likeSubscription?.cancel();
    super.dispose();
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

  List<String> _getBlockedIds(dynamic userData) {
    final list = userData?['blockedUserIds'] as List<dynamic>?;
    return list?.map((e) => e.toString()).toList() ?? [];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin을 위해 필수
    final user = _authService.currentUser;

    return StreamBuilder<DocumentSnapshot>(
      stream: user != null ? UserRepository().streamUser(user.uid) : null,
      builder: (context, userSnap) {
        final blockedIds = userSnap.hasData ? _getBlockedIds(userSnap.data?.data()) : <String>[];

        return StreamBuilder<List<PostModel>>(
          stream: _postsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.grey[300],
                ),
                const SizedBox(height: 16),
                Text(
                  '데이터를 불러오는 중 오류가 발생했습니다',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }

            final postsRaw = snapshot.data ?? [];
            // [Safety] Filter out posts from blocked users (client-side)
            final postsBlocked = blockedIds.isEmpty
                ? postsRaw
                : postsRaw.where((p) => !blockedIds.contains(p.userId)).toList();

            return ListenableBuilder(
              listenable: HiddenContentService(),
              builder: (context, _) {
                final hiddenService = HiddenContentService();
                final posts = postsBlocked
                    .where((p) => !hiddenService.isPostHidden(p.id))
                    .toList();

                if (posts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.restaurant_menu,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '아직 게시글이 없어요',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  key: PageStorageKey('home_feed_scroll_${widget.category}'),
                  padding: const EdgeInsets.all(16),
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PostDetailScreen(post: post),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: PostCard(
                  key: ValueKey(post.id),
                  description: post.content,
                  author: post.authorName,
                  timestamp: _formatTimestamp(post.createdAt),
                  tags: post.tags,
                  savedMoney: post.savedAmount > 0 ? post.savedAmount : null,
                  // 좋아요 수: 캐시에 있으면 캐시 값 사용, 없으면 원본 데이터
                  likes: _likeCountCache[post.id] ?? post.likes,
                  comments: post.comments,
                  postId: post.id,
                  // 좋아요 상태: 캐시에 있으면 캐시 값 사용, 없으면 원본 데이터에서 계산
                  isLiked: _likeStatusCache[post.id] ?? 
                      post.likedBy.contains(_authService.currentUser?.uid ?? ''),
                  imageUrl: post.mainImageUrl,
                  userId: post.userId,
                  cookingTime: post.cookingTime,
                  servings: post.servings,
                ),
              ),
            );
                  },
                );
              },
            );
        },
        );
      },
    );
  }
}
