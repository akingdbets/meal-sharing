import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'home_screen.dart';
import 'fridge_search_screen.dart';
import 'community_screen.dart';
import 'my_log_screen.dart';
import 'my_page_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key, this.initialHomeTabIndex});

  /// 온보딩에서 선택한 카테고리(0: 현실 집밥, 1: 자취 밥상)를 홈 첫 진입 시 반영
  final int? initialHomeTabIndex;

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  DateTime? _lastBackPressed;

  @override
  void initState() {
    super.initState();
    final uid = AuthService().currentUser?.uid;
    if (uid != null) {
      NotificationService().saveFcmTokenIfNeeded(uid);
      NotificationService().startListeningToUserNotifications(uid);
    }
  }

  @override
  void dispose() {
    NotificationService().stopListeningToUserNotifications();
    super.dispose();
  }

  List<Widget> get _screens => [
    HomeScreen(initialTabIndex: widget.initialHomeTabIndex),
    const FridgeSearchScreen(),
    const CommunityScreen(),
    const MyLogScreen(),
    const MyPageScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (!mounted) return;

        final now = DateTime.now();
        if (_lastBackPressed == null ||
            now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
          _lastBackPressed = now;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('뒤로 버튼을 한번 더 누르면 종료됩니다.'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        // 선택된 탭만 글자 표시, 선택되지 않은 탭은 글자 숨김
        showSelectedLabels: true,
        showUnselectedLabels: false,
        // 폰트 크기 고정
        selectedFontSize: 12.0,
        unselectedFontSize: 12.0,
        // 라벨 스타일: 굵고 선명하게
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12.0,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12.0,
        ),
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: Colors.grey[600],
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: '홈',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: '냉장고 파먹기',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: '자유게시판',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: '마이로그',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: '마이페이지',
          ),
        ],
      ),
      ),
    );
  }
}
