import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../widgets/notification_setting_tiles.dart';
import 'login/login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = AuthService();
    final user = authService.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const PageStorageKey<String>('settings_scroll'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                color: Colors.white,
                child: Text(
                  '설정 ⚙️',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 28,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Profile Section
              user != null
                  ? StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .snapshots(),
                      builder: (context, snapshot) {
                        String displayName = '익명 사용자';
                        if (snapshot.hasData && snapshot.data!.exists) {
                          final userData = snapshot.data!.data() as Map<String, dynamic>?;
                          displayName = userData?['displayName'] as String? ?? 
                                        user.displayName ?? 
                                        '익명 사용자';
                        } else {
                          displayName = user.displayName ?? '익명 사용자';
                        }

                        // Get first character for avatar
                        final avatarText = displayName.isNotEmpty 
                            ? displayName[0].toUpperCase() 
                            : '?';

                        return Container(
                          color: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: ListTile(
                            leading: CircleAvatar(
                              radius: 32,
                              backgroundColor: theme.colorScheme.primaryContainer,
                              child: Text(
                                avatarText,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            title: Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              user.email ?? '이메일 없음',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                Icons.edit_outlined,
                                color: Colors.grey[600],
                              ),
                              onPressed: () {
                                // TODO: Implement edit profile
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('프로필 편집 기능은 준비 중입니다'),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    )
                  : Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: const ListTile(
                        leading: CircleAvatar(
                          radius: 32,
                          child: Icon(Icons.person),
                        ),
                        title: Text('익명 사용자'),
                        subtitle: Text('이메일 없음'),
                      ),
                    ),

              const SizedBox(height: 8),

              // Account Actions Section
              Container(
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        '계정',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.logout,
                        color: Colors.red[600],
                      ),
                      title: Text(
                        '로그아웃',
                        style: TextStyle(
                          color: Colors.red[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () => _showLogoutDialog(context, authService),
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.person_remove_outlined,
                        color: Colors.red[600],
                      ),
                      title: Text(
                        '회원 탈퇴',
                        style: TextStyle(
                          color: Colors.red[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () => _showDeleteAccountDialog(context, authService),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // 앱 알림 설정 (토글만 리빌드되어 스크롤 유지)
              Container(
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        '앱 알림 설정',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const NotificationSettingTiles(),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // App Info Section
              Container(
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        '앱 정보',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.info_outline,
                        color: Colors.grey[600],
                      ),
                      title: const Text('앱 버전'),
                      trailing: Text(
                        '1.0.0',
                        style: TextStyle(
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.help_outline,
                        color: Colors.grey[600],
                      ),
                      title: const Text('문의하기'),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('문의하기 기능은 준비 중입니다'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, AuthService authService) {
    final scaffoldContext = context;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('로그아웃'),
          content: const Text('로그아웃 하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                try {
                  await authService.signOut();
                  if (!scaffoldContext.mounted) return;
                  Navigator.of(scaffoldContext).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                } catch (e) {
                  if (scaffoldContext.mounted) {
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      SnackBar(
                        content: Text('로그아웃 중 오류가 발생했습니다: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: Text(
                '로그아웃',
                style: TextStyle(
                  color: Colors.red[600],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteAccountDialog(BuildContext context, AuthService authService) {
    // 비동기 콜백에서 사용할 부모 context 보존 (확인 다이얼로그 pop 후에도 유효)
    final scaffoldContext = context;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text(
            '회원 탈퇴',
            style: TextStyle(color: Colors.red),
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '정말 회원 탈퇴를 하시겠습니까?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text(
                '탈퇴 시 다음 정보가 모두 삭제됩니다:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              SizedBox(height: 8),
              Text(
                '• 프로필 정보\n• 작성한 게시글\n• 식사 로그\n• 커뮤니티 게시글',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              SizedBox(height: 12),
              Text(
                '이 작업은 되돌릴 수 없습니다.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop(); // 확인 다이얼로그만 닫기

                if (!scaffoldContext.mounted) return;
                showDialog(
                  context: scaffoldContext,
                  barrierDismissible: false,
                  builder: (BuildContext _) {
                    return const AlertDialog(
                      content: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(width: 16),
                          Text('계정을 삭제하는 중...'),
                        ],
                      ),
                    );
                  },
                );

                bool didNavigateToLogin = false;
                try {
                  // 타임아웃 90초: 무한 대기 방지
                  await authService.deleteAccount().timeout(
                    const Duration(seconds: 90),
                    onTimeout: () {
                      throw TimeoutException('회원 탈퇴 처리 시간이 초과되었습니다.');
                    },
                  );

                  if (!scaffoldContext.mounted) return;
                  Navigator.of(scaffoldContext).pop(); // 로딩 다이얼로그 먼저 닫기
                  if (!scaffoldContext.mounted) return;
                  await Future.delayed(const Duration(milliseconds: 400));
                  if (!scaffoldContext.mounted) return;
                  Navigator.of(scaffoldContext).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                  didNavigateToLogin = true;
                } on FirebaseAuthException catch (e) {
                  if (e.code == 'requires-recent-login') {
                    if (scaffoldContext.mounted) {
                      Navigator.of(scaffoldContext).pop(); // 로딩 다이얼로그 먼저 닫기
                      if (!scaffoldContext.mounted) return;
                      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                        const SnackBar(
                          content: Text('보안을 위해 다시 로그인한 후 탈퇴해주세요.'),
                          backgroundColor: Colors.red,
                          duration: Duration(seconds: 5),
                        ),
                      );
                      Navigator.of(scaffoldContext).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => const LoginScreen()),
                        (route) => false,
                      );
                      didNavigateToLogin = true;
                    }
                  } else {
                    if (scaffoldContext.mounted) {
                      Navigator.of(scaffoldContext).pop();
                      ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                        SnackBar(
                          content: Text('회원 탈퇴 중 오류가 발생했습니다: ${e.message ?? e.code}'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                  }
                } on TimeoutException catch (e) {
                  if (scaffoldContext.mounted) {
                    Navigator.of(scaffoldContext).pop();
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      SnackBar(
                        content: Text(e.message ?? '처리 시간이 초과되었습니다. 다시 시도해 주세요.'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                } catch (e) {
                  if (scaffoldContext.mounted) {
                    Navigator.of(scaffoldContext).pop();
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      SnackBar(
                        content: Text('회원 탈퇴 중 오류가 발생했습니다: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                } finally {
                  if (scaffoldContext.mounted && !didNavigateToLogin) {
                    try {
                      Navigator.of(scaffoldContext).pop();
                    } catch (_) {}
                  }
                }
              },
              child: Text(
                '탈퇴하기',
                style: TextStyle(
                  color: Colors.red[600],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
