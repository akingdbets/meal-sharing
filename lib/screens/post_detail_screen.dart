import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/post_model.dart';
import '../models/comment_model.dart';
import '../repositories/post_repository.dart';
import '../repositories/comment_repository.dart';
import '../repositories/meal_log_repository.dart';
import '../services/auth_service.dart';
import '../services/like_sync_service.dart';
import '../services/safety_service.dart';
import '../services/hidden_content_service.dart';
import '../repositories/user_repository.dart';
import '../utils/profanity_filter.dart';
import 'edit_post_screen.dart';
import 'user_profile_screen.dart';

class PostDetailScreen extends StatefulWidget {
  final PostModel post;

  const PostDetailScreen({
    super.key,
    required this.post,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final PostRepository _postRepository = PostRepository();
  final CommentRepository _commentRepository = CommentRepository();
  final AuthService _authService = AuthService();
  final SafetyService _safetyService = SafetyService();
  final UserRepository _userRepository = UserRepository();
  final LikeSyncService _likeSyncService = LikeSyncService();
  final HiddenContentService _hiddenContentService = HiddenContentService();
  final TextEditingController _commentController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  PostModel? _currentPost;
  bool _isLiked = false;
  bool _isScrapped = false;
  bool _isLoading = false;
  File? _commentImageFile;
  String? _commentImageUrl;
  bool _isUploadingCommentImage = false;
  
  // 댓글 수를 로컬 상태로 관리하여 즉시 갱신
  late int _commentCount;
  
  // 좋아요 동기화 구독
  StreamSubscription<LikeUpdateEvent>? _likeSubscription;
  
  // YouTube Player Controller
  YoutubePlayerController? _youtubeController;

  @override
  void initState() {
    super.initState();
    _currentPost = widget.post;
    _isLiked = _currentPost!.likedBy.contains(_authService.currentUser?.uid ?? '');
    // 초기값을 post 데이터에서 가져옴
    _commentCount = _currentPost!.comments;
    _checkScrapStatus();
    
    // Initialize YouTube controller if video ID exists
    _initYoutubeController();
    
    // [핵심] 화면 진입 즉시 백그라운드에서 최신 데이터 가져오기 (Silent Update)
    _fetchLatestPostData();
    
    // 좋아요 상태 변경 이벤트 구독
    _likeSubscription = _likeSyncService.stream.listen((event) {
      // 이 게시물의 좋아요 상태가 변경되었는지 확인
      if (event.postId == _currentPost?.id) {
        if (mounted) {
          setState(() {
            _isLiked = event.isLiked;
            // _currentPost의 likes도 업데이트
            if (_currentPost != null) {
              _currentPost = _currentPost!.copyWith(
                likes: event.likeCount,
                likedBy: event.isLiked
                    ? [..._currentPost!.likedBy, _authService.currentUser?.uid ?? '']
                    : _currentPost!.likedBy.where((id) => id != _authService.currentUser?.uid).toList(),
              );
            }
          });
        }
      }
    });
  }
  
  void _initYoutubeController() {
    if (_currentPost?.youtubeVideoId != null && _currentPost!.youtubeVideoId!.isNotEmpty) {
      _youtubeController = YoutubePlayerController(
        initialVideoId: _currentPost!.youtubeVideoId!,
        flags: const YoutubePlayerFlags(
          autoPlay: false,
          mute: false,
          disableDragSeek: false,
          loop: false,
          isLive: false,
          forceHD: false,
          enableCaption: true,
        ),
      );
    }
  }
  
  /// 화면 진입 시 서버에서 최신 게시물 데이터를 가져와 조용히 업데이트 (Silent Update)
  /// 로딩 인디케이터 없이 기존 데이터를 먼저 보여준 뒤 백그라운드에서 갱신
  Future<void> _fetchLatestPostData() async {
    try {
      final freshPost = await _postRepository.getPostById(widget.post.id);
      
      if (freshPost != null && mounted) {
        setState(() {
          _currentPost = freshPost;
          
          // 개별 상태 변수들도 최신 데이터로 동기화
          _isLiked = freshPost.likedBy.contains(_authService.currentUser?.uid ?? '');
          _commentCount = freshPost.comments;
        });
        
        // 전역 좋아요 동기화 서비스에도 최신 상태 방송 (다른 화면들도 업데이트)
        _likeSyncService.updateLike(
          freshPost.id,
          _isLiked,
          freshPost.likes,
        );
      }
    } catch (e) {
      // Silent fail - 기존 데이터로 계속 표시
      print("게시물 최신화 실패 (무시 가능): $e");
    }
  }

  Future<void> _checkScrapStatus() async {
    final user = _authService.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (userDoc.exists && mounted) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final scrappedPostIds = (userData['scrappedPostIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        setState(() {
          _isScrapped = scrappedPostIds.contains(_currentPost?.id ?? '');
        });
      }
    } catch (e) {
      print('Error checking scrap status: $e');
    }
  }

  Future<void> _toggleScrap() async {
    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다')),
      );
      return;
    }

    if (_currentPost == null) return;

    setState(() {
      _isScrapped = !_isScrapped;
    });

    try {
      await _postRepository.toggleScrap(_currentPost!.id, user.uid);
    } catch (e) {
      setState(() {
        _isScrapped = !_isScrapped;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('스크랩 처리 중 오류가 발생했습니다: $e')),
      );
    }
  }

  /// Launch URL (can be replaced with tracking link later)
  Future<void> _launchURL(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('링크를 열 수 없습니다'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('링크 열기 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Search ingredient on Coupang
  Future<void> _searchOnCoupang(String ingredientName) async {
    // URL encoding for Korean characters
    final encodedName = Uri.encodeComponent(ingredientName);
    final url = 'https://www.coupang.com/np/search?component=&q=$encodedName&channel=user';
    await _launchURL(url);
  }

  /// Share current post
  Future<void> _sharePost() async {
    if (_currentPost == null) return;
    final text = '오늘의 식탁에서 위 음식의 레시피를 확인해보세요!!\n\n[App Store 다운로드]\nhttps://apps.apple.com/app/id000000000\n\n[Google Play 다운로드]\nhttps://play.google.com/store/apps/details?id=com.example.app';

    try {
      if (_currentPost!.mainImageUrl != null && _currentPost!.mainImageUrl!.isNotEmpty) {
        // Download image to a temporary file
        final response = await http.get(Uri.parse(_currentPost!.mainImageUrl!));
        if (response.statusCode == 200) {
          final tempDir = await getTemporaryDirectory();
          final file = File('${tempDir.path}/share_image_${DateTime.now().millisecondsSinceEpoch}.jpg');
          await file.writeAsBytes(response.bodyBytes);
          
          await Share.shareXFiles(
            [XFile(file.path)],
            text: text,
          );
          return;
        }
      }
    } catch (e) {
      print('Error sharing post with image: $e');
      // Fallback to text only
    }

    // Share text only if no image or error occurred
    await Share.share(text);
  }

  @override
  void dispose() {
    // 구독 취소하여 메모리 누수 방지
    _likeSubscription?.cancel();
    _commentController.dispose();
    _youtubeController?.dispose();
    super.dispose();
  }

  Future<void> _loadPost({bool forceRefresh = false}) async {
    try {
      PostModel? updatedPost;
      if (forceRefresh) {
        // Force fetch from server to bypass cache
        final doc = await FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.post.id)
            .get(const GetOptions(source: Source.server));
        if (doc.exists) {
          updatedPost = PostModel.fromFirestore(doc);
        }
      } else {
        updatedPost = await _postRepository.getPostById(widget.post.id);
      }
      
      if (updatedPost != null && mounted) {
        setState(() {
          _currentPost = updatedPost;
          final likedByList = updatedPost!.likedBy;
          final currentUserId = _authService.currentUser?.uid ?? '';
          _isLiked = likedByList.isNotEmpty && likedByList.contains(currentUserId);
          // 댓글 수 동기화
          _commentCount = updatedPost.comments;
        });
        _checkScrapStatus();
      }
    } catch (e) {
      print('Error loading post: $e');
    }
  }

  Future<void> _handleRefresh() async {
    if (_currentPost == null) return;
    
    try {
      // Sync comment count first
      await _postRepository.syncCommentCount(_currentPost!.id);
      
      // Then reload post data from server
      await _loadPost(forceRefresh: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('새로고침 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _toggleLike() async {
    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다')),
      );
      return;
    }

    if (_currentPost == null) return;

    // 1. 내 UI 즉시 변경 (Optimistic Update)
    final previousLiked = _isLiked;
    final previousLikes = _currentPost!.likes;
    final newStatus = !_isLiked;
    final newCount = newStatus ? previousLikes + 1 : previousLikes - 1;
    
    setState(() {
      _isLiked = newStatus;
      _currentPost = _currentPost!.copyWith(
        likes: newCount,
        likedBy: newStatus
            ? [..._currentPost!.likedBy, user.uid]
            : _currentPost!.likedBy.where((id) => id != user.uid).toList(),
      );
    });

    // 2. 📡 전역 방송 송출 (다른 화면들도 다 바꿔라!)
    _likeSyncService.updateLike(_currentPost!.id, newStatus, newCount);

    // 3. 서버 요청 (실패 시 롤백)
    try {
      await _postRepository.toggleLike(_currentPost!.id, user.uid, previousLiked);
      // 성공 시 리로드 없음 (optimistic UI 유지)
    } catch (e) {
      // 에러 발생 시 롤백
      setState(() {
        _isLiked = previousLiked;
        _currentPost = _currentPost!.copyWith(
          likes: previousLikes,
          likedBy: previousLiked
              ? [..._currentPost!.likedBy, user.uid]
              : _currentPost!.likedBy.where((id) => id != user.uid).toList(),
        );
      });
      // 롤백 상태도 방송
      _likeSyncService.updateLike(_currentPost!.id, previousLiked, previousLikes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류가 발생했습니다: $e')),
      );
    }
  }

  Future<void> _pickCommentImage() async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      
      if (pickedFile == null) return;
      
      setState(() {
        _commentImageFile = File(pickedFile.path);
        _isUploadingCommentImage = true;
      });
      
      // Upload image to Firebase Storage
      final user = _authService.currentUser;
      if (user == null) return;
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref().child('comment_images/${user.uid}/$timestamp.jpg');
      await ref.putFile(_commentImageFile!);
      final url = await ref.getDownloadURL();
      
      if (mounted) {
        setState(() {
          _commentImageUrl = url;
          _isUploadingCommentImage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploadingCommentImage = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 업로드 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _submitComment(String? parentCommentId, {String? replyText}) async {
    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다')),
      );
      return;
    }

    final content = parentCommentId != null
        ? (replyText ?? '')
        : _commentController.text.trim();

    if (content.isEmpty && _commentImageUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('댓글 내용 또는 사진을 입력해주세요')),
      );
      return;
    }

    // [Safety] Profanity filter - block upload if text contains bad words
    if (content.isNotEmpty) {
      final badWord = ProfanityFilter().containsProfanity(content);
      if (badWord != null) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('부적절한 내용'),
              content: const Text(
                '입력한 내용에 부적절한 표현이 포함되어 있습니다.\n수정 후 다시 시도해주세요.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('확인'),
                ),
              ],
            ),
          );
        }
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String authorName = user.displayName ?? '익명';
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          final userData = userDoc.data();
          authorName = userData?['displayName'] as String? ?? authorName;
        }
      } catch (e) {
        print('Error fetching user displayName: $e');
      }

      // Ensure authorId is set to current user's UID for querying user's comments
      final currentUserId = user.uid;
      
      final comment = CommentModel(
        id: '',
        postId: _currentPost!.id,
        userId: currentUserId,
        authorId: currentUserId, // Required: authorId must be set for getUserComments to work
        authorName: authorName,
        authorProfileImage: null,
        content: content,
        imageUrl: parentCommentId != null ? null : _commentImageUrl, // 답글에는 이미지 없음
        parentCommentId: parentCommentId,
        likes: 0,
        likedBy: [],
        createdAt: DateTime.now(),
      );

      await _commentRepository.createComment(comment);
      
      // ⭐ 핵심: 댓글 수 즉시 갱신 (최상위 댓글인 경우에만)
      if (parentCommentId == null) {
        setState(() {
          _commentCount++;
        });
        _commentController.clear();
        setState(() {
          _commentImageFile = null;
          _commentImageUrl = null;
        });
        // 키보드 닫기
        FocusScope.of(context).unfocus();
      }
      
      // 댓글 작성 후에는 스크롤 위치 유지를 위해 리로드하지 않음
      // StreamBuilder가 자동으로 업데이트됨
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('댓글 작성 중 오류가 발생했습니다: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteComment(String commentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('댓글 삭제'),
        content: const Text('정말로 이 댓글을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _commentRepository.deleteComment(commentId, _currentPost!.id);
        // ⭐ 핵심: 댓글 수 즉시 감소 (최상위 댓글인 경우에만)
        // 대댓글은 카운트에 포함되지 않으므로, 최상위 댓글 삭제 시에만 감소
        // 실제로는 _loadPost에서 최신 데이터를 가져오지만, 즉시 반영을 위해 감소
        setState(() {
          if (_commentCount > 0) {
            _commentCount--;
          }
        });
        await _loadPost();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('댓글 삭제 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _editPost() async {
    if (_currentPost == null) return;
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditPostScreen(post: _currentPost!),
      ),
    );

    // If post was updated, reload the post
    if (result == true && mounted) {
      await _loadPost();
    }
  }

  Future<void> _deletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('게시글 삭제'),
        content: const Text('정말로 이 게시글을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        setState(() {
          _isLoading = true;
        });
        
        // Delete associated meal log by postId
        try {
          await MealLogRepository().deleteMealLogByPostId(_currentPost!.id);
          print('Meal log deleted for postId: ${_currentPost!.id}');
        } catch (e) {
          print('Error deleting meal log: $e');
          // Continue with post deletion even if meal log deletion fails
        }
        
        // Delete post
        await _postRepository.deletePost(_currentPost!.id);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('게시글이 삭제되었습니다')),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('게시글 삭제 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  /// [Safety] Show Report/Block BottomSheet for the post (target = post author)
  void _showPostMoreBottomSheet(BuildContext context) {
    final user = _authService.currentUser;
    if (user == null || _currentPost == null) return;
    if (user.uid == _currentPost!.userId) return;
    _showReportBlockBottomSheet(
      context: context,
      targetUid: _currentPost!.userId,
      contentId: _currentPost!.id,
      type: 'post',
      onBlocked: () => Navigator.pop(context),
    );
  }

  /// 신고 사유 선택 후 확인 시 선택된 사유 문자열 반환, 취소 시 null
  Future<String?> _showReportReasonDialog(BuildContext context) async {
    const reasons = [
      ('spam', '스팸'),
      ('inappropriate', '부적절한 콘텐츠'),
      ('hate', '혐오 발언'),
      ('privacy', '개인정보 유출'),
      ('other', '기타'),
    ];
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '신고 사유를 선택해주세요',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...reasons.map((e) => ListTile(
                title: Text(e.$2),
                onTap: () => Navigator.pop(ctx, e.$1),
              )),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [Safety] Shared BottomSheet for Report and Block options
  void _showReportBlockBottomSheet({
    required BuildContext context,
    required String targetUid,
    required String contentId,
    required String type,
    VoidCallback? onBlocked,
  }) {
    final user = _authService.currentUser;
    if (user == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('신고하기', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () async {
                Navigator.pop(context);
                final reasonKey = await _showReportReasonDialog(context);
                if (reasonKey == null || !mounted) return;
                final reasonLabels = {
                  'spam': '스팸',
                  'inappropriate': '부적절한 콘텐츠',
                  'hate': '혐오 발언',
                  'privacy': '개인정보 유출',
                  'other': '기타',
                };
                final reasonText = reasonLabels[reasonKey] ?? reasonKey;
                try {
                  await _safetyService.report(
                    reporterUid: user.uid,
                    targetUid: targetUid,
                    contentId: contentId,
                    type: type,
                    reason: reasonText,
                  );
                  if (type == 'post') {
                    await _hiddenContentService.addHiddenPost(contentId);
                    if (mounted) Navigator.pop(context);
                  } else {
                    await _hiddenContentService.addHiddenComment(contentId);
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('신고가 접수되었습니다. 해당 콘텐츠가 숨겨졌습니다.')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('신고 처리 중 오류: $e')),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('사용자 차단', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await _safetyService.blockUser(
                    currentUid: user.uid,
                    targetUid: targetUid,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('사용자를 차단했습니다')),
                    );
                    onBlocked?.call();
                    await _loadPost();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('차단 처리 중 오류: $e')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(int number) {
    return number.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return DateFormat('M월 d일').format(dateTime);
    } else if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            // Image with InteractiveViewer for zoom/pan
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.white,
                            size: 48,
                          ),
                          SizedBox(height: 16),
                          Text(
                            '이미지를 불러올 수 없습니다',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            // Close button
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build header media: 항상 대표 이미지만 표시
  Widget _buildMediaContent() {
    if (_currentPost!.mainImageUrl != null) {
      return GestureDetector(
        onTap: () => _showImageDialog(_currentPost!.mainImageUrl!),
        child: Image.network(
          _currentPost!.mainImageUrl!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[200],
              child: const Center(
                child: Icon(Icons.restaurant, size: 64, color: Colors.grey),
              ),
            );
          },
        ),
      );
    }
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: Icon(Icons.restaurant, size: 64, color: Colors.grey),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _authService.currentUser;
    final isOwner = user != null && _currentPost?.userId == user.uid;

    if (_currentPost == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_youtubeController != null) {
      return YoutubePlayerBuilder(
        // [전체화면 진입] 자연스럽게 가로 모드 허용 (패키지 내부 로직과 충돌 방지)
        onEnterFullScreen: () {
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        },
        // [전체화면 탈출] 세로 모드로 복구 및 상태바 복원
        onExitFullScreen: () {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        },
        player: YoutubePlayer(
          controller: _youtubeController!,
          showVideoProgressIndicator: true,
          progressIndicatorColor: Colors.amber,
          progressColors: const ProgressBarColors(
            playedColor: Colors.amber,
            handleColor: Colors.amberAccent,
          ),
          // onReady: 회전 관련 로직 제거 (패키지 기본 동작 존중)
        ),
        builder: (context, player) {
          // ⭐ builder가 준 player를 그대로 전달 (직접 YoutubePlayer 생성 시 리빌드/회전 시 전체화면 해제됨)
          return _buildScaffold(context, theme, user, isOwner, videoPlayer: player);
        },
      );
    }
    return _buildScaffold(context, theme, user, isOwner, videoPlayer: null);
  }

  Widget _buildScaffold(
    BuildContext context,
    ThemeData theme,
    dynamic user,
    bool isOwner, {
    Widget? videoPlayer,
  }) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: StreamBuilder<DocumentSnapshot>(
        stream: user != null ? _userRepository.streamUser(user.uid) : null,
        builder: (context, userSnap) {
          final userData = userSnap.data?.data() as Map<String, dynamic>?;
          final blockedIds = userSnap.hasData && userData != null
              ? ((userData['blockedUserIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[])
              : <String>[];
          if (blockedIds.contains(_currentPost!.userId)) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.block, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      '차단한 사용자의 게시글입니다',
                      style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('돌아가기'),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
        onRefresh: _handleRefresh,
        child: CustomScrollView(
          key: const PageStorageKey('post_detail_scroll'),
          slivers: [
          // App Bar: 항상 대표 이미지
          SliverAppBar(
            expandedHeight: MediaQuery.of(context).size.width * 3 / 4, // 4:3
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: _buildMediaContent(),
            ),
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              // More (Report / Block) - show only for non-owners
              if (!isOwner)
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.more_horiz, color: Colors.white, size: 20),
                  ),
                  onPressed: _isLoading ? null : () => _showPostMoreBottomSheet(context),
                  tooltip: '더보기',
                ),
              // Share Button
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.share, color: Colors.white, size: 20),
                ),
                onPressed: _isLoading ? null : _sharePost,
                tooltip: '공유하기',
              ),
              // Scrap Button
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isScrapped ? Icons.bookmark : Icons.bookmark_border,
                    color: _isScrapped ? Colors.amber : Colors.white,
                    size: 20,
                  ),
                ),
                onPressed: _isLoading ? null : _toggleScrap,
                tooltip: _isScrapped ? '스크랩 취소' : '스크랩',
              ),
              if (isOwner) ...[
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit_outlined, color: Colors.white, size: 20),
                  ),
                  onPressed: _isLoading ? null : _editPost,
                  tooltip: '수정',
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
                  ),
                  onPressed: _isLoading ? null : _deletePost,
                  tooltip: '삭제',
                ),
              ],
            ],
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Author & Time
                  Row(
                    children: [
                      // Avatar (Clickable)
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfileScreen(
                                userId: _currentPost!.userId,
                                userName: _currentPost!.authorName,
                                userImageUrl: _currentPost!.authorProfileImage,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                theme.colorScheme.primary,
                                theme.colorScheme.secondary,
                              ],
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              _currentPost!.authorName.isNotEmpty ? _currentPost!.authorName[0] : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Author name (Clickable)
                            InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => UserProfileScreen(
                                      userId: _currentPost!.userId,
                                      userName: _currentPost!.authorName,
                                      userImageUrl: _currentPost!.authorProfileImage,
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  _currentPost!.authorName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              _formatTimestamp(_currentPost!.createdAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Content Description
                  Text(
                    _currentPost!.content,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 1.6,
                      color: Colors.grey[900],
                    ),
                  ),

                  // 조리시간 · 인분 (있을 때만)
                  if ((_currentPost!.cookingTime != null && _currentPost!.cookingTime! > 0) ||
                      _currentPost!.servings > 1) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        if (_currentPost!.cookingTime != null && _currentPost!.cookingTime! > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.orange.shade200,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.schedule,
                                  size: 18,
                                  color: Colors.orange.shade700,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${_currentPost!.cookingTime}분',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_currentPost!.servings > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.teal.shade200,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.restaurant,
                                  size: 18,
                                  color: Colors.teal.shade700,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${_currentPost!.servings}인분',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.teal.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                  
                  // Tags
                  if (_currentPost!.tags.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: _currentPost!.tags.map((tag) {
                        final displayText = tag.startsWith('#') ? tag : '#$tag';
                        return Chip(
                          label: Text(
                            displayText,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[800],
                            ),
                          ),
                          backgroundColor: Colors.grey[200],
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                  ],
                  
                  const SizedBox(height: 24),

                  // Like & Comment Actions
                  Row(
                    children: [
                      InkWell(
                        onTap: _toggleLike,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _isLiked
                                ? theme.colorScheme.primaryContainer
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isLiked ? Icons.favorite : Icons.favorite_border,
                                color: _isLiked
                                    ? Colors.red
                                    : Colors.grey[600],
                                size: 20,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatNumber(_currentPost!.likes),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _isLiked
                                      ? Colors.red
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.comment_outlined,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatNumber(_commentCount),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Savings Banner
                  if (_currentPost!.savedAmount > 0)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.secondary,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '💰',
                            style: const TextStyle(fontSize: 32),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '이 요리로 ${_formatNumber(_currentPost!.savedAmount)}원을 아꼈어요!',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_currentPost!.deliveryMenuName != null && _currentPost!.servings > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${_currentPost!.deliveryMenuName} ${_currentPost!.servings}인분 기준',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (_currentPost!.savedAmount > 0) const SizedBox(height: 24),

                  // Ingredients Section with Quantity
                  if (_currentPost!.ingredients.isNotEmpty) ...[
                    Text(
                      '식재료',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[900],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        children: _currentPost!.ingredients.asMap().entries.map((entry) {
                          final index = entry.key;
                          final ingredient = entry.value;
                          final amountText = ingredient.displayAmount;
                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    // 재료 이름
                                    Expanded(
                                      child: Text(
                                        ingredient.name,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey[900],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // 수량/단위 (자유 텍스트)
                                    if (amountText.isNotEmpty)
                                      Text(
                                        amountText,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    // 쿠팡 검색 버튼
                                    IconButton(
                                      icon: Icon(
                                        Icons.shopping_cart_checkout,
                                        color: Colors.red[600],
                                        size: 20,
                                      ),
                                      onPressed: () => _searchOnCoupang(ingredient.name),
                                      tooltip: '쿠팡에서 최저가 검색',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ),
                              if (index < _currentPost!.ingredients.length - 1)
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: Colors.grey[200],
                                ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Recipe Steps Section
                  if (_currentPost!.recipeSteps.isNotEmpty) ...[
                    Text(
                      '조리 순서',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[900],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._currentPost!.recipeSteps.asMap().entries.map((entry) {
                      final index = entry.key;
                      final step = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey[200]!,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                step,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.5,
                                  color: Colors.grey[900],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                  ],

                  // 동영상 레시피 섹션 (동영상이 있을 때만)
                  if (videoPlayer != null) ...[
                    Text(
                      '동영상 레시피',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[900],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: videoPlayer,
                        ),
                      ),
                    ),
                  ],

                  // 조리 팁 (데이터가 있을 때만 표시)
                  if (_currentPost!.cookingTips != null &&
                      _currentPost!.cookingTips!.trim().isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '💡',
                                style: TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '조리 팁',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber[900],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _currentPost!.cookingTips!,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[900],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Comments Section
                  Divider(),
                  const SizedBox(height: 16),
                  Text(
                    '댓글 ${_formatNumber(_commentCount)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[900],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Comment Input
                  Column(
                    children: [
                      if (_commentImageUrl != null) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          height: 100,
                          width: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  _commentImageUrl!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  color: Colors.white,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(24, 24),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _commentImageUrl = null;
                                      _commentImageFile = null;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      Row(
                        children: [
                          IconButton(
                            onPressed: _isUploadingCommentImage ? null : _pickCommentImage,
                            icon: Icon(
                              Icons.add_photo_alternate,
                              color: _isUploadingCommentImage
                                  ? Colors.grey
                                  : theme.colorScheme.primary,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _commentController,
                              decoration: InputDecoration(
                                hintText: '댓글을 입력하세요...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.primary,
                                    width: 2,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                              maxLines: null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _isLoading ? null : () => _submitComment(null),
                            icon: Icon(
                              Icons.send,
                              color: _isLoading
                                  ? Colors.grey
                                  : theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Comments List (filtered by blocked users)
                  StreamBuilder<DocumentSnapshot>(
                    stream: user != null ? _userRepository.streamUser(user.uid) : null,
                    builder: (context, userSnap) {
                      final userData = userSnap.data?.data() as Map<String, dynamic>?;
                      final blockedIds = userSnap.hasData && userData != null
                          ? ((userData['blockedUserIds'] as List<dynamic>?)
                                  ?.map((e) => e.toString())
                                  .toList() ??
                              <String>[])
                          : <String>[];

                      return StreamBuilder<List<CommentModel>>(
                        stream: _currentPost != null
                            ? _commentRepository.streamComments(_currentPost!.id)
                            : Stream.value(<CommentModel>[]),
                        builder: (context, snapshot) {
                      // 게시물 데이터가 없으면 빈 댓글 메시지 표시
                      if (_currentPost == null) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              '아직 작성된 댓글이 없습니다.',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 14,
                              ),
                            ),
                          ),
                        );
                      }

                      // 1. 에러 체크 우선
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: Colors.red[300],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '댓글을 불러오는 중 오류가 발생했습니다',
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${snapshot.error}',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                          // 2. 데이터 처리
                          final commentsRaw = snapshot.hasData ? snapshot.data! : <CommentModel>[];
                          // [Safety] Filter out comments from blocked users
                          final commentsBlocked = blockedIds.isEmpty
                              ? commentsRaw
                              : commentsRaw.where((c) => !blockedIds.contains(c.userId)).toList();

                          return ListenableBuilder(
                            listenable: _hiddenContentService,
                            builder: (context, _) {
                              // [Report] Filter out comments hidden by user (reported)
                              final comments = commentsBlocked
                                  .where((c) => !_hiddenContentService.isCommentHidden(c.id))
                                  .toList();

                              // 3. 데이터 없음 체크
                              if (comments.isEmpty) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Text(
                                      '아직 작성된 댓글이 없습니다.',
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              return Column(
                                children: comments.map((comment) {
                          return _CommentWidget(
                            key: ValueKey(comment.id),
                            comment: comment,
                            currentUserId: user?.uid,
                            onDeleteComment: _deleteComment,
                            onSubmitReply: (replyText, parentCommentId) async {
                              if (replyText.trim().isNotEmpty) {
                                await _submitComment(parentCommentId, replyText: replyText);
                              }
                            },
                            commentRepository: _commentRepository,
                            postId: _currentPost!.id,
                            onLoadPost: _loadPost,
                            onShowReportBlock: (targetUid, contentId) {
                              _showReportBlockBottomSheet(
                                context: context,
                                targetUid: targetUid,
                                contentId: contentId,
                                type: 'comment',
                                onBlocked: () => _loadPost(),
                              );
                            },
                          );
                        }).toList(),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  
                  // 법적 문구 (쿠팡 파트너스)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '이 포스팅은 쿠팡 파트너스 활동의 일환으로, 이에 따른 일정액의 수수료를 제공받습니다.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
        ),
      );
        },
      ),
    );
  }
}

class _CommentWidget extends StatefulWidget {
  final CommentModel comment;
  final String? currentUserId;
  final void Function(String commentId) onDeleteComment;
  final Function(String, String?) onSubmitReply; // (replyText, parentCommentId)
  final CommentRepository commentRepository;
  final String postId;
  final VoidCallback onLoadPost;
  final void Function(String targetUid, String contentId)? onShowReportBlock;

  const _CommentWidget({
    super.key,
    required this.comment,
    required this.currentUserId,
    required this.onDeleteComment,
    required this.onSubmitReply,
    required this.commentRepository,
    required this.postId,
    required this.onLoadPost,
    this.onShowReportBlock,
  });

  @override
  State<_CommentWidget> createState() => _CommentWidgetState();
}

class _CommentWidgetState extends State<_CommentWidget> {
  bool _isLiked = false;
  bool _showReplies = false;
  bool _isReplying = false; // 독립적인 상태 관리
  final TextEditingController _replyController = TextEditingController(); // 독립적인 컨트롤러

  @override
  void initState() {
    super.initState();
    _isLiked = widget.comment.likedBy.contains(widget.currentUserId ?? '');
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return DateFormat('M월 d일').format(dateTime);
    } else if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }

  Future<void> _toggleLike() async {
    if (widget.currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다')),
      );
      return;
    }

    try {
      await widget.commentRepository.toggleLike(
        widget.comment.id,
        widget.currentUserId!,
        _isLiked,
      );
      setState(() {
        _isLiked = !_isLiked;
      });
      // onLoadPost 제거: optimistic UI 유지
    } catch (e) {
      // 에러 발생 시 롤백
      setState(() {
        _isLiked = !_isLiked;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류가 발생했습니다: $e')),
      );
    }
  }

  void _showImageDialog(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            // Image with InteractiveViewer for zoom/pan
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.white,
                            size: 48,
                          ),
                          SizedBox(height: 16),
                          Text(
                            '이미지를 불러올 수 없습니다',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            // Close button
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOwner = widget.currentUserId == widget.comment.userId;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main Content Row: Avatar + Text/Image
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Avatar (Clickable)
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserProfileScreen(
                        userId: widget.comment.authorId,
                        userName: widget.comment.authorName,
                        userImageUrl: widget.comment.authorProfileImage,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.secondary,
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      widget.comment.authorName.isNotEmpty
                          ? widget.comment.authorName[0]
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Center: Expanded content (Author + Time + Text)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Author Name + Time Row
                    Row(
                      children: [
                        // Author name (Clickable)
                        Expanded(
                          child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => UserProfileScreen(
                                  userId: widget.comment.authorId,
                                  userName: widget.comment.authorName,
                                  userImageUrl: widget.comment.authorProfileImage,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              widget.comment.authorName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                        const SizedBox(width: 6),
                        Text(
                          _formatTimestamp(widget.comment.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                        // More (Report/Block) - show for non-owners
                        if (widget.onShowReportBlock != null &&
                            widget.currentUserId != null &&
                            widget.currentUserId != widget.comment.userId)
                          IconButton(
                            icon: Icon(
                              Icons.more_horiz,
                              size: 18,
                              color: Colors.grey[600],
                            ),
                            onPressed: () {
                              widget.onShowReportBlock!(
                                widget.comment.userId,
                                widget.comment.id,
                              );
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Comment Content Text
                    if (widget.comment.isDeleted)
                      Text(
                        '삭제된 댓글입니다.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                        ),
                      )
                    else if (widget.comment.content.isNotEmpty)
                      Text(
                        widget.comment.content,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[900],
                          height: 1.4,
                        ),
                      ),
                  ],
                ),
              ),
              // Right: Image Thumbnail (if exists) - positioned more to the right
              // Don't show image for deleted comments
              if (!widget.comment.isDeleted && widget.comment.imageUrl != null) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _showImageDialog(context, widget.comment.imageUrl!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      widget.comment.imageUrl!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 60,
                          height: 60,
                          color: Colors.grey[200],
                          child: const Icon(
                            Icons.error_outline,
                            color: Colors.grey,
                            size: 24,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // Comment Actions (indented to align with text) + Delete Button
          // Hide actions for deleted comments, but still show replies button
          if (!widget.comment.isDeleted)
            Padding(
              padding: const EdgeInsets.only(left: 40), // Align with text (32 avatar + 8 spacing)
              child: Row(
                children: [
                  InkWell(
                    onTap: _toggleLike,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            size: 16,
                            color: _isLiked ? Colors.red : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.comment.likes}',
                            style: TextStyle(
                              fontSize: 12,
                              color: _isLiked ? Colors.red : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isReplying = !_isReplying;
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.reply, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              '답글',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Spacer(),
                  // Delete Button (if owner)
                  if (isOwner)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: Colors.red[300],
                      onPressed: () => widget.onDeleteComment(widget.comment.id),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  // Show replies button
                  StreamBuilder<List<CommentModel>>(
                    stream: widget.commentRepository.streamReplies(widget.comment.id),
                    builder: (context, snapshot) {
                      final replies = snapshot.data ?? [];
                      if (replies.isEmpty) return const SizedBox.shrink();
                      
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _showReplies = !_showReplies;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Text(
                            '답글 ${replies.length}개 ${_showReplies ? '숨기기' : '보기'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            )
          else
            // For deleted comments, only show replies button
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: StreamBuilder<List<CommentModel>>(
                stream: widget.commentRepository.streamReplies(widget.comment.id),
                builder: (context, snapshot) {
                  final replies = snapshot.data ?? [];
                  if (replies.isEmpty) return const SizedBox.shrink();
                  
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _showReplies = !_showReplies;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        '답글 ${replies.length}개 ${_showReplies ? '숨기기' : '보기'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          // Reply Input (disabled for deleted comments)
          if (_isReplying && !widget.comment.isDeleted) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    decoration: InputDecoration(
                      hintText: '답글을 입력하세요...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    maxLines: null,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () async {
                    if (_replyController.text.trim().isNotEmpty) {
                      await widget.onSubmitReply(_replyController.text.trim(), widget.comment.id);
                      setState(() {
                        _isReplying = false;
                        _replyController.clear();
                      });
                    }
                  },
                  icon: Icon(
                    Icons.send,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _isReplying = false;
                      _replyController.clear();
                    });
                  },
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ],
          // Replies List
          if (_showReplies)
            StreamBuilder<List<CommentModel>>(
              stream: widget.commentRepository.streamReplies(widget.comment.id),
              builder: (context, snapshot) {
                final replies = snapshot.data ?? [];
                if (replies.isEmpty) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.only(left: 16, top: 12),
                  child: Column(
                    children: replies.map((reply) {
                      final isReplyOwner = widget.currentUserId == reply.userId;
                      return Container(
                        key: ValueKey(reply.id),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  reply.authorName.isNotEmpty
                                      ? reply.authorName[0]
                                      : '?',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        reply.authorName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatTimestamp(reply.createdAt),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                      if (isReplyOwner) ...[
                                        const Spacer(),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 14),
                                          color: Colors.red[300],
                                          onPressed: () => widget.onDeleteComment(reply.id),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    reply.content,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[900],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
