import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 알림 한 건 (내역용). postId+type으로 게시글로 이동, follow+senderId로 프로필로 이동.
class NotificationHistoryItem {
  final String title;
  final String body;
  final DateTime createdAt;
  final String? id;
  final String? postId;
  /// COMMENT(레시피 댓글)·COMMUNITY·follow 등.
  final String? type;
  /// 팔로우 알림 등에서 나를 팔로우한 유저 uid (프로필로 이동 시 사용)
  final String? senderId;

  NotificationHistoryItem({
    required this.title,
    required this.body,
    required this.createdAt,
    this.id,
    this.postId,
    this.type,
    this.senderId,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        if (id != null) 'id': id,
        if (postId != null) 'postId': postId,
        if (type != null) 'type': type,
        if (senderId != null) 'senderId': senderId,
      };

  factory NotificationHistoryItem.fromJson(Map<String, dynamic> json) {
    return NotificationHistoryItem(
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      id: json['id'] as String?,
      postId: json['postId'] as String?,
      type: json['type'] as String?,
      senderId: json['senderId'] as String?,
    );
  }

  /// 게시글로 이동 가능 여부 (레시피 COMMENT 또는 커뮤니티 COMMUNITY + postId 있을 때)
  bool get canNavigateToPost =>
      postId != null &&
      postId!.isNotEmpty &&
      (type == null ||
          type!.toLowerCase() == 'comment' ||
          type!.toLowerCase() == 'community');

  bool get isCommunityType =>
      type != null && type!.toLowerCase() == 'community';

  /// 팔로우 알림에서 프로필로 이동 가능 여부 (follow 타입 + senderId 있을 때)
  bool get canNavigateToProfile =>
      type != null &&
      type!.toLowerCase() == 'follow' &&
      senderId != null &&
      senderId!.isNotEmpty;
}

/// 알림 내역 저장 및 조회 (로컬)
class NotificationHistoryService extends ChangeNotifier {
  static final NotificationHistoryService _instance = NotificationHistoryService._internal();
  factory NotificationHistoryService() => _instance;
  NotificationHistoryService._internal() {
    _load();
  }

  static const String _key = 'notification_history';
  static const String _keySeenIds = 'notification_seen_ids';
  static const int _maxItems = 200;
  static const int _maxSeenIds = 500;

  final List<NotificationHistoryItem> _items = [];
  final Set<String> _seenIds = {};

  List<NotificationHistoryItem> get items => List.unmodifiable(_items);

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>?;
        if (list != null) {
          _items.clear();
          for (final e in list) {
            if (e is Map<String, dynamic>) {
              _items.add(NotificationHistoryItem.fromJson(e));
            }
          }
          _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }
      }
      final idsRaw = prefs.getStringList(_keySeenIds);
      if (idsRaw != null) _seenIds.addAll(idsRaw);
    } catch (e) {
      debugPrint('NotificationHistoryService load error: $e');
    }
  }

  Future<void> _saveSeenIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _seenIds.take(_maxSeenIds).toList();
      await prefs.setStringList(_keySeenIds, list);
    } catch (e) {
      debugPrint('NotificationHistoryService save seenIds error: $e');
    }
  }

  /// FCM 또는 Firestore 알림 추가. id가 있으면 중복 추가 방지. type+postId/senderId로 이동 여부 판단.
  Future<void> addItem({
    required String title,
    required String body,
    String? id,
    DateTime? createdAt,
    String? postId,
    String? type,
    String? senderId,
  }) async {
    final when = createdAt ?? DateTime.now();
    if (id != null && _seenIds.contains(id)) return;
    if (id != null) {
      _seenIds.add(id);
      if (_seenIds.length > _maxSeenIds) {
        final toRemove = _seenIds.length - _maxSeenIds;
        for (var i = 0; i < toRemove && _seenIds.isNotEmpty; i++) {
          _seenIds.remove(_seenIds.first);
        }
      }
      _saveSeenIds();
    }
    _items.insert(0, NotificationHistoryItem(
      title: title,
      body: body,
      createdAt: when,
      id: id,
      postId: postId,
      type: type,
      senderId: senderId,
    ));
    if (_items.length > _maxItems) {
      _items.removeRange(_maxItems, _items.length);
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_items.map((e) => e.toJson()).toList());
      await prefs.setString(_key, encoded);
    } catch (e) {
      debugPrint('NotificationHistoryService save error: $e');
    }
  }
}
