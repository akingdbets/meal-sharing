import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'login/login_screen.dart';
import 'app_notification_screen.dart';
import 'blocked_users_screen.dart';
import 'my_scrapped_posts_screen.dart';
import 'my_comments_screen.dart';
import 'my_community_posts_screen.dart';
import 'follow_list_screen.dart';
import 'edit_profile_screen.dart';
import 'inquiry_screen.dart';

class MyPageScreen extends StatelessWidget {
  const MyPageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = AuthService();
    final user = authService.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const PageStorageKey<String>('my_page_scroll'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Section (Header)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(24),
                child: user != null
                    ? StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .snapshots(),
                        builder: (context, snapshot) {
                          // Firestore UserModel 우선, 없으면 Auth 보조
                          String displayName = user.displayName ?? '익명 사용자';
                          String email = user.email ?? '';
                          int followersCount = 0;
                          int followingCount = 0;
                          String? profileImageUrl;
                          if (snapshot.hasData && snapshot.data!.exists) {
                            final userData = snapshot.data!.data() as Map<String, dynamic>?;
                            displayName = userData?['displayName'] as String? ?? displayName;
                            email = userData?['email'] as String? ?? email;
                            followersCount = userData?['followersCount'] as int? ?? 0;
                            followingCount = userData?['followingCount'] as int? ?? 0;
                            profileImageUrl = userData?['profileImageUrl'] as String? ?? userData?['profileImage'] as String?;
                          }
                          final uid = user.uid;
                          final isNaver = uid.startsWith('naver_') || uid.startsWith('n_');
                          final isKakao = uid.startsWith('kakao_');
                          // 지메일 유저는 본인 이메일만 표시(라벨 없음), 네이버/카카오는 라벨만
                          final accountText = isNaver
                              ? '네이버 계정'
                              : (isKakao ? '카카오 계정' : email.trim());

                          final avatarText = displayName.isNotEmpty 
                              ? displayName[0].toUpperCase() 
                              : '?';
                          // 프로필 사진 없거나 기본 이미지면 아이콘 표시, 아니면 URL 사용
                          final effectiveProfileImageUrl = (profileImageUrl != null && profileImageUrl.trim().isNotEmpty)
                              ? profileImageUrl
                              : null;
                          final useDefaultAvatar = effectiveProfileImageUrl == null ||
                              effectiveProfileImageUrl == AuthService.defaultProfileImageUrl;

                          return Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const SizedBox(width: 48), // Balance for trailing button
                                  // Profile Avatar (탭 시 확대, 기본 이미지는 유저 아이콘)
                                  GestureDetector(
                                    onTap: () {
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
                                                  child: useDefaultAvatar
                                                      ? Container(
                                                          width: 256,
                                                          height: 256,
                                                          color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                                                          alignment: Alignment.center,
                                                          child: Icon(Icons.person, size: 120, color: theme.colorScheme.primary),
                                                        )
                                                      : Image.network(
                                                          effectiveProfileImageUrl,
                                                          fit: BoxFit.contain,
                                                          errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 80),
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
                                    },
                                    child: ClipOval(
                                      child: useDefaultAvatar
                                          ? Container(
                                              width: 96,
                                              height: 96,
                                              color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                                              alignment: Alignment.center,
                                              child: Icon(Icons.person, size: 48, color: theme.colorScheme.primary),
                                            )
                                          : Image.network(
                                              effectiveProfileImageUrl,
                                              width: 96,
                                              height: 96,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Container(
                                                width: 96,
                                                height: 96,
                                                color: theme.colorScheme.primaryContainer,
                                                alignment: Alignment.center,
                                                child: Text(
                                                  avatarText,
                                                  style: TextStyle(
                                                    fontSize: 36,
                                                    fontWeight: FontWeight.bold,
                                                    color: theme.colorScheme.primary,
                                                  ),
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                  // Profile Edit Button
                                  IconButton(
                                    icon: Icon(
                                      Icons.edit_outlined,
                                      color: Colors.grey[600],
                                    ),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => EditProfileScreen(
                                            currentDisplayName: displayName,
                                            currentProfileImageUrl: profileImageUrl,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Nickname
                              Text(
                                displayName,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              // 닉네임 밑 중앙: 네이버/카카오는 라벨, 지메일은 본인 이메일만(라벨 없음)
                              if (accountText.isNotEmpty)
                                Center(
                                  child: Text(
                                    accountText,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              const SizedBox(height: 12),
                              // 팔로워 / 팔로잉 (탭 가능)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => FollowListScreen(
                                            userId: user.uid,
                                            displayName: displayName,
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
                                  const SizedBox(width: 24),
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => FollowListScreen(
                                            userId: user.uid,
                                            displayName: displayName,
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
                          );
                        },
                      )
                    : const Center(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 48,
                              child: Icon(Icons.person, size: 48),
                            ),
                            SizedBox(height: 16),
                            Text('익명 사용자'),
                            Text('이메일 없음'),
                          ],
                        ),
                      ),
              ),

              const SizedBox(height: 16),

              // 내 활동 섹션
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '내 활동',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[900],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActivityCard(
                        icon: Icons.bookmark,
                        title: '내 스크랩',
                        color: theme.colorScheme.primary,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MyScrappedPostsScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActivityCard(
                        icon: Icons.comment,
                        title: '내 댓글',
                        color: theme.colorScheme.secondary,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MyCommentsScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActivityCard(
                        icon: Icons.edit_note,
                        title: '내 게시글',
                        color: theme.colorScheme.primary,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MyCommunityPostsScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 앱 알림 · 차단한 사용자 · 로그아웃
              Container(
                color: Colors.white,
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.notifications_outlined, color: Colors.grey[600]),
                      title: Text(
                        '앱 알림',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[900],
                        ),
                      ),
                      trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => const AppNotificationScreen()),
                        );
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.block, color: Colors.grey[600]),
                      title: Text(
                        '차단한 사용자',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[900],
                        ),
                      ),
                      trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => const BlockedUsersScreen()),
                        );
                      },
                    ),
                    ListTile(
                      leading: Icon(Icons.logout, color: Colors.red[600]),
                      title: Text(
                        '로그아웃',
                        style: TextStyle(
                          color: Colors.red[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () => _showLogoutDialog(context, authService),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // 앱 정보 섹션
              Container(
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Text(
                        '앱 정보',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[900],
                        ),
                      ),
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.info_outline,
                        color: Colors.grey[600],
                      ),
                      title: Text(
                        '앱 버전',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
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
                      title: Text(
                        '문의하기 / 의견 보내기',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const InquiryScreen(),
                          ),
                        );
                      },
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
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () => _showDeleteAccountDialog(context, authService),
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
          title: const Text('로그아웃', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('로그아웃 하시겠습니까?', style: TextStyle(fontWeight: FontWeight.bold)),
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
    final scaffoldContext = context;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text(
            '회원 탈퇴',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
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
                style: TextStyle(fontSize: 13, color: Colors.black),
              ),
              SizedBox(height: 8),
              Text(
                '• 프로필 정보\n• 작성한 게시글\n• 식사 로그\n• 커뮤니티 게시글',
                style: TextStyle(fontSize: 13, color: Colors.black),
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
                Navigator.of(dialogContext).pop();

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
                  // signOut 반영·UI 정리 후 로그인 화면으로 이동 (로딩/검은 화면 방지)
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
                  // 로딩 다이얼로그가 아직 남아 있으면 닫기 (예외 경로에서 pop 누락 방지)
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

class _ActivityCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _ActivityCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 32,
                color: color,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
