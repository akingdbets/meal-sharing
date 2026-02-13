import 'package:flutter/material.dart';
import '../widgets/notification_setting_tiles.dart';

/// 앱 알림 전용 화면 - 알림 설정만 가능.
class AppNotificationScreen extends StatelessWidget {
  const AppNotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('앱 알림', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.grey[800],
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Container(
                color: Colors.white,
                child: const NotificationSettingTiles(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
