import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../screens/main_navigation_screen.dart';

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
  String? _selectedType; // 'housewife' or 'single'
  bool _isUpdating = false;

  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    // Auto-focus nickname field when step 1 loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nicknameFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nicknameController.dispose();
    _nicknameFocusNode.dispose();
    super.dispose();
  }

  void _nextStep(BuildContext context) {
    // 닉네임 설정 확인 후 키보드 내려서 다음 페이지에서 bottom overflow 방지
    FocusScope.of(context).unfocus();
    if (_currentPage == 0 && _nickname.trim().isNotEmpty) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentPage = 1;
      });
    }
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

      final userDocRef = _firestore.collection('users').doc(user.uid);
      
      // Check if document exists
      final userDoc = await userDocRef.get();
      
      final displayName = _nickname.trim();
      
      if (!userDoc.exists) {
        // Document doesn't exist - create it with set
        await userDocRef.set({
          'uid': user.uid,
          'email': user.email ?? '',
          'displayName': displayName,
          'userType': _selectedType,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        // Document exists - update it
        await userDocRef.update({
          'displayName': displayName,
          'userType': _selectedType,
        });
      }

      // Update Firebase Auth profile to sync displayName
      try {
        await user.updateDisplayName(displayName);
        await user.reload();
      } catch (e) {
        print('Error updating Firebase Auth displayName: $e');
        // Continue even if this fails
      }

      // Navigate to main screen (자취 밥상 선택 시 홈에서 해당 탭이 먼저 보이도록 전달)
      if (mounted) {
        final initialHomeTabIndex = _selectedType == 'single' ? 1 : 0;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => MainNavigationScreen(initialHomeTabIndex: initialHomeTabIndex),
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
          // 이전 단계로 이동
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
        child: Column(
          children: [
            // Top Bar with Back Button and Progress
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                        ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Progress Bar
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
                          ? (_nickname.trim().isNotEmpty ? () => _nextStep(context) : null)
                          : (_selectedType != null ? _completeOnboarding : null)),
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
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
        ),
      ),
      ),
    );
  }

  Widget _buildStep1(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          // Title
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
          // Subtitle
          Text(
            '다른 사용자에게 보여질 이름이에요',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 48),
          // TextField
          TextField(
            controller: _nicknameController,
            focusNode: _nicknameFocusNode,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: '닉네임을 입력하세요',
              hintStyle: TextStyle(
                fontSize: 20,
                color: Colors.grey[400],
              ),
              border: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Colors.grey[300]!,
                  width: 1,
                ),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Colors.grey[300]!,
                  width: 1,
                ),
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
              });
            },
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (_nickname.trim().isNotEmpty) {
                _nextStep(context);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStep2(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          // Title
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
          // Subtitle
          Text(
            '맞춤형 레시피를 추천해드릴게요',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 48),
          // Selection Cards (Horizontal)
          Row(
            children: [
              // Housewife Card
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
              // Single Card
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
          const Spacer(),
        ],
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
            color: isSelected
                ? theme.colorScheme.primary
                : Colors.grey[300]!,
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
