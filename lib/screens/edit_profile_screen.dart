import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../repositories/user_repository.dart';
import '../repositories/post_repository.dart';
import '../repositories/community_repository.dart';
import '../repositories/comment_repository.dart';
import '../services/auth_service.dart';
import '../utils/profanity_filter.dart';

/// 닉네임: 2~8자, 한글·영문·숫자만 (특수문자·공백 금지)
final RegExp _nicknameRegex = RegExp(r'^[가-힣a-zA-Z0-9]{2,8}$');

class EditProfileScreen extends StatefulWidget {
  final String currentDisplayName;
  final String? currentProfileImageUrl;

  const EditProfileScreen({
    super.key,
    required this.currentDisplayName,
    this.currentProfileImageUrl,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  final FocusNode _nicknameFocusNode = FocusNode();
  final UserRepository _userRepo = UserRepository();
  final AuthService _auth = AuthService();
  final ImagePicker _imagePicker = ImagePicker();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  File? _pickedImageFile;
  String? _profileImageUrl;
  bool _isLoading = false;
  String? _nicknameError;
  bool _nicknameVerified = false; // '중복 확인' 통과 여부
  bool _isCheckingDuplicate = false;

  @override
  void initState() {
    super.initState();
    _nicknameController.text = widget.currentDisplayName;
    _profileImageUrl = widget.currentProfileImageUrl;
    _nicknameVerified = true; // 초기값이 현재 닉네임이므로 변경 없이 저장 가능
    _nicknameController.addListener(() {
      setState(() {
        final same = _nicknameController.text.trim() == widget.currentDisplayName;
        if (same) _nicknameVerified = true;
        else _nicknameVerified = false;
      });
    });
  }

  @override
  void dispose() {
    _nicknameFocusNode.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  /// 형식 검사만 (에러 메시지용)
  String? _getFormatError() {
    final value = _nicknameController.text.trim();
    if (value.isEmpty) return '닉네임을 입력해주세요.';
    if (value.length < 2 || value.length > 8) return '닉네임은 2자 이상 8자 이하여야 합니다.';
    if (!_nicknameRegex.hasMatch(value)) return '한글, 영문, 숫자만 사용할 수 있습니다. (특수문자·공백 불가)';
    return null;
  }

  bool get _isFormValid {
    final value = _nicknameController.text.trim();
    if (value.isEmpty || value.length < 2 || value.length > 8) return false;
    if (!_nicknameRegex.hasMatch(value)) return false;
    return true;
  }

  /// '중복 확인' 버튼: 형식·비속어·중복 검사 후 상태 메시지 표시
  Future<void> _checkDuplicate() async {
    FocusScope.of(context).unfocus();
    final value = _nicknameController.text.trim();
    setState(() {
      _nicknameError = null;
      _nicknameVerified = false;
      _isCheckingDuplicate = true;
    });

    final formatErr = _getFormatError();
    if (formatErr != null) {
      setState(() {
        _nicknameError = formatErr;
        _isCheckingDuplicate = false;
      });
      return;
    }

    final badWord = ProfanityFilter().containsProfanity(value);
    if (badWord != null) {
      setState(() {
        _nicknameError = '닉네임에 부적절한 표현이 포함되어 있습니다.';
        _isCheckingDuplicate = false;
      });
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _nicknameError = '로그인이 필요합니다.';
        _isCheckingDuplicate = false;
      });
      return;
    }

    final isTaken = await _userRepo.isDisplayNameTaken(value, excludeUid: user.uid);
    if (!mounted) return;
    if (isTaken) {
      setState(() {
        _nicknameError = '이미 사용 중인 닉네임입니다.';
        _isCheckingDuplicate = false;
      });
      return;
    }

    setState(() {
      _nicknameError = null;
      _nicknameVerified = true;
      _isCheckingDuplicate = false;
    });
  }

  void _showProfileImageOptions() {
    showModalBottomSheet<void>(
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
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('갤러리에서 사진 선택'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('기본 이미지로 변경'),
                onTap: () {
                  Navigator.pop(ctx);
                  _setDefaultImage();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setDefaultImage() {
    setState(() {
      _pickedImageFile = null;
      _profileImageUrl = AuthService.defaultProfileImageUrl;
    });
  }

  Future<void> _pickImage() async {
    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 512,
        maxHeight: 512,
      );
      if (picked == null) return;
      setState(() {
        _pickedImageFile = File(picked.path);
        _profileImageUrl = null; // 새로 고른 사진이 우선
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 선택 실패: $e')),
        );
      }
    }
  }

  Future<String?> _uploadProfileImage(String uid) async {
    if (_pickedImageFile == null) return _profileImageUrl;
    try {
      final path = 'profile_images/$uid/avatar.jpg';
      final ref = _storage.ref().child(path);
      await ref.putFile(_pickedImageFile!);
      return await ref.getDownloadURL();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 업로드 실패: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _save() async {
    if (!_isFormValid || !_nicknameVerified) return;

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final displayName = _nicknameController.text.trim();
    setState(() => _isLoading = true);
    try {
      String? imageUrl = _profileImageUrl;
      if (_pickedImageFile != null) {
        final uploaded = await _uploadProfileImage(user.uid);
        if (uploaded == null) {
          setState(() => _isLoading = false);
          return;
        }
        imageUrl = uploaded;
      }
      await _userRepo.updateProfile(
        user.uid,
        displayName: displayName,
        profileImageUrl: imageUrl,
      );
      await _auth.updateDisplayName(displayName);
      // 닉네임 변경 시 해당 유저의 게시물·댓글에 표시되는 이름도 갱신
      try {
        await PostRepository().updateAuthorNameForUser(user.uid, displayName);
        await CommunityRepository().updateAuthorNameForUser(user.uid, displayName);
        await CommunityRepository().updateCommentAuthorNameForUser(user.uid, displayName);
        await CommentRepository().updateAuthorNameForUser(user.uid, displayName);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('프로필은 저장되었으나 일부 게시물/댓글 반영에 실패했습니다: $e')),
          );
        }
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프로필이 저장되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('프로필 편집', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 프로필 사진 (탭 시 갤러리 / 기본 이미지 선택)
                    Center(
                      child: GestureDetector(
                        onTap: _showProfileImageOptions,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircleAvatar(
                              radius: 56,
                              backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.5),
                              backgroundImage: _pickedImageFile != null
                                  ? FileImage(_pickedImageFile!)
                                  : (_profileImageUrl != null &&
                                          _profileImageUrl!.trim().isNotEmpty &&
                                          _profileImageUrl != AuthService.defaultProfileImageUrl)
                                      ? NetworkImage(_profileImageUrl!)
                                      : null,
                              child: _pickedImageFile == null &&
                                      (_profileImageUrl == null ||
                                          _profileImageUrl!.trim().isEmpty ||
                                          _profileImageUrl == AuthService.defaultProfileImageUrl)
                                  ? Icon(Icons.person, size: 56, color: theme.colorScheme.primary)
                                  : null,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        '탭하여 사진 변경',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // 닉네임
                    Text(
                      '닉네임',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _nicknameController,
                            focusNode: _nicknameFocusNode,
                            decoration: InputDecoration(
                              hintText: '2~8자, 한글·영문·숫자만',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              errorBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.red),
                              ),
                            ),
                            onChanged: (_) => setState(() {
                              _nicknameError = null;
                              if (_nicknameController.text.trim() != widget.currentDisplayName) {
                                _nicknameVerified = false;
                              } else {
                                _nicknameVerified = true;
                              }
                            }),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 48,
                          child: FilledButton(
                            onPressed: _isCheckingDuplicate ? null : _checkDuplicate,
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            child: _isCheckingDuplicate
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('중복 확인'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_nicknameError != null)
                      Text(
                        _nicknameError!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else if (_nicknameVerified)
                      Text(
                        _nicknameController.text.trim() == widget.currentDisplayName
                            ? '현재 사용 중인 닉네임입니다.'
                            : '사용 가능한 닉네임입니다.',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    const SizedBox(height: 32),

                    // 저장 버튼
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: (_isFormValid && _nicknameVerified) ? _save : null,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: theme.colorScheme.primary,
                        ),
                        child: const Text('저장'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
