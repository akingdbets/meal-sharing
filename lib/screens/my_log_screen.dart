import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:async';
import '../models/meal_log_model.dart';
import '../repositories/meal_log_repository.dart';
import '../repositories/post_repository.dart';
import '../services/auth_service.dart';
import 'post_detail_screen.dart';

class MyLogScreen extends StatefulWidget {
  const MyLogScreen({super.key});

  @override
  State<MyLogScreen> createState() => _MyLogScreenState();
}

class _MyLogScreenState extends State<MyLogScreen> with AutomaticKeepAliveClientMixin {
  String _viewMode = 'list'; // 'list' or 'calendar'
  DateTime _currentMonth = DateTime.now();
  bool _isLocaleInitialized = false;

  // 리스트 뷰: 월별 필터 + 더보기 페이징
  DateTime _selectedMonth = DateTime.now();
  int _displayLimit = 10;
  static const int _limitStep = 10;
  final MealLogRepository _repository = MealLogRepository();
  final PostRepository _postRepository = PostRepository();
  final AuthService _authService = AuthService();

  // Stream instances; 재초기화를 위해 nullable로 두고 didChangeDependencies에서 설정
  Stream<List<MealLogModel>>? _mealLogsStream;
  Stream<Map<String, dynamic>>? _statsStream;
  String? _lastUserId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeLocale();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 로그인/로그아웃 시 또는 화면 복귀 시 스트림 갱신 (캘린더·리스트 데이터 반영)
    final user = _authService.currentUser;
    final userId = user?.uid;
    if (userId != _lastUserId) {
      _lastUserId = userId;
      if (userId != null) {
        // broadcast: StreamBuilder 재생성 시 "already been listened to" 방지 (타입 유지)
        _mealLogsStream = _repository.streamUserMealLogs(userId).asBroadcastStream();
        _statsStream = _getCombinedStatsStream(userId).share();
      } else {
        _mealLogsStream = Stream.value([]);
        _statsStream = Stream.value({'totalSaved': 0, 'mealsCooked': 0}).share();
      }
      if (mounted) setState(() {});
    }
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

  /// 게시글 삭제 시에도 절약 금액이 갱신되도록 mealLogs + totalSaved 스트림을 함께 구독.
  Stream<Map<String, dynamic>> _getCombinedStatsStream(String userId) {
    final mealLogsStream = _repository.streamUserMealLogs(userId);
    final totalSavedStream = _postRepository.streamUserTotalSavedThisMonth(userId);
    return Rx.combineLatest2<List<MealLogModel>, int, Map<String, dynamic>>(
      mealLogsStream,
      totalSavedStream,
      (logs, totalSaved) {
        final now = DateTime.now();
        final thisMonthLogs = logs.where((log) =>
          log.date.year == now.year && log.date.month == now.month
        ).toList();
        return {
          'totalSaved': totalSaved,
          'mealsCooked': thisMonthLogs.length,
        };
      },
    );
  }

  Future<void> _showDateModal(
    BuildContext context,
    DateTime date,
    List<MealLogModel> dayLogs,
  ) async {
    final user = _authService.currentUser;
    if (user == null) return;

    // Get posts for this date
    final startDate = DateTime(date.year, date.month, date.day);
    final endDate = DateTime(date.year, date.month, date.day, 23, 59, 59);
    final posts = await _postRepository.getPostsByDateRange(startDate, endDate);
    final userPosts = posts.where((post) => post.userId == user.uid).toList();

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

  /// 캘린더 그리드 (스트림 데이터를 인자로 받아 전환 시에도 데이터 유지)
  Widget _buildCalendarContent(
    ThemeData theme,
    List<MealLogModel> logs,
    Map<String, List<MealLogModel>> groupedLogs,
  ) {
    final daysInMonth = _getDaysInMonth(_currentMonth);
    final firstDayOfWeek = _getFirstDayOfWeek(_currentMonth);
    final totalDays = firstDayOfWeek + daysInMonth;
    final rows = (totalDays / 7).ceil();
    final totalCells = 7 * (rows + 1);

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
          GridView.builder(
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
              final dayIndex = index - 7 - firstDayOfWeek;
              if (dayIndex < 0) return const SizedBox.shrink();
              if (dayIndex >= daysInMonth) return const SizedBox.shrink();
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
                    color: hasMeals ? Colors.orange[100] : Colors.grey[50],
                    border: hasMeals
                        ? Border.all(color: Colors.orange[400]!, width: 2)
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
          ),
        ],
      ),
    );
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
                _displayLimit = 10;
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
                _displayLimit = 10;
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

  /// 리스트 뷰 (월별 필터 + 더보기 페이징)
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
    // 선택한 월에 해당하는 날짜만 필터
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
                      final user = _authService.currentUser;
                      if (user == null) return;
                      if (meal.postId != null && meal.postId!.isNotEmpty) {
                        final post =
                            await _postRepository.getPostById(meal.postId!);
                        if (mounted && post != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  PostDetailScreen(post: post),
                            ),
                          );
                        }
                      } else {
                        final posts =
                            await _postRepository.getPostsByUserId(user.uid);
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin을 위해 필수
    final theme = Theme.of(context);
    final numberFormat = NumberFormat('#,###');

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const PageStorageKey('my_log_scroll_key'),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더: 간소한 타이틀 (냉장고 파먹기와 동일 위치·스타일)
              Row(
                children: [
                  Text(
                    '마이 로그 📅',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: Colors.grey[900],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Stats + 도전 과제: _statsStream 단일 구독으로 Bad state 방지
              StreamBuilder<Map<String, dynamic>>(
                stream: _statsStream ?? Stream.value({'totalSaved': 0, 'mealsCooked': 0}),
                builder: (context, statsSnapshot) {
                  final totalSaved = statsSnapshot.data?['totalSaved'] ?? 0;
                  final mealsCooked = statsSnapshot.data?['mealsCooked'] ?? 0;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                      ),
                      const SizedBox(height: 16),

                      // Hoisted: 단일 StreamBuilder — 리스트/캘린더 전환 시 스트림 유지, 무한 로딩 방지
              StreamBuilder<List<MealLogModel>>(
                stream: _mealLogsStream ?? Stream.value([]),
                builder: (context, mealSnapshot) {
                  final logs = mealSnapshot.data ?? [];
                  final groupedLogs = _groupLogsByDate(logs);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // View Mode Toggle (StreamBuilder 내부 → 전환 시에도 snapshot 유지)
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
                      if (_viewMode == 'list')
                        _buildListContent(
                          theme,
                          mealSnapshot.connectionState,
                          logs,
                          groupedLogs,
                        ),
                      if (_viewMode == 'calendar')
                        _buildCalendarContent(theme, logs, groupedLogs),
                      const SizedBox(height: 16),

                      // 이번 달 도전 과제 (동일 statsSnapshot 사용)
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
                            Column(
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
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          );
                },
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          if (imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            )
          else
            Center(
              child: Icon(
                Icons.restaurant,
                size: 48,
                color: Colors.grey[400],
              ),
            ),
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
      ),
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
