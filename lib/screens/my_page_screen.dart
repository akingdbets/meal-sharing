import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'login/login_screen.dart';
import 'my_scrapped_posts_screen.dart';
import 'my_comments_screen.dart';
import 'my_community_posts_screen.dart';
import 'follow_list_screen.dart';
import 'edit_profile_screen.dart';

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
                          String displayName = '익명 사용자';
                          String email = user.email ?? '이메일 없음';
                          
                          int followersCount = 0;
                          int followingCount = 0;
                          String? profileImageUrl;
                          if (snapshot.hasData && snapshot.data!.exists) {
                            final userData = snapshot.data!.data() as Map<String, dynamic>?;
                            displayName = userData?['displayName'] as String? ?? 
                                        user.displayName ?? 
                                        '익명 사용자';
                            email = userData?['email'] as String? ?? email;
                            followersCount = userData?['followersCount'] as int? ?? 0;
                            followingCount = userData?['followingCount'] as int? ?? 0;
                            profileImageUrl = userData?['profileImageUrl'] as String?;
                          } else {
                            displayName = user.displayName ?? '익명 사용자';
                          }

                          final avatarText = displayName.isNotEmpty 
                              ? displayName[0].toUpperCase() 
                              : '?';
                          final hasProfileImage = profileImageUrl != null && profileImageUrl.trim().isNotEmpty;

                          return Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const SizedBox(width: 48), // Balance for trailing button
                                  // Profile Avatar (탭 시 확대)
                                  GestureDetector(
                                    onTap: hasProfileImage
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
                                                          profileImageUrl!,
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
                                      radius: 48,
                                      backgroundColor: theme.colorScheme.primaryContainer,
                                      backgroundImage: hasProfileImage ? NetworkImage(profileImageUrl) : null,
                                      child: hasProfileImage
                                          ? null
                                          : Text(
                                              avatarText,
                                              style: TextStyle(
                                                fontSize: 36,
                                                fontWeight: FontWeight.bold,
                                                color: theme.colorScheme.primary,
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
                              const SizedBox(height: 8),
                              // Email
                              Text(
                                email,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
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

              // 설정 섹션
              Container(
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Text(
                        '설정',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[900],
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
                          fontWeight: FontWeight.bold,
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
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () => _showDeleteAccountDialog(context, authService),
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
                        '문의하기',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
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
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('로그아웃', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('로그아웃 하시겠습니까?', style: TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  await authService.signOut();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
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
                  await authService.deleteAccount();
                  await Future.delayed(const Duration(milliseconds: 300));

                  if (!scaffoldContext.mounted) return;
                  Navigator.of(scaffoldContext).pop(); // 로딩 다이얼로그 닫기
                  if (!scaffoldContext.mounted) return;
                  Navigator.of(scaffoldContext).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                  didNavigateToLogin = true;
                } on FirebaseAuthException catch (e) {
                  if (e.code == 'requires-recent-login') {
                    if (scaffoldContext.mounted) {
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
                  } else if (scaffoldContext.mounted) {
                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      SnackBar(
                        content: Text('회원 탈퇴 중 오류가 발생했습니다: ${e.message ?? e.code}'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                } catch (e) {
                  if (scaffoldContext.mounted) {
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
                    Navigator.of(scaffoldContext).pop();
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
