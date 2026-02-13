import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../models/meal_log_model.dart';
import '../repositories/meal_log_repository.dart';
import '../repositories/post_repository.dart';
import '../repositories/user_repository.dart';
import '../services/auth_service.dart';
import '../services/safety_service.dart';
import 'post_detail_screen.dart';
import 'follow_list_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String? userImageUrl;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.userImageUrl,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  String _viewMode = 'list'; // 'list' or 'calendar'
  DateTime _currentMonth = DateTime.now();
  bool _isLocaleInitialized = false;

  // 리스트 뷰: 월별 필터 + 더보기 페이징 (마이로그와 동일)
  DateTime _selectedMonth = DateTime.now();
  int _displayLimit = 10;
  static const int _limitStep = 10;

  final MealLogRepository _repository = MealLogRepository();
  final PostRepository _postRepository = PostRepository();
  final UserRepository _userRepo = UserRepository();
  final AuthService _auth = AuthService();
  final SafetyService _safetyService = SafetyService();

  @override
  void initState() {
    super.initState();
    _initializeLocale();
  }

  Future<void> _initializeLocale() async {
    await initializeDateFormatting('ko_KR', null);
    if (mounted) {
      setState(() {
        _isLocaleInitialized = true;
      });
    }
  }


  Map<String, List<MealLogModel>> _groupLogsByDate(List<MealLogModel> logs) {
    final Map<String, List<MealLogModel>> grouped = {};
    for (var log in logs) {
      final dateStr = DateFormat('yyyy-MM-dd').format(log.date);
      if (!grouped.containsKey(dateStr)) {
        grouped[dateStr] = [];
      }
      grouped[dateStr]!.add(log);
    }
    return grouped;
  }

  int _getDaysInMonth(DateTime date) {
    return DateTime(date.year, date.month + 1, 0).day;
  }

  int _getFirstDayOfWeek(DateTime date) {
    final firstDay = DateTime(date.year, date.month, 1);
    return firstDay.weekday % 7; // 0 = Sunday, 1 = Monday, ..., 6 = Saturday
  }

  String _formatDateKorean(DateTime date) {
    final weekdays = ['일요일', '월요일', '화요일', '수요일', '목요일', '금요일', '토요일'];
    return '${date.month}월 ${date.day}일 ${weekdays[date.weekday % 7]}';
  }

  Stream<Map<String, dynamic>> _getCombinedStatsStream(String userId) {
    return _repository.streamUserMealLogs(userId).asyncMap((logs) async {
      final totalSaved = await _postRepository.getUserTotalSavedThisMonth(userId);
      
      final now = DateTime.now();
      final thisMonthLogs = logs.where((log) => 
        log.date.year == now.year && log.date.month == now.month
      ).toList();
      final mealsCooked = thisMonthLogs.length;
      
      return {
        'totalSaved': totalSaved,
        'mealsCooked': mealsCooked,
      };
    });
  }

  /// 리스트 상단 월 선택기: [<] YYYY년 M월 [>], 월 변경 시 _displayLimit 리셋
  Widget _buildMonthSelector(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                _selectedMonth = DateTime(
                  _selectedMonth.year,
                  _selectedMonth.month - 1,
                );
                _displayLimit = _limitStep;
              });
            },
            icon: const Icon(Icons.chevron_left),
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey[100],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '${_selectedMonth.year}년 ${_selectedMonth.month}월',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: () {
              setState(() {
                _selectedMonth = DateTime(
                  _selectedMonth.year,
                  _selectedMonth.month + 1,
                );
                _displayLimit = _limitStep;
              });
            },
            icon: const Icon(Icons.chevron_right),
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey[100],
            ),
          ),
        ],
      ),
    );
  }

  /// 리스트 뷰 (월별 필터 + 더보기 페이징) — 마이로그와 동일
  Widget _buildListContent(
    ThemeData theme,
    ConnectionState connectionState,
    List<MealLogModel> logs,
    Map<String, List<MealLogModel>> groupedLogs,
  ) {
    if (connectionState == ConnectionState.waiting && logs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    final allSortedDates = groupedLogs.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    final monthFilteredDates = allSortedDates.where((dateStr) {
      final d = DateTime.parse(dateStr);
      return d.year == _selectedMonth.year && d.month == _selectedMonth.month;
    }).toList();
    final totalInMonth = monthFilteredDates.length;
    final displayedDates = monthFilteredDates.take(_displayLimit).toList();
    final hasMore = totalInMonth > _displayLimit;

    if (logs.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMonthSelector(theme),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.restaurant_menu, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  '아직 기록된 식단이 없어요',
                  style: TextStyle(color: Colors.grey[500], fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMonthSelector(theme),
        const SizedBox(height: 16),
        if (displayedDates.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_selectedMonth.month}월에는 기록된 식단이 없어요',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          )
        else ...[
          ...displayedDates.map((dateStr) {
            final date = DateTime.parse(dateStr);
            final dayLogs = groupedLogs[dateStr]!;
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
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
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 20, color: Colors.orange[600]),
                      const SizedBox(width: 8),
                      Text(
                        _isLocaleInitialized
                            ? DateFormat('M월 d일 EEEE', 'ko_KR').format(date)
                            : _formatDateKorean(date),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: dayLogs.length,
                    itemBuilder: (context, index) {
                      final meal = dayLogs[index];
                      return InkWell(
                        onTap: () async {
                          if (meal.postId != null && meal.postId!.isNotEmpty) {
                            final post = await _postRepository.getPostById(meal.postId!);
                            if (mounted && post != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PostDetailScreen(post: post),
                                ),
                              );
                            }
                          } else {
                            final posts = await _postRepository.getPostsByUserId(widget.userId);
                            final matchingPost = posts.firstWhere(
                              (post) {
                                final postDate = DateTime(
                                  post.createdAt.year,
                                  post.createdAt.month,
                                  post.createdAt.day,
                                );
                                final mealDate = DateTime(
                                  meal.date.year,
                                  meal.date.month,
                                  meal.date.day,
                                );
                                return postDate.isAtSameMomentAs(mealDate) &&
                                    post.mainImageUrl == meal.imageUrl;
                              },
                              orElse: () => posts.firstWhere(
                                (post) {
                                  final postDate = DateTime(
                                    post.createdAt.year,
                                    post.createdAt.month,
                                    post.createdAt.day,
                                  );
                                  final mealDate = DateTime(
                                    meal.date.year,
                                    meal.date.month,
                                    meal.date.day,
                                  );
                                  return postDate.isAtSameMomentAs(mealDate);
                                },
                                orElse: () => posts.first,
                              ),
                            );
                            if (mounted && posts.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PostDetailScreen(
                                    post: matchingPost,
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        child: _MealCard(
                          title: meal.mealTitle,
                          imageUrl: meal.imageUrl,
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          }).toList(),
          if (hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _displayLimit += _limitStep;
                  });
                },
                icon: const Icon(Icons.add, size: 18),
                label: Text('더보기 (${displayedDates.length}/$totalInMonth)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Future<String?> _showReportReasonDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('신고 사유 선택'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _reportReasonTile(ctx, 'spam', '스팸'),
              _reportReasonTile(ctx, 'inappropriate', '부적절한 콘텐츠'),
              _reportReasonTile(ctx, 'hate', '혐오 발언'),
              _reportReasonTile(ctx, 'privacy', '개인정보 유출'),
              _reportReasonTile(ctx, 'other', '기타'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reportReasonTile(BuildContext context, String value, String label) {
    return ListTile(
      title: Text(label),
      onTap: () => Navigator.pop(context, value),
    );
  }

  void _showReportBlockBottomSheet(BuildContext context) {
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
                    targetUid: widget.userId,
                    contentId: widget.userId,
                    type: 'user',
                    reason: reasonText,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('신고가 접수되었습니다.')),
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
                    targetUid: widget.userId,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('사용자를 차단했습니다')),
                    );
                    Navigator.pop(context);
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

  Future<void> _showDateModal(
    BuildContext context,
    DateTime date,
    List<MealLogModel> dayLogs,
  ) async {
    // Get posts for this date (for target user)
    final startDate = DateTime(date.year, date.month, date.day);
    final endDate = DateTime(date.year, date.month, date.day, 23, 59, 59);
    final posts = await _postRepository.getPostsByDateRange(startDate, endDate);
    final userPosts = posts.where((post) => post.userId == widget.userId).toList();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Text(
                        _isLocaleInitialized
                            ? DateFormat('M월 d일 EEEE', 'ko_KR').format(date)
                            : _formatDateKorean(date),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${userPosts.length}개의 식사',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                // Posts List
                Expanded(
                  child: userPosts.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              '이 날짜에 기록된 식사가 없습니다',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 14,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: userPosts.length,
                          itemBuilder: (context, index) {
                            final post = userPosts[index];
                            return InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PostDetailScreen(post: post),
                                  ),
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                child: Row(
                                  children: [
                                    // Image
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: post.mainImageUrl != null
                                          ? ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.network(
                                                post.mainImageUrl!,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  return Icon(
                                                    Icons.restaurant,
                                                    size: 30,
                                                    color: Colors.grey[400],
                                                  );
                                                },
                                              ),
                                            )
                                          : Icon(
                                              Icons.restaurant,
                                              size: 30,
                                              color: Colors.grey[400],
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Content
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            post.content.length > 30
                                                ? '${post.content.substring(0, 30)}...'
                                                : post.content,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.favorite_border,
                                                size: 14,
                                                color: Colors.grey[500],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${post.likes}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[500],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Icon(
                                                Icons.comment_outlined,
                                                size: 14,
                                                color: Colors.grey[500],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${post.comments}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[500],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final numberFormat = NumberFormat('#,###');
    final currentUid = _auth.currentUser?.uid;
    final isMe = currentUid == widget.userId;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: Text(
          '${widget.userName}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        actions: [
          if (!isMe && currentUid != null && currentUid.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showReportBlockBottomSheet(context),
              tooltip: '더보기',
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // 프로필 + 팔로워/팔로잉 + 팔로우 버튼
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _userRepo.streamUser(widget.userId),
                builder: (context, userSnap) {
                  int followersCount = 0;
                  int followingCount = 0;
                  if (userSnap.hasData && userSnap.data!.exists) {
                    final d = userSnap.data!.data();
                    followersCount = d?['followersCount'] as int? ?? 0;
                    followingCount = d?['followingCount'] as int? ?? 0;
                  }
                  final currentUid = _auth.currentUser?.uid;
                  final isMe = currentUid == widget.userId;
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: (widget.userImageUrl != null && widget.userImageUrl!.isNotEmpty)
                                  ? () {
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => Dialog(
                                          backgroundColor: Colors.transparent,
                                          insetPadding: const EdgeInsets.all(24),
                                          child: Stack(
                                            alignment: Alignment.topRight,
                                            children: [
                                              InteractiveViewer(
                                                minScale: 0.5,
                                                maxScale: 4,
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: Image.network(
                                                    widget.userImageUrl!,
                                                    fit: BoxFit.contain,
                                                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 80),
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: () => Navigator.of(ctx).pop(),
                                                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                                                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }
                                  : null,
                              child: CircleAvatar(
                                radius: 32,
                                backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.5),
                                backgroundImage: widget.userImageUrl != null && widget.userImageUrl!.isNotEmpty
                                    ? NetworkImage(widget.userImageUrl!)
                                    : null,
                                child: widget.userImageUrl == null || widget.userImageUrl!.isEmpty
                                    ? Text(
                                        widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.userName,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => FollowListScreen(
                                                userId: widget.userId,
                                                displayName: widget.userName,
                                                initialTabIndex: 0,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Text(
                                          '팔로워 $followersCount',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 20),
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => FollowListScreen(
                                                userId: widget.userId,
                                                displayName: widget.userName,
                                                initialTabIndex: 1,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Text(
                                          '팔로잉 $followingCount',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (!isMe && currentUid != null && currentUid.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          StreamBuilder<bool>(
                            stream: _userRepo.streamIsFollowing(currentUid, widget.userId),
                            builder: (context, followSnap) {
                              final isFollowing = followSnap.data ?? false;
                              return SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () async {
                                    try {
                                      if (isFollowing) {
                                        await _userRepo.unfollowUser(currentUid, widget.userId);
                                      } else {
                                        await _userRepo.followUser(currentUid, widget.userId);
                                      }
                                      if (mounted) setState(() {});
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('오류: $e')),
                                        );
                                      }
                                    }
                                  },
                                  icon: Icon(isFollowing ? Icons.person_remove : Icons.person_add, size: 20),
                                  label: Text(isFollowing ? '언팔로우' : '팔로우'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    backgroundColor: isFollowing ? Colors.grey : theme.colorScheme.primary,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Stats
              StreamBuilder<Map<String, dynamic>>(
                stream: _getCombinedStatsStream(widget.userId),
                builder: (context, snapshot) {
                  final totalSaved = snapshot.data?['totalSaved'] ?? 0;
                  final mealsCooked = snapshot.data?['mealsCooked'] ?? 0;
                  
                  return Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.trending_down,
                          label: '이번 달 절약',
                          value: '${numberFormat.format(totalSaved)}원',
                          subtitle: '배달비 대비 절약액',
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.emoji_events,
                          label: '요리 횟수',
                          value: '$mealsCooked회',
                          subtitle: '이번 달 집밥 도전',
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              // View Mode Toggle
              Row(
                children: [
                  Expanded(
                    child: _ViewModeButton(
                      label: '리스트 보기',
                      isSelected: _viewMode == 'list',
                      onTap: () {
                        setState(() {
                          _viewMode = 'list';
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ViewModeButton(
                      label: '캘린더 보기',
                      icon: Icons.calendar_today,
                      isSelected: _viewMode == 'calendar',
                      onTap: () {
                        setState(() {
                          _viewMode = 'calendar';
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Calendar View
              if (_viewMode == 'calendar')
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _currentMonth = DateTime(
                                  _currentMonth.year,
                                  _currentMonth.month - 1,
                                );
                              });
                            },
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Text(
                            '${_currentMonth.year}년 ${_currentMonth.month}월',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _currentMonth = DateTime(
                                  _currentMonth.year,
                                  _currentMonth.month + 1,
                                );
                              });
                            },
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Calendar Grid
                      StreamBuilder<List<MealLogModel>>(
                        stream: _repository.streamUserMealLogs(widget.userId),
                        builder: (context, snapshot) {
                          final logs = snapshot.data ?? [];
                          final groupedLogs = _groupLogsByDate(logs);
                          
                          return Builder(
                            builder: (context) {
                              final daysInMonth = _getDaysInMonth(_currentMonth);
                              final firstDayOfWeek = _getFirstDayOfWeek(_currentMonth);
                              // Calculate number of rows needed
                              final totalDays = firstDayOfWeek + daysInMonth;
                              final rows = (totalDays / 7).ceil();
                              final totalCells = 7 * (rows + 1); // 1 row for headers + rows for days
                              
                              return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 7,
                                  childAspectRatio: 1,
                                  crossAxisSpacing: 4,
                                  mainAxisSpacing: 4,
                                ),
                                itemCount: totalCells,
                                itemBuilder: (context, index) {
                                  if (index < 7) {
                                    // Day labels
                                    final days = ['일', '월', '화', '수', '목', '금', '토'];
                                    return Center(
                                      child: Text(
                                        days[index],
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    );
                                  }
                                  
                                  // Calculate day number
                                  final dayIndex = index - 7 - firstDayOfWeek;
                                  
                                  // Empty cells before first day
                                  if (dayIndex < 0) {
                                    return const SizedBox.shrink();
                                  }
                                  
                                  // Days beyond the month
                                  if (dayIndex >= daysInMonth) {
                                    return const SizedBox.shrink();
                                  }
                                  
                                  final day = dayIndex + 1;
                                  DateTime date;
                                  try {
                                    date = DateTime(
                                      _currentMonth.year,
                                      _currentMonth.month,
                                      day,
                                    );
                                  } catch (e) {
                                    return const SizedBox.shrink();
                                  }
                                  
                                  final dateStr = DateFormat('yyyy-MM-dd').format(date);
                                  final dayLogs = groupedLogs[dateStr] ?? [];
                                  final hasMeals = dayLogs.isNotEmpty;
                                  final mealsCount = dayLogs.length;

                                  return InkWell(
                                    onTap: hasMeals
                                        ? () => _showDateModal(context, date, dayLogs)
                                        : null,
                                    child: Container(
                                      margin: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: hasMeals
                                            ? Colors.orange[100]
                                            : Colors.grey[50],
                                        border: hasMeals
                                            ? Border.all(
                                                color: Colors.orange[400]!,
                                                width: 2,
                                              )
                                            : null,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              '$day',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.grey[700],
                                              ),
                                            ),
                                            if (hasMeals) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                '🍽️ $mealsCount',
                                                style: const TextStyle(fontSize: 10),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
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

              // List View (월별 + 더보기, 마이로그와 동일)
              if (_viewMode == 'list')
                StreamBuilder<List<MealLogModel>>(
                  stream: _repository.streamUserMealLogs(widget.userId),
                  builder: (context, snapshot) {
                    final logs = snapshot.data ?? [];
                    final groupedLogs = _groupLogsByDate(logs);
                    return _buildListContent(
                      theme,
                      snapshot.connectionState,
                      logs,
                      groupedLogs,
                    );
                  },
                ),

              // Achievements
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.yellow[50]!,
                      Colors.orange[50]!,
                    ],
                  ),
                  border: Border.all(color: Colors.yellow[200]!),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.emoji_events,
                          size: 24,
                          color: Colors.yellow[600],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '이번 달 도전 과제',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    StreamBuilder<Map<String, dynamic>>(
                      stream: _getCombinedStatsStream(widget.userId),
                      builder: (context, snapshot) {
                        final mealsCooked = snapshot.data?['mealsCooked'] ?? 0;
                        final totalSaved = snapshot.data?['totalSaved'] ?? 0;
                        return Column(
                          children: [
                            _AchievementProgress(
                              label: '집밥 20회 도전',
                              current: mealsCooked,
                              total: 20,
                              color: Colors.orange,
                            ),
                            const SizedBox(height: 12),
                            _AchievementProgress(
                              label: '10만원 절약하기',
                              current: totalSaved,
                              total: 100000,
                              color: theme.colorScheme.primary,
                              isMoney: true,
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ViewModeButton({
    required this.label,
    this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : Colors.grey[200]!,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : Colors.grey[700],
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  final String title;
  final String? imageUrl;

  const _MealCard({
    required this.title,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[200],
                        child: const Center(
                          child: Icon(
                            Icons.restaurant,
                            size: 32,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                  ),
                )
              : const Center(
                  child: Icon(
                    Icons.restaurant,
                    size: 32,
                    color: Colors.grey,
                  ),
                ),
        ),
        // Title overlay
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.7),
                  Colors.transparent,
                ],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AchievementProgress extends StatelessWidget {
  final String label;
  final int current;
  final int total;
  final Color color;
  final bool isMoney;

  const _AchievementProgress({
    required this.label,
    required this.current,
    required this.total,
    required this.color,
    this.isMoney = false,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (current / total).clamp(0.0, 1.0);
    final numberFormat = NumberFormat('#,###');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            Text(
              isMoney
                  ? '${numberFormat.format(current)}원'
                  : '$current/$total',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}
