import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/post_repository.dart';
import '../repositories/user_repository.dart';
import '../models/post_model.dart';
import '../widgets/post_card.dart';
import '../services/auth_service.dart';
import 'post_detail_screen.dart';
import 'package:intl/intl.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final PostRepository _repository = PostRepository();
  final UserRepository _userRepository = UserRepository();
  final AuthService _authService = AuthService();
  Timer? _debounceTimer;

  List<String> _getBlockedIds(dynamic userData) {
    final list = userData?['blockedUserIds'] as List<dynamic>?;
    return list?.map((e) => e.toString()).toList() ?? [];
  }
  
  List<PostModel> _searchResults = [];
  List<Map<String, dynamic>> _tagsWithCounts = [];
  bool _isLoading = false;
  bool _isTagMode = false;

  @override
  void initState() {
    super.initState();
    _loadTagsWithCounts();
    _searchController.addListener(_onSearchChanged);
    
    // Auto focus search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        FocusScope.of(context).requestFocus(FocusNode());
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    
    // Check if it's tag mode
    setState(() {
      _isTagMode = query.startsWith('#');
    });

    // Cancel previous timer
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    // Debounce search
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (_isTagMode) {
        // Tag mode: filter tags
        _filterTags(query);
      } else {
        // Normal mode: search posts
        _performSearch(query);
      }
    });
  }

  Future<void> _loadTagsWithCounts() async {
    try {
      final tags = await _repository.getTagsWithCounts();
      if (mounted) {
        setState(() {
          _tagsWithCounts = tags;
        });
      }
    } catch (e) {
      print('Error loading tags: $e');
    }
  }

  void _filterTags(String query) {
    // Tags are already loaded, filtering is handled in the build method
    // This method is kept for consistency but filtering happens in _buildTagList
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final results = await _repository.searchPosts(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error searching posts: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _searchByTag(String tag) async {
    setState(() {
      _isLoading = true;
      _searchController.text = tag;
      _isTagMode = false;
    });

    try {
      final results = await _repository.getPostsByTag(tag);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error searching by tag: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
    final theme = Theme.of(context);
    final query = _searchController.text.trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '검색어를 입력하세요',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.grey[400]),
          ),
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _authService.currentUser != null ? _userRepository.streamUser(_authService.currentUser!.uid) : null,
        builder: (context, userSnap) {
          final blockedIds = userSnap.hasData ? _getBlockedIds(userSnap.data?.data()) : <String>[];
          return _buildBody(theme, query, blockedIds);
        },
      ),
    );
  }

  Widget _buildBody(ThemeData theme, String query, List<String> blockedIds) {
    // Empty state
    if (query.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            '검색어를 입력하거나 #을 눌러 태그를 검색하세요',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Tag mode
    if (_isTagMode) {
      return _buildTagList(theme, query);
    }

    // Normal search mode
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final displayResults = blockedIds.isEmpty
        ? _searchResults
        : _searchResults.where((p) => !blockedIds.contains(p.userId)).toList();

    if (displayResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              '검색 결과가 없습니다',
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
      padding: const EdgeInsets.all(16),
      itemCount: displayResults.length,
      itemBuilder: (context, index) {
        final post = displayResults[index];
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
              cookingTime: post.cookingTime,
              servings: post.servings,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTagList(ThemeData theme, String query) {
    final lowerQuery = query.toLowerCase();
    
    // Filter tags based on query
    final filteredTags = _tagsWithCounts.where((tagData) {
      final tag = (tagData['tag'] as String).toLowerCase();
      // If query is just '#', show all tags
      if (query == '#') return true;
      // Otherwise, filter by query
      return tag.contains(lowerQuery);
    }).toList();

    if (filteredTags.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.tag,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              '일치하는 태그가 없습니다',
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
      padding: const EdgeInsets.all(16),
      itemCount: filteredTags.length,
      itemBuilder: (context, index) {
        final tagData = filteredTags[index];
        final tag = tagData['tag'] as String;
        final count = tagData['count'] as int;

        return InkWell(
          onTap: () => _searchByTag(tag),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Text(
                  tag,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  '$count개',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
