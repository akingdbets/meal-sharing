import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

/// 앱 알림 설정 - 활동별 on/off (로컬 + Firestore 동기화). Cloud Function이 Firestore 설정을 보고 푸시 발송 여부 결정.
class NotificationSettingsService extends ChangeNotifier {
  static final NotificationSettingsService _instance =
      NotificationSettingsService._internal();
  factory NotificationSettingsService() => _instance;
  NotificationSettingsService._internal() {
    _load();
  }

  static const String _keyMaster = 'notification_enabled';
  static const String _keyComments = 'notification_comments';
  static const String _keyLikes = 'notification_likes';
  static const String _keyFollows = 'notification_follows';
  static const String _keyCommunity = 'notification_community';

  bool _master = true;
  bool _comments = true;
  bool _likes = true;
  bool _follows = true;
  bool _community = true;

  /// 전체 알림 (꺼지면 모든 알림 미표시)
  bool get notificationEnabled => _master;
  bool get commentsEnabled => _comments;
  bool get likesEnabled => _likes;
  bool get followsEnabled => _follows;
  bool get communityEnabled => _community;

  /// FCM data['type']과 매칭 (백엔드에서 동일 문자열 사용 권장)
  static const String typeComment = 'comment';
  static const String typeLike = 'like';
  static const String typeFollow = 'follow';
  static const String typeCommunity = 'community';

  /// 해당 활동 타입 알림을 표시해도 되는지 (타입별 설정만 적용, 전체 알림 없음)
  bool shouldShowNotification(String? type) {
    final t = type?.toLowerCase();
    switch (t) {
      case 'comment':
        return _comments;
      case 'like':
        return _likes;
      case 'follow':
        return _follows;
      case 'community':
        return _community;
      default:
        return true;
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _master = prefs.getBool(_keyMaster) ?? true;
      _comments = prefs.getBool(_keyComments) ?? true;
      _likes = prefs.getBool(_keyLikes) ?? true;
      _follows = prefs.getBool(_keyFollows) ?? true;
      _community = prefs.getBool(_keyCommunity) ?? true;
      notifyListeners();
      // 로그인 유저면 Firestore에 현재 설정 동기화 (Cloud Function 푸시 판단용)
      await _syncToFirestore();
    } catch (e) {
      debugPrint('NotificationSettingsService load error: $e');
    }
  }

  Future<bool> _save(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
      return true;
    } catch (e) {
      debugPrint('NotificationSettingsService save error: $e');
      return false;
    }
  }

  /// Firestore users/{uid}에 알림 설정 동기화 (Cloud Function이 푸시 발송 여부 판단에 사용)
  Future<void> _syncToFirestore() async {
    final uid = AuthService().currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'notificationComments': _comments,
        'notificationFollows': _follows,
        'notificationCommunity': _community,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('NotificationSettingsService Firestore sync error: $e');
    }
  }

  Future<bool> setMasterEnabled(bool value) async {
    final prev = _master;
    _master = value;
    notifyListeners();
    if (!await _save(_keyMaster, value)) {
      _master = prev;
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<bool> setCommentsEnabled(bool value) async {
    final prev = _comments;
    _comments = value;
    notifyListeners();
    if (!await _save(_keyComments, value)) {
      _comments = prev;
      notifyListeners();
      return false;
    }
    await _syncToFirestore();
    return true;
  }

  Future<bool> setLikesEnabled(bool value) async {
    final prev = _likes;
    _likes = value;
    notifyListeners();
    if (!await _save(_keyLikes, value)) {
      _likes = prev;
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<bool> setFollowsEnabled(bool value) async {
    final prev = _follows;
    _follows = value;
    notifyListeners();
    if (!await _save(_keyFollows, value)) {
      _follows = prev;
      notifyListeners();
      return false;
    }
    await _syncToFirestore();
    return true;
  }

  Future<bool> setCommunityEnabled(bool value) async {
    final prev = _community;
    _community = value;
    notifyListeners();
    if (!await _save(_keyCommunity, value)) {
      _community = prev;
      notifyListeners();
      return false;
    }
    await _syncToFirestore();
    return true;
  }

  /// 기존 단일 토글 호환
  Future<bool> setEnabled(bool value) async => setMasterEnabled(value);

  Future<bool> loadInitial() async {
    await _load();
    return _master;
  }
}
