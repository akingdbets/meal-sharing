import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../repositories/post_repository.dart';
import '../services/auth_service.dart';
import '../services/like_sync_service.dart';
import '../screens/user_profile_screen.dart';

class PostCard extends StatefulWidget {
  final String description;
  final String author;
  final String timestamp;
  final List<String> tags;
  final int? savedMoney;
  final int likes;
  final int comments;
  final String? imageUrl;
  final String postId;
  final bool isLiked;
  final String userId; // Added userId for profile navigation
  final List<String> postIngredients; // 게시물의 재료 목록
  final List<String> userIngredients; // 사용자가 가진 재료 목록
  final int? cookingTime; // 조리시간(분)
  final int? servings; // 인분

  const PostCard({
    super.key,
    required this.description,
    required this.author,
    required this.timestamp,
    required this.tags,
    this.savedMoney,
    required this.likes,
    required this.comments,
    this.imageUrl,
    required this.postId,
    this.isLiked = false,
    required this.userId, // Added userId parameter
    this.postIngredients = const [], // 게시물의 재료 목록 (기본값: 빈 리스트)
    this.userIngredients = const [], // 사용자가 가진 재료 목록 (기본값: 빈 리스트)
    this.cookingTime,
    this.servings,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  final PostRepository _postRepository = PostRepository();
  final AuthService _authService = AuthService();
  final LikeSyncService _likeSyncService = LikeSyncService();
  bool _isLiked = false;
  int _likes = 0;
  bool _isScrapped = false;
  String? _authorProfileImageUrl; // To store author's profile image
  StreamSubscription<LikeUpdateEvent>? _likeSubscription; // 좋아요 동기화 구독

  @override
  void initState() {
    super.initState();
    _isLiked = widget.isLiked;
    _likes = widget.likes;
    _checkScrapStatus();
    _fetchAuthorProfileImage();
    
    // 좋아요 상태 변경 이벤트 구독
    _likeSubscription = _likeSyncService.stream.listen((event) {
      // 이 게시물의 좋아요 상태가 변경되었는지 확인
      if (event.postId == widget.postId) {
        if (mounted) {
          setState(() {
            _isLiked = event.isLiked;
            _likes = event.likeCount;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    // 구독 취소하여 메모리 누수 방지
    _likeSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 부모로부터 받은 데이터(likes)가 변했다면 내 상태(_likes)도 업데이트
    if (widget.likes != oldWidget.likes) {
      setState(() {
        _likes = widget.likes;
      });
    }
    // 부모로부터 받은 좋아요 여부가 변했다면 업데이트
    if (widget.isLiked != oldWidget.isLiked) {
      setState(() {
        _isLiked = widget.isLiked;
      });
    }
    // postId가 변경된 경우 (다른 게시물로 교체된 경우) 스크랩 상태와 프로필 이미지 다시 로드
    if (widget.postId != oldWidget.postId) {
      _checkScrapStatus();
      _fetchAuthorProfileImage();
    }
  }

  Future<void> _fetchAuthorProfileImage() async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        if (mounted) {
          setState(() {
            _authorProfileImageUrl = userData?['profileImageUrl'] as String?;
          });
        }
      }
    } catch (e) {
      print('Error fetching author profile image: $e');
    }
  }

  Future<void> _checkScrapStatus() async {
    final user = _authService.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (userDoc.exists && mounted) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final scrappedPostIds = (userData['scrappedPostIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        setState(() {
          _isScrapped = scrappedPostIds.contains(widget.postId);
        });
      }
    } catch (e) {
      print('Error checking scrap status: $e');
    }
  }

  Future<void> _toggleScrap() async {
    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다')),
      );
      return;
    }

    setState(() {
      _isScrapped = !_isScrapped;
    });

    try {
      await _postRepository.toggleScrap(widget.postId, user.uid);
    } catch (e) {
      setState(() {
        _isScrapped = !_isScrapped;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('스크랩 처리 중 오류가 발생했습니다: $e')),
      );
    }
  }

  Future<void> _toggleLike() async {
    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다')),
      );
      return;
    }

    // 1. 내 UI 즉시 변경 (Optimistic Update)
    final newStatus = !_isLiked;
    final newCount = newStatus ? _likes + 1 : _likes - 1;

    setState(() {
      _isLiked = newStatus;
      _likes = newCount;
    });

    // 2. 📡 전역 방송 송출 (다른 화면들도 다 바꿔라!)
    _likeSyncService.updateLike(widget.postId, newStatus, newCount);

    // 3. 서버 요청 (실패 시 롤백)
    try {
      await _postRepository.toggleLike(widget.postId, user.uid, !newStatus);
    } catch (e) {
      // 에러 발생 시 원래 상태로 롤백
      setState(() {
        _isLiked = !newStatus;
        _likes = newStatus ? _likes - 1 : _likes + 1;
      });
      // 롤백 상태도 방송
      _likeSyncService.updateLike(widget.postId, !newStatus, _likes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류가 발생했습니다: $e')),
      );
    }
  }

  /// 쿠팡 검색 URL 실행
  Future<void> _launchCoupangSearch(String ingredient) async {
    try {
      // 쿠팡 검색 URL 패턴
      final encodedIngredient = Uri.encodeComponent(ingredient);
      final url = Uri.parse('https://www.coupang.com/np/search?component=&q=$encodedIngredient');
      
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('쿠팡 검색을 열 수 없습니다: $ingredient')),
          );
        }
        print('Could not launch $url');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류가 발생했습니다: $e')),
        );
      }
      print('Error launching URL: $e');
    }
  }

  /// 부족한 재료 계산 및 위젯 생성
  Widget _buildMissingIngredientsWidget() {
    // 빈 리스트 체크
    if (widget.userIngredients.isEmpty || widget.postIngredients.isEmpty) {
      return const SizedBox.shrink();
    }

    // 재료 이름을 소문자로 정규화하여 비교
    final userIngredientMap = <String, String>{}; // normalized -> original
    for (final ing in widget.userIngredients) {
      final normalized = ing.toLowerCase().trim();
      if (normalized.isNotEmpty) {
        userIngredientMap[normalized] = ing;
      }
    }

    final postIngredientMap = <String, String>{}; // normalized -> original
    for (final ing in widget.postIngredients) {
      final normalized = ing.toLowerCase().trim();
      if (normalized.isNotEmpty) {
        postIngredientMap[normalized] = ing;
      }
    }

    // 부족한 재료 계산 (게시물 재료 중 사용자가 가지지 않은 것)
    final missingIngredients = <String>[];
    for (final entry in postIngredientMap.entries) {
      final postIngNormalized = entry.key;
      final postIngOriginal = entry.value;
      
      bool hasIngredient = false;
      
      // 정확히 일치하는지 확인
      if (userIngredientMap.containsKey(postIngNormalized)) {
        hasIngredient = true;
      } else {
        // 부분 일치 확인 (예: "대파"와 "파")
        for (final userIngNormalized in userIngredientMap.keys) {
          if (postIngNormalized.contains(userIngNormalized) || 
              userIngNormalized.contains(postIngNormalized)) {
            hasIngredient = true;
            break;
          }
        }
      }
      
      if (!hasIngredient) {
        missingIngredients.add(postIngOriginal);
      }
    }

    // 부족한 재료가 없는 경우
    if (missingIngredients.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              size: 16,
              color: Colors.green[700],
            ),
            const SizedBox(width: 6),
            Text(
              '바로 요리 가능! 🎉',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green[700],
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    // 부족한 재료가 있는 경우
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: Colors.redAccent[700],
              ),
              const SizedBox(width: 6),
              Text(
                '부족한 재료:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.redAccent[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: missingIngredients.map((ingredient) {
              return InkWell(
                onTap: () => _launchCoupangSearch(ingredient),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.redAccent[300] ?? Colors.redAccent,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ingredient,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.redAccent[700],
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.shopping_cart_outlined,
                        size: 12,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final numberFormat = NumberFormat('#,###');

    return Card(
      elevation: 1,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Colors.grey.shade100,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image with Savings Badge (4:3 aspect ratio)
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: widget.imageUrl != null
                      ? ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                          child: Image.network(
                            widget.imageUrl!,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Center(
                          child: Icon(
                            Icons.restaurant,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                        ),
                ),
              ),
              // Savings Badge
              if (widget.savedMoney != null && widget.savedMoney! > 0)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '💰',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${numberFormat.format(widget.savedMoney ?? 0)}원 절약!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Scrap Button
              Positioned(
                top: 12,
                left: 12,
                child: InkWell(
                  onTap: _toggleScrap,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isScrapped ? Icons.bookmark : Icons.bookmark_border,
                      color: _isScrapped ? Colors.amber : Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author & Time
                Row(
                  children: [
                    // Avatar (Clickable)
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserProfileScreen(
                              userId: widget.userId,
                              userName: widget.author,
                              userImageUrl: _authorProfileImageUrl,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.secondary,
                            ],
                          ),
                          shape: BoxShape.circle,
                          image: _authorProfileImageUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(_authorProfileImageUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _authorProfileImageUrl == null
                            ? Center(
                                child: Text(
                                  widget.author.isNotEmpty ? widget.author[0] : '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Author name and timestamp
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Author name (Clickable)
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserProfileScreen(
                                    userId: widget.userId,
                                    userName: widget.author,
                                    userImageUrl: null,
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                widget.author,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.grey[900],
                                ),
                              ),
                            ),
                          ),
                          Text(
                            widget.timestamp,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Description (2줄 초과 시 ... 표시)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        widget.description,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                // 조리시간 · 인분 (있을 때만)
                if ((widget.cookingTime != null && widget.cookingTime! > 0) ||
                    (widget.servings != null && widget.servings! > 1)) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (widget.cookingTime != null && widget.cookingTime! > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange.shade200,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 14,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${widget.cookingTime}분',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (widget.servings != null && widget.servings! > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.teal.shade200,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.restaurant,
                                size: 14,
                                color: Colors.teal.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${widget.servings}인분',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.teal.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // Tags
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: widget.tags.take(3).map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                // 부족한 재료 표시 (userIngredients가 제공된 경우만)
                if (widget.userIngredients.isNotEmpty && widget.postIngredients.isNotEmpty) ...[
                  _buildMissingIngredientsWidget(),
                  const SizedBox(height: 12),
                ],
                // Engagement (Likes & Comments)
                Row(
                  children: [
                    InkWell(
                      onTap: _toggleLike,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isLiked ? Icons.favorite : Icons.favorite_border,
                              size: 20,
                              color: _isLiked ? Colors.red : Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              numberFormat.format(_likes),
                              style: TextStyle(
                                fontSize: 14,
                                color: _isLiked ? Colors.red : Colors.grey[600],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.comment_outlined,
                      size: 20,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      numberFormat.format(widget.comments),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
