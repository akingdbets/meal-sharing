import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'notification_history_service.dart';
import 'notification_settings_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _userNotificationsSubscription;

  Future<void> initialize() async {
    // 1. 권한 요청
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('🔔 알림 권한 허용됨');

      // [수정됨] iOS인 경우 APNs 토큰이 생성될 때까지 잠시 대기
      if (Platform.isIOS) {
        String? apnsToken = await _firebaseMessaging.getAPNSToken();

        // APNs 토큰이 아직 없으면 3초간 1초씩 쉬면서 재시도
        int retry = 0;
        while (apnsToken == null && retry < 3) {
          await Future.delayed(const Duration(seconds: 1));
          apnsToken = await _firebaseMessaging.getAPNSToken();
          retry++;
          print("⏳ APNs 토큰 대기 중... ($retry/3)");
        }
      }

      // 2. FCM 토큰 가져오기 → users/{userId}/fcmTokens 서브컬렉션에 저장
      try {
        final user = AuthService().currentUser;
        if (user != null) {
          await saveFcmTokenIfNeeded(user.uid);
        }
        // 토큰 갱신 시 자동으로 Firestore 업데이트
        _firebaseMessaging.onTokenRefresh.listen((newToken) async {
          final u = AuthService().currentUser;
          if (u != null && newToken.isNotEmpty) {
            try {
              await saveFcmTokenToFirestore(u.uid, newToken);
              print("FCM token refreshed and saved to fcmTokens");
            } catch (e) {
              print("Error saving refreshed token: $e");
            }
          }
        });
      } catch (e) {
        print("토큰 가져오기/저장 실패: $e");
      }

      await _initLocalNotifications();
      _setupMessageHandlers();
    }
  }

  /// 토큰을 해시하여 fcmTokens 서브컬렉션의 문서 ID로 사용 (여러 기기 지원)
  static String _tokenDocId(String token) {
    final bytes = utf8.encode(token);
    final hash = sha256.convert(bytes);
    return hash.toString().substring(0, 50);
  }

  /// users/{userId}/fcmTokens/{docId}에 토큰 저장 (여러 기기 = 여러 문서)
  Future<void> saveFcmTokenToFirestore(String userId, String token) async {
    final docId = _tokenDocId(token);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('fcmTokens')
        .doc(docId)
        .set({
      'token': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    print("FCM token saved to users/$userId/fcmTokens/$docId");
  }

  /// getToken() 호출 후 Firestore에 저장. 앱 시작/로그인 시 호출.
  Future<void> saveFcmTokenIfNeeded(String userId) async {
    try {
      final token = await _firebaseMessaging.getToken();
      if (token != null && token.isNotEmpty) {
        await saveFcmTokenToFirestore(userId, token);
      }
    } catch (e) {
      print("saveFcmTokenIfNeeded error: $e");
    }
  }

  /// users/{uid}/notifications 스트림 구독 → 알림 내역에 반영 (댓글 등)
  void startListeningToUserNotifications(String uid) {
    _userNotificationsSubscription?.cancel();
    _userNotificationsSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .listen((snapshot) {
      final settings = NotificationSettingsService();
      final history = NotificationHistoryService();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final type = data['type'] as String?;
        if (!settings.shouldShowNotification(type)) continue;
        final title = data['title'] as String? ?? '';
        final body = data['body'] as String? ?? '';
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
        final postId = data['postId'] as String?;
        final senderId = data['senderId'] as String?;
        history.addItem(
          title: title,
          body: body,
          id: doc.id,
          createdAt: createdAt,
          postId: postId,
          type: type,
          senderId: senderId,
        );
      }
    });
  }

  void stopListeningToUserNotifications() {
    _userNotificationsSubscription?.cancel();
    _userNotificationsSubscription = null;
  }

  static const String _androidChannelId = 'meal_sharing_notifications';
  static const String _androidChannelName = '알림';

  Future<void> _initLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestSoundPermission: false,
          requestBadgePermission: false,
          requestAlertPermission: false,
        );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        print('알림 클릭됨: ${details.payload}');
      },
    );

    // Android 8+ 채널 생성 (importance 지정 없으면 NPE 발생)
    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            _androidChannelId,
            _androidChannelName,
            description: '앱 알림',
            importance: Importance.defaultImportance,
          ),
        );
      }
    }
  }

  void _setupMessageHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📩 Foreground 메시지: ${message.notification?.title}');
      _showLocalNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('📩 알림 클릭함: ${message.data}');
      final n = message.notification;
      if (n != null) {
        final data = message.data;
        NotificationHistoryService().addItem(
          title: n.title ?? '',
          body: n.body ?? '',
          id: data['notificationId'] as String?,
          postId: data['postId'] as String?,
          type: data['type'] as String?,
          senderId: data['senderId'] as String?,
        );
      }
    });
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final settings = NotificationSettingsService();
    final data = message.data;
    final type = data['type'] as String?;
    if (!settings.shouldShowNotification(type)) return;

    // notificationId로 중복 방지 (Firestore 리스너에서 이미 추가된 경우)
    NotificationHistoryService().addItem(
      title: notification.title ?? '',
      body: notification.body ?? '',
      id: data['notificationId'] as String?,
      postId: data['postId'] as String?,
      type: type,
      senderId: data['senderId'] as String?,
    );
    await _localNotifications.show(
        id: notification.hashCode.abs().clamp(0, 0x7FFFFFFF),
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannelId,
            _androidChannelName,
            channelDescription: '앱 알림',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
  }
}
