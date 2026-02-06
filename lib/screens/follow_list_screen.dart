import 'package:flutter/material.dart';
import '../repositories/user_repository.dart';
import '../services/auth_service.dart';
import 'user_profile_screen.dart';

/// 팔로워/팔로잉 탭 리스트. [프로필사진] [닉네임] [팔로우/맞팔로우]. 탭 시 UserProfileScreen 이동.
class FollowListScreen extends StatefulWidget {
  final String userId;
  final String displayName;
  final int initialTabIndex; // 0: 팔로워, 1: 팔로잉

  const FollowListScreen({
    super.key,
    required this.userId,
    required this.displayName,
    this.initialTabIndex = 0,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final UserRepository _userRepo = UserRepository();
  final AuthService _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUid = _auth.currentUser?.uid;
    final isMyList = currentUid == widget.userId;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: Text(
          widget.displayName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: theme.colorScheme.primary,
          tabs: const [
            Tab(text: '팔로워'),
            Tab(text: '팔로잉'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _FollowTab(
            stream: _userRepo.streamFollowers(widget.userId),
            currentUid: currentUid,
            isMyList: isMyList,
            userRepo: _userRepo,
          ),
          _FollowTab(
            stream: _userRepo.streamFollowing(widget.userId),
            currentUid: currentUid,
            isMyList: isMyList,
            userRepo: _userRepo,
          ),
        ],
      ),
    );
  }
}

class _FollowTab extends StatefulWidget {
  final Stream<List<String>> stream;
  final String? currentUid;
  final bool isMyList;
  final UserRepository userRepo;

  const _FollowTab({
    required this.stream,
    required this.currentUid,
    required this.isMyList,
    required this.userRepo,
  });

  @override
  State<_FollowTab> createState() => _FollowTabState();
}

class _FollowTabState extends State<_FollowTab> {
  List<Map<String, dynamic>> _userInfos = [];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: widget.stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final uids = snap.data ?? [];
        if (uids.isEmpty) {
          return Center(
            child: Text(
              '목록이 비어 있어요',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          );
        }
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: widget.userRepo.getUsersByIds(uids),
          builder: (context, futureSnap) {
            if (!futureSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            _userInfos = futureSnap.data!;
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _userInfos.length,
              itemBuilder: (context, index) {
                final info = _userInfos[index];
                final uid = info['uid'] as String? ?? '';
                final displayName =
                    info['displayName'] as String? ?? '알 수 없음';
                final profileImageUrl = info['profileImageUrl'] as String?;
                final isMe = uid == widget.currentUid;
                return _FollowListItem(
                  uid: uid,
                  displayName: displayName,
                  profileImageUrl: profileImageUrl,
                  currentUid: widget.currentUid,
                  isMyList: widget.isMyList,
                  isMe: isMe,
                  userRepo: widget.userRepo,
                  onFollowChanged: () => setState(() {}),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _FollowListItem extends StatelessWidget {
  final String uid;
  final String displayName;
  final String? profileImageUrl;
  final String? currentUid;
  final bool isMyList;
  final bool isMe;
  final UserRepository userRepo;
  final VoidCallback onFollowChanged;

  const _FollowListItem({
    required this.uid,
    required this.displayName,
    this.profileImageUrl,
    required this.currentUid,
    required this.isMyList,
    required this.isMe,
    required this.userRepo,
    required this.onFollowChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(
              userId: uid,
              userName: displayName,
              userImageUrl: profileImageUrl,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.5),
              backgroundImage: profileImageUrl != null && profileImageUrl!.isNotEmpty
                  ? NetworkImage(profileImageUrl!)
                  : null,
              child: profileImageUrl == null || profileImageUrl!.isEmpty
                  ? Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (currentUid != null && currentUid!.isNotEmpty && !isMe)
              StreamBuilder<bool>(
                stream: userRepo.streamIsFollowing(currentUid!, uid),
                builder: (context, followSnap) {
                  final isFollowing = followSnap.data ?? false;
                  final showFollowBack = isMyList && !isFollowing;
                  return TextButton(
                    onPressed: () async {
                      try {
                        if (isFollowing) {
                          await userRepo.unfollowUser(currentUid!, uid);
                        } else {
                          await userRepo.followUser(currentUid!, uid);
                        }
                        onFollowChanged();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('오류: $e')),
                          );
                        }
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: Text(
                      showFollowBack ? '맞팔로우' : (isFollowing ? '언팔로우' : '팔로우'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
