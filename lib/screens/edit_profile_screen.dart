import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../repositories/user_repository.dart';
import '../repositories/post_repository.dart';
import '../repositories/community_repository.dart';
import '../repositories/comment_repository.dart';
import '../services/auth_service.dart';

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
  final UserRepository _userRepo = UserRepository();
  final AuthService _auth = AuthService();
  final ImagePicker _imagePicker = ImagePicker();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  File? _pickedImageFile;
  String? _profileImageUrl;
  bool _isLoading = false;
  String? _nicknameError;

  @override
  void initState() {
    super.initState();
    _nicknameController.text = widget.currentDisplayName;
    _profileImageUrl = widget.currentProfileImageUrl;
    _nicknameController.addListener(_validateNickname);
  }

  @override
  void dispose() {
    _nicknameController.removeListener(_validateNickname);
    _nicknameController.dispose();
    super.dispose();
  }

  void _validateNickname() {
    final value = _nicknameController.text.trim();
    if (value.isEmpty) {
      setState(() => _nicknameError = '닉네임을 입력해주세요.');
      return;
    }
    if (value.length < 2 || value.length > 8) {
      setState(() => _nicknameError = '닉네임은 2자 이상 8자 이하여야 합니다.');
      return;
    }
    if (!_nicknameRegex.hasMatch(value)) {
      setState(() => _nicknameError = '한글, 영문, 숫자만 사용할 수 있습니다. (특수문자·공백 불가)');
      return;
    }
    setState(() => _nicknameError = null);
  }

  bool get _isFormValid {
    final value = _nicknameController.text.trim();
    if (value.isEmpty || value.length < 2 || value.length > 8) return false;
    if (!_nicknameRegex.hasMatch(value)) return false;
    return true;
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
    _validateNickname();
    if (!_isFormValid) return;

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final displayName = _nicknameController.text.trim();
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
    final hasImage = _pickedImageFile != null || (_profileImageUrl != null && _profileImageUrl!.isNotEmpty);

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
                    // 프로필 사진
                    Center(
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircleAvatar(
                              radius: 56,
                              backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.5),
                              backgroundImage: _pickedImageFile != null
                                  ? FileImage(_pickedImageFile!)
                                  : (hasImage && _profileImageUrl != null
                                      ? NetworkImage(_profileImageUrl!)
                                      : null),
                              child: _pickedImageFile == null && (!hasImage || _profileImageUrl == null)
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
                    TextFormField(
                      controller: _nicknameController,
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
                      onChanged: (_) => _validateNickname(),
                    ),
                    if (_nicknameError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _nicknameError!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),

                    // 저장 버튼
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isFormValid ? _save : null,
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
