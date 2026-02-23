import 'package:flutter/material.dart';
import 'dart:async';
import '../widgets/post_card.dart';
import '../services/mock_ai_service.dart';
import '../services/auth_service.dart';
import '../services/like_sync_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/post_repository.dart';
import '../repositories/user_repository.dart';
import '../models/post_model.dart';
import 'post_detail_screen.dart';

class FridgeSearchScreen extends StatefulWidget {
  const FridgeSearchScreen({super.key});

  @override
  State<FridgeSearchScreen> createState() => _FridgeSearchScreenState();
}

class _FridgeSearchScreenState extends State<FridgeSearchScreen> with AutomaticKeepAliveClientMixin {
  final List<String> _selectedIngredients = [];
  final TextEditingController _ingredientSearchController = TextEditingController();
  final MockAIService _aiService = MockAIService();
  final AuthService _authService = AuthService();
  final LikeSyncService _likeSyncService = LikeSyncService();
  final PostRepository _postRepository = PostRepository();
  final UserRepository _userRepository = UserRepository();
  final ScrollController _scrollController = ScrollController();

  List<String> _getBlockedIds(dynamic userData) {
    final list = userData?['blockedUserIds'] as List<dynamic>?;
    return list?.map((e) => e.toString()).toList() ?? [];
  }
  
  // 좋아요 상태 캐시 (postId -> isLiked, likeCount)
  final Map<String, bool> _likeStatusCache = {};
  final Map<String, int> _likeCountCache = {};
  
  // LikeSyncService 구독
  StreamSubscription<LikeUpdateEvent>? _likeSubscription;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 게시물 목록은 StreamBuilder로 실시간 반영 (삭제 시 즉시 갱신)
    _likeSubscription = _likeSyncService.stream.listen((event) {
      if (mounted) {
        setState(() {
          _likeStatusCache[event.postId] = event.isLiked;
          _likeCountCache[event.postId] = event.likeCount;
        });
      }
    });
  }
  
  /// 게시물들의 재료 빈도수를 계산하여 상위 10개 추출
  List<String> _calculateTopIngredients(List<PostModel> posts) {
    final Map<String, int> ingredientCount = {};
    for (final post in posts) {
      for (final ingredient in post.ingredients) {
        final name = ingredient.name.trim();
        if (name.isNotEmpty) {
          ingredientCount[name] = (ingredientCount[name] ?? 0) + 1;
        }
      }
    }
    final sortedIngredients = ingredientCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sortedIngredients.take(10).map((e) => e.key).toList();
  }

  /// 스트림에서 받은 전체 게시물을 선택된 재료로 메모리 필터링·정렬
  List<PostModel> _filterPostsInMemory(List<PostModel> allPosts, List<String> selectedIngredients) {
    if (selectedIngredients.isEmpty) return allPosts;
    final filtered = allPosts.where((post) =>
        _countMatchingIngredients(post.ingredients, selectedIngredients) > 0).toList();
    filtered.sort((a, b) {
      final aMatch = _countMatchingIngredients(a.ingredients, selectedIngredients);
      final bMatch = _countMatchingIngredients(b.ingredients, selectedIngredients);
      final c = bMatch.compareTo(aMatch);
      if (c != 0) return c;
      return b.createdAt.compareTo(a.createdAt);
    });
    return filtered;
  }

  void _filterPostsByIngredients() {
    setState(() {});
  }

  /// 게시물의 재료 중 선택된 재료와 일치하는 개수를 계산
  int _countMatchingIngredients(List<Ingredient> postIngredients, List<String> selectedIngredients) {
    int matchCount = 0;
    
    // 선택된 재료를 소문자로 정규화
    final normalizedSelected = selectedIngredients
        .map((ing) => ing.toLowerCase().trim())
        .toSet();
    
    for (final postIng in postIngredients) {
      final postIngName = postIng.name.toLowerCase().trim();
      
      // 정확히 일치하는지 확인
      if (normalizedSelected.contains(postIngName)) {
        matchCount++;
        continue;
      }
      
      // 부분 일치 확인 (예: "대파"와 "파")
      for (final selectedIng in normalizedSelected) {
        if (postIngName.contains(selectedIng) || selectedIng.contains(postIngName)) {
          matchCount++;
          break;
        }
      }
    }
    
    return matchCount;
  }

  void _addIngredient(String ingredient) {
    if (ingredient.trim().isEmpty) return;
    
    final trimmed = ingredient.trim();
    
    // MockAiService의 재료 목록에서 정확히 일치하는 재료 찾기
    final allIngredients = _aiService.getAllIngredients();
    final normalized = trimmed.toLowerCase();
    final exactMatch = allIngredients.firstWhere(
      (ing) => ing.toLowerCase() == normalized,
      orElse: () => '',
    );
    
    if (exactMatch.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$trimmed"은(는) 등록된 재료가 아닙니다. 기존 재료 목록에서 선택해주세요.'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // 이미 선택된 재료인지 확인
    if (_selectedIngredients.contains(exactMatch)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$exactMatch"은(는) 이미 선택된 재료입니다.'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }
    
    // 스크롤 위치 저장
    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    
    // 재료 추가
    setState(() {
      _selectedIngredients.add(exactMatch);
    });
    
    // 입력창 초기화
    _ingredientSearchController.clear();
    
    // 게시물 필터링
    _filterPostsByIngredients();
    
    // 스크롤 위치 복원 (다음 프레임에서)
    if (scrollOffset > 0 && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scrollController.hasClients) {
          try {
            _scrollController.jumpTo(scrollOffset);
          } catch (_) {}
        }
      });
    }
  }

  void _removeIngredient(String ingredient) {
    // 스크롤 위치 저장
    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    
    setState(() {
      _selectedIngredients.remove(ingredient);
    });
    
    _filterPostsByIngredients();
    
    // 스크롤 위치 복원 (다음 프레임에서)
    if (scrollOffset > 0 && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scrollController.hasClients) {
          try {
            _scrollController.jumpTo(scrollOffset);
          } catch (_) {}
        }
      });
    }
  }

  @override
  void dispose() {
    // 구독 취소하여 메모리 누수 방지
    _likeSubscription?.cancel();
    _ingredientSearchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin을 위한 필수 호출
    final theme = Theme.of(context);

    return StreamBuilder<DocumentSnapshot>(
      stream: _authService.currentUser != null ? _userRepository.streamUser(_authService.currentUser!.uid) : null,
      builder: (context, userSnap) {
        final blockedIds = userSnap.hasData ? _getBlockedIds(userSnap.data?.data()) : <String>[];
        return StreamBuilder<List<PostModel>>(
          stream: _postRepository.streamAllPosts(),
          builder: (context, snapshot) {
            final allPosts = snapshot.data ?? [];
            final postsBlocked = blockedIds.isEmpty
                ? allPosts
                : allPosts.where((p) => !blockedIds.contains(p.userId)).toList();
            final topIngredients = _calculateTopIngredients(postsBlocked);
            final displayPosts = _filterPostsInMemory(postsBlocked, _selectedIngredients);
            final isLoading = snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;

            return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: GestureDetector(
        // 빈 공간 터치 시 키보드 내리기
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
          child: Column(
            children: [
            // 헤더: 크고 깔끔한 텍스트 타이틀
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Text(
                    '냉장고 파먹기 🥬',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: Colors.grey[900],
                    ),
                  ),
                ],
              ),
            ),
            
            // 메인 콘텐츠
            Expanded(
              child: SingleChildScrollView(
                key: const PageStorageKey('fridge_search_scroll'),
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 선택된 재료 칩
                    if (_selectedIngredients.isNotEmpty) ...[
                      // 타이틀과 초기화 버튼
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '선택된 재료',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.grey[800],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              // 스크롤 위치 저장
                              final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                              
                              setState(() {
                                _selectedIngredients.clear();
                              });
                              
                              _filterPostsByIngredients();
                              
                              // 스크롤 위치 복원 (다음 프레임에서)
                              if (scrollOffset > 0 && _scrollController.hasClients) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (!mounted) return;
                                  if (_scrollController.hasClients) {
                                    try {
                                      _scrollController.jumpTo(scrollOffset);
                                    } catch (_) {}
                                  }
                                });
                              }
                            },
                            icon: const Icon(
                              Icons.refresh,
                              size: 16,
                            ),
                            label: const Text(
                              '초기화',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 50,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: _selectedIngredients.map((ingredient) {
                            return Container(
                              margin: const EdgeInsets.only(right: 8),
                              child: Chip(
                                label: Text(
                                  ingredient,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                onDeleted: () => _removeIngredient(ingredient),
                                deleteIcon: const Icon(Icons.close, size: 18),
                                backgroundColor: theme.colorScheme.primaryContainer,
                                labelStyle: TextStyle(
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 검색창 (Autocomplete)
                    Container(
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
                      child: Autocomplete<String>(
                        key: const ValueKey('autocomplete_fridge_ingredient'),
                        // 데이터 소스: MockAiService의 전체 재료 리스트
                        optionsBuilder: (textEditingValue) {
                          final query = textEditingValue.text.toLowerCase().trim();
                          if (query.isEmpty) {
                            return Iterable<String>.empty();
                          }
                          
                          // 이미 선택된 재료는 제외하고 필터링
                          return _aiService.getAllIngredients().where((ingredient) {
                            return ingredient.toLowerCase().contains(query) &&
                                !_selectedIngredients.contains(ingredient);
                          });
                        },
                        // 입력 필드 빌더
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          // Autocomplete의 controller와 state의 controller 동기화
                          if (controller.text != _ingredientSearchController.text) {
                            _ingredientSearchController.text = controller.text;
                          }
                          
                          controller.addListener(() {
                            if (_ingredientSearchController.text != controller.text) {
                              _ingredientSearchController.text = controller.text;
                            }
                          });
                          
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              hintText: '재료를 검색하세요 (예: 양파, 삼겹살)',
                              hintStyle: TextStyle(
                                color: Colors.grey[400],
                                fontWeight: FontWeight.w500,
                              ),
                              prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            // 엔터 키 입력 시에도 재료 추가
                            onSubmitted: (value) {
                              if (value.trim().isNotEmpty) {
                                _addIngredient(value);
                              }
                            },
                          );
                        },
                        // 재료 선택 시: 선택된 재료 리스트에 추가하고 입력창 초기화
                        onSelected: (value) {
                          _addIngredient(value);
                        },
                        // 자동완성 옵션 리스트 UI
                        optionsViewBuilder: (context, onSelected, options) {
                          if (options.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.white,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 200),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final option = options.elementAt(index);
                                    return InkWell(
                                      onTap: () => onSelected(option),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.restaurant,
                                              size: 18,
                                              color: Colors.grey[600],
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                option,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 자주 쓰는 재료 Quick Select (빈도순 Top 10)
                    if (topIngredients.isNotEmpty) ...[
                      Text(
                        '자주 쓰는 재료',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.grey[900],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: topIngredients.map((ingredient) {
                          final isSelected = _selectedIngredients.contains(ingredient);
                          return ActionChip(
                            label: Text(
                              ingredient,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                // 선택됨: 흰색 글씨, 선택 안 됨: 검은 글씨
                                color: isSelected ? Colors.white : Colors.black87,
                              ),
                            ),
                            backgroundColor: isSelected 
                                ? theme.colorScheme.primary 
                                : Colors.grey[200],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            onPressed: () {
                              // 스크롤 위치 저장
                              final scrollOffset = _scrollController.hasClients 
                                  ? _scrollController.offset 
                                  : 0.0;
                              
                              setState(() {
                                // 토글: 이미 선택된 재료면 제거, 없으면 추가
                                if (_selectedIngredients.contains(ingredient)) {
                                  _selectedIngredients.remove(ingredient);
                                } else {
                                  _selectedIngredients.add(ingredient);
                                }
                              });
                              
                              _filterPostsByIngredients();
                              
                              // 스크롤 위치 복원 (다음 프레임에서)
                              if (scrollOffset > 0 && _scrollController.hasClients) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (!mounted) return;
                                  if (_scrollController.hasClients) {
                                    try {
                                      _scrollController.jumpTo(scrollOffset);
                                    } catch (_) {}
                                  }
                                });
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // 검색 결과 리스트
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '검색 결과',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.grey[900],
                          ),
                        ),
                        if (_selectedIngredients.isNotEmpty)
                          Text(
                            '${displayPosts.length}개',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // 로딩 상태
                    if (isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    // 빈 상태 (귀여운 엠티 뷰)
                    else if (displayPosts.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(48),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // 귀여운 아이콘
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.orange[50],
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.kitchen_outlined,
                                size: 64,
                                color: Colors.orange[300],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _selectedIngredients.isEmpty
                                  ? '냉장고를 채워보세요! 🥬'
                                  : '이 재료로 만들 수 있는\n요리가 없어요 😢',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: Colors.grey[800],
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _selectedIngredients.isEmpty
                                  ? '재료를 선택하면\n맛있는 레시피를 찾아드려요!'
                                  : '다른 재료를 추가하거나\n다른 재료를 선택해보세요',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      )
                    // 검색 결과 리스트
                    else
                      ...displayPosts.map((post) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: GestureDetector(
                            onTap: () async {
                              // await를 사용하여 돌아올 때까지 대기 (상태 유지)
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PostDetailScreen(post: post),
                                ),
                              );
                              // 돌아왔을 때 강제 리로드 하지 않음 (스크롤 유지)
                            },
                            child: PostCard(
                              key: ValueKey(post.id),
                              // 1. ID
                              postId: post.id,
                              // 2. 작성자 및 내용
                              author: (post.authorName).isNotEmpty ? post.authorName : '익명',
                              description: (post.content).isNotEmpty ? post.content : '',
                              timestamp: _formatTimestamp(post.createdAt),
                              // 3. 숫자 필드
                              savedMoney: post.savedAmount > 0 ? post.savedAmount : null,
                              likes: _likeCountCache[post.id] ?? post.likes,
                              comments: post.comments,
                              // 4. 리스트 및 유저 ID (null 방어)
                              tags: post.tags.isNotEmpty ? post.tags : const [],
                              userId: post.userId,
                              // 5. 이미지 (nullable)
                              imageUrl: post.mainImageUrl,
                              // 6. 좋아요 상태
                              isLiked: _likeStatusCache[post.id] ??
                                  post.likedBy.contains(_authService.currentUser?.uid ?? ''),
                              // 7. 재료 매칭 (null/빈 문자열 제외하여 전달)
                              postIngredients: post.ingredients
                                  .map((ing) => ing.name)
                                  .where((n) => n.isNotEmpty)
                                  .toList(),
                              userIngredients: List<String>.from(_selectedIngredients),
                              cookingTime: post.cookingTime,
                              servings: post.servings,
                            ),
                          ),
                        );
                      }),
                    
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
        ),
    );
          },
        );
      },
    );
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }
}
