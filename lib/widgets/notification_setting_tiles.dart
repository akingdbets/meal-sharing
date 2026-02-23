import 'package:flutter/material.dart';
import '../services/notification_settings_service.dart';

/// 앱 알림 설정 - 활동별 토글. ListenableBuilder로 이 블록만 리빌드되어 스크롤 유지.
class NotificationSettingTiles extends StatelessWidget {
  const NotificationSettingTiles({super.key});

  static Future<void> _saveSetting(BuildContext context, Future<bool> Function() save) async {
    final ok = await save();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('설정 저장에 실패했습니다. 다시 시도해 주세요.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NotificationSettingsService(),
      builder: (context, _) {
        final service = NotificationSettingsService();
        return Column(
          children: [
            ListTile(
              leading: Icon(Icons.chat_bubble_outline, color: Colors.grey[600]),
              title: const Text('댓글·답글 알림', style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: Switch(
                value: service.commentsEnabled,
                onChanged: (v) => _saveSetting(context, () => service.setCommentsEnabled(v)),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.person_add_outlined, color: Colors.grey[600]),
              title: const Text('팔로우 알림', style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: Switch(
                value: service.followsEnabled,
                onChanged: (v) => _saveSetting(context, () => service.setFollowsEnabled(v)),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.groups_outlined, color: Colors.grey[600]),
              title: const Text('자유게시판 알림', style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: Switch(
                value: service.communityEnabled,
                onChanged: (v) => _saveSetting(context, () => service.setCommunityEnabled(v)),
              ),
            ),
          ],
        );
      },
    );
  }
}
