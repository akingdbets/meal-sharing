import 'package:flutter/material.dart';
import '../repositories/user_repository.dart';
import '../services/auth_service.dart';
import '../services/safety_service.dart';

/// 내가 차단한 사용자 목록 및 차단 해제.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final AuthService _auth = AuthService();
  final SafetyService _safety = SafetyService();
  final UserRepository _userRepo = UserRepository();

  List<Map<String, dynamic>> _blockedUsers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() { _loading = false; _error = '로그인이 필요합니다.'; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final ids = await _safety.getBlockedUserIds(uid);
      final users = await _userRepo.getUsersByIds(ids);
      if (mounted) {
        setState(() {
          _blockedUsers = users;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '목록을 불러오지 못했습니다.';
        });
      }
    }
  }

  Future<void> _unblock(String targetUid) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null) return;
    try {
      await _safety.unblockUser(currentUid: currentUid, targetUid: targetUid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('차단을 해제했습니다')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('차단 해제 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('차단한 사용자', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey[800],
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: TextStyle(color: Colors.grey[600])),
                  ),
                )
              : _blockedUsers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.block, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            '차단한 사용자가 없습니다',
                            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      itemCount: _blockedUsers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final user = _blockedUsers[index];
                        final uid = user['uid'] as String? ?? '';
                        final displayName = user['displayName'] as String? ?? '알 수 없음';
                        final profileImageUrl = user['profileImageUrl'] as String?;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.grey[300],
                                backgroundImage: profileImageUrl != null && profileImageUrl.isNotEmpty
                                    ? NetworkImage(profileImageUrl)
                                    : null,
                                child: profileImageUrl == null || profileImageUrl.isEmpty
                                    ? Text(
                                        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton(
                                onPressed: () => _unblock(uid),
                                child: const Text('차단 해제'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
