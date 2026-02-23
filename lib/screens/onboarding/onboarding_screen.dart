import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../repositories/user_repository.dart';
import '../../services/auth_service.dart';
import '../../utils/profanity_filter.dart';
import '../../screens/main_navigation_screen.dart';

/// 닉네임 규칙: 2~8자, 한글·영문·숫자만 (프로필 수정과 동일)
final RegExp _nicknameRegex = RegExp(r'^[가-힣a-zA-Z0-9]{2,8}$');

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _nicknameController = TextEditingController();
  final FocusNode _nicknameFocusNode = FocusNode();

  int _currentPage = 0;
  String _nickname = '';
  String? _nicknameError; // 형식·비속어·중복 검사 시 표시
  bool _nicknameVerified = false; // '중복 확인' 통과 여부
  bool _isCheckingDuplicate = false; // 중복 확인 요청 중
  String? _selectedType; // 'housewife' or 'single'
  bool _isUpdating = false;

  final AuthService _authService = AuthService();
  final UserRepository _userRepo = UserRepository();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    // Auto-focus nickname field when step 1 loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _nicknameFocusNode.requestFocus();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nicknameController.dispose();
    _nicknameFocusNode.dispose();
    super.dispose();
  }

  /// '중복 확인' 버튼: 형식·비속어·중복 검사 후 상태 메시지 표시
  Future<void> _checkDuplicate() async {
    FocusScope.of(context).unfocus();
    final value = _nickname.trim();
    setState(() {
      _nicknameError = null;
      _nicknameVerified = false;
      _isCheckingDuplicate = true;
    });

    if (value.isEmpty) {
      setState(() {
        _nicknameError = '닉네임을 입력해주세요.';
        _isCheckingDuplicate = false;
      });
      return;
    }
    if (value.length < 2 || value.length > 8) {
      setState(() {
        _nicknameError = '닉네임은 2자 이상 8자 이하여야 합니다.';
        _isCheckingDuplicate = false;
      });
      return;
    }
    if (!_nicknameRegex.hasMatch(value)) {
      setState(() {
        _nicknameError = '한글, 영문, 숫자만 사용할 수 있습니다. (특수문자·공백 불가)';
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

    final user = _authService.currentUser;
    if (user != null) {
      final isTaken = await _userRepo.isDisplayNameTaken(value, excludeUid: user.uid);
      if (!mounted) return;
      if (isTaken) {
        setState(() {
          _nicknameError = '이미 사용 중인 닉네임입니다.';
          _isCheckingDuplicate = false;
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _nicknameError = null;
      _nicknameVerified = true;
      _isCheckingDuplicate = false;
    });
  }

  /// 다음 단계로 이동 (이미 _nicknameVerified 된 경우만 호출)
  Future<void> _nextStep(BuildContext context) async {
    FocusScope.of(context).unfocus();
    if (_currentPage != 0) return;
    if (!_nicknameVerified) return;
    setState(() {
      _nicknameError = null;
      _currentPage = 1;
    });
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _selectType(String type) {
    setState(() {
      _selectedType = type;
    });
  }

  Future<void> _completeOnboarding() async {
    if (_selectedType == null) return;

    setState(() {
      _isUpdating = true;
    });

    try {
      final user = _authService.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      final displayName = _nickname.trim();

      if (displayName.length < 2 || displayName.length > 8) {
        setState(() => _isUpdating = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('닉네임은 2자 이상 8자 이하여야 합니다.'), backgroundColor: Colors.orange),
          );
        }
        return;
      }
      if (!_nicknameRegex.hasMatch(displayName)) {
        setState(() => _isUpdating = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('한글, 영문, 숫자만 사용할 수 있습니다.'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      final badWord = ProfanityFilter().containsProfanity(displayName);
      if (badWord != null) {
        setState(() => _isUpdating = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('닉네임에 부적절한 표현이 포함되어 있습니다. 다른 닉네임을 사용해 주세요.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final isTaken = await _userRepo.isDisplayNameTaken(displayName, excludeUid: user.uid);
      if (isTaken) {
        setState(() => _isUpdating = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('이미 사용 중인 닉네임입니다. 다른 닉네임을 입력해 주세요.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final userDocRef = _firestore.collection('users').doc(user.uid);
      final userDoc = await userDocRef.get();

      if (!userDoc.exists) {
        await userDocRef.set({
          'uid': user.uid,
          'email': user.email ?? '',
          'displayName': displayName,
          'displayNameLower': displayName.toLowerCase(),
          'userType': _selectedType,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await userDocRef.update({
          'displayName': displayName,
          'displayNameLower': displayName.toLowerCase(),
          'userType': _selectedType,
        });
      }

      try {
        await user.updateDisplayName(displayName);
        await user.reload();
      } catch (e) {
        print('Error updating Firebase Auth displayName: $e');
      }

      if (mounted) {
        final initialHomeTabIndex = _selectedType == 'single' ? 1 : 0;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) =>
                MainNavigationScreen(initialHomeTabIndex: initialHomeTabIndex),
          ),
        );
      }
    } catch (e) {
      print('Error completing onboarding: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (_currentPage + 1) / 2;

    return PopScope(
      canPop: _currentPage == 0,
      onPopInvoked: (didPop) {
        if (!didPop && _currentPage > 0) {
          _pageController.previousPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
          setState(() {
            _currentPage = 0;
          });
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          // LayoutBuilder를 사용하여 화면 크기 변화에 대응
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                children: [
                  // Top Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            if (_currentPage > 0)
                              IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () {
                                  _pageController.previousPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                  setState(() {
                                    _currentPage = 0;
                                  });
                                },
                                color: Colors.grey[700],
                              )
                            else
                              const SizedBox(height: 48), // 뒤로가기 없을 때 높이 유지
                            const Spacer(),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.primary,
                            ),
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // PageView Content
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildStep1(context, theme),
                        _buildStep2(theme),
                      ],
                    ),
                  ),

                  // Bottom Button
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isUpdating
                            ? null
                            : (_currentPage == 0
                                  ? (_nicknameVerified ? () async => await _nextStep(context) : null)
                                  : (_selectedType != null
                                        ? _completeOnboarding
                                        : null)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isUpdating
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                _currentPage == 0 ? '다음' : '시작하기',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // Step 1: 닉네임 입력 (스크롤 가능하도록 수정)
  Widget _buildStep1(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            Text(
              '앱에서 사용할\n닉네임을 알려주세요.',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900],
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '다른 사용자에게 보여질 이름이에요',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 48),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _nicknameController,
                    focusNode: _nicknameFocusNode,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: '닉네임을 입력하세요',
                      hintStyle: TextStyle(fontSize: 20, color: Colors.grey[400]),
                      border: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _nickname = value;
                        _nicknameError = null;
                        _nicknameVerified = false; // 입력 변경 시 확인 초기화
                      });
                    },
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (_nickname.trim().isNotEmpty) _checkDuplicate();
                    },
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
            const SizedBox(height: 8),
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
                '사용 가능한 닉네임입니다.',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            // 키보드에 가려지지 않도록 하단 여백 추가
            const SizedBox(height: 200),
          ],
        ),
      ),
    );
  }

  // Step 2: 타입 선택 (스크롤 가능하도록 수정)
  Widget _buildStep2(ThemeData theme) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            Text(
              '어떤 요리를\n주로 하시나요?',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900],
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '맞춤형 레시피를 추천해드릴게요',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 48),
            Row(
              children: [
                Expanded(
                  child: _TypeSelectionCard(
                    title: '현실 집밥',
                    subtitle: '주부',
                    icon: Icons.restaurant,
                    isSelected: _selectedType == 'housewife',
                    onTap: () => _selectType('housewife'),
                    theme: theme,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _TypeSelectionCard(
                    title: '자취 밥상',
                    subtitle: '자취생',
                    icon: Icons.fastfood,
                    isSelected: _selectedType == 'single',
                    onTap: () => _selectType('single'),
                    theme: theme,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40), // 하단 여백 확보
          ],
        ),
      ),
    );
  }
}

class _TypeSelectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final ThemeData theme;

  const _TypeSelectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer.withOpacity(0.3)
              : Colors.white,
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 48,
                color: isSelected
                    ? theme.colorScheme.primary
                    : Colors.grey[600],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.grey[900],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
