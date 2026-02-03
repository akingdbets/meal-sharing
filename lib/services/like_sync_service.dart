import 'dart:async';

/// 좋아요 변경 이벤트 모델
class LikeUpdateEvent {
  final String postId;
  final bool isLiked;
  final int likeCount;

  LikeUpdateEvent({
    required this.postId,
    required this.isLiked,
    required this.likeCount,
  });
}

/// 싱글톤 서비스
/// 앱 전체에서 좋아요 상태를 실시간으로 동기화하기 위한 중계소
class LikeSyncService {
  static final LikeSyncService _instance = LikeSyncService._internal();
  factory LikeSyncService() => _instance;
  LikeSyncService._internal();

  final _controller = StreamController<LikeUpdateEvent>.broadcast();
  Stream<LikeUpdateEvent> get stream => _controller.stream;

  /// 좋아요 상태 변경 시 호출
  /// 이 메서드를 호출하면 앱 내의 모든 화면에 좋아요 상태 변경이 방송됨
  void updateLike(String postId, bool isLiked, int likeCount) {
    _controller.add(LikeUpdateEvent(
      postId: postId,
      isLiked: isLiked,
      likeCount: likeCount,
    ));
  }
}
