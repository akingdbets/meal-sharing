import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth_wrapper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false; // 로딩 상태 관리
  bool _isTermsAccepted = false; // 이용약관 동의 상태

  // 🍎 애플 로그인 핸들러
  void _handleAppleLogin() async {
    if (!_isTermsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('서비스 이용약관 및 커뮤니티 가이드라인에 동의해주세요.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // AuthService의 애플 로그인 호출
      final userCredential = await AuthService().signInWithApple();

      if (userCredential != null && mounted) {
        // 성공 시 AuthWrapper로 이동 → 온보딩 여부 검사 후 온보딩/메인 화면 분기
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthWrapper()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('애플 로그인 실패: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = AuthService();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              // 상단 여백
              const Spacer(flex: 1),

              // Branding Area
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.rice_bowl,
                    size: 80,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '오늘의 식탁',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 28,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '현실 집밥부터 자취 생존 식단까지',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 48),

              // 로딩 중이면 뱅글뱅글, 아니면 컨텐츠 표시
              if (_isLoading)
                const CircularProgressIndicator()
              else
                Column(
                  children: [
                    // 이용약관 동의 체크박스
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isTermsAccepted ? theme.colorScheme.primary : Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _isTermsAccepted = !_isTermsAccepted;
                          });
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _isTermsAccepted,
                                onChanged: (value) {
                                  setState(() {
                                    _isTermsAccepted = value ?? false;
                                  });
                                },
                                activeColor: theme.colorScheme.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '[필수] 서비스 이용약관 및 커뮤니티 가이드라인 동의',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '* 부적절한 게시글은 관리자에 의해 강제 삭제될 수 있습니다.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red[400],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 🍎 Apple 로그인 (iOS 등에서만 표시, Android에서는 숨김)
                    if (kIsWeb || !Platform.isAndroid) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _handleAppleLogin,
                          icon: const Icon(
                            Icons.apple,
                            size: 24,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Apple로 계속하기',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 카카오 로그인 버튼
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading
                            ? null
                            : () async {
                                if (!_isTermsAccepted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('서비스 이용약관 및 커뮤니티 가이드라인에 동의해주세요.')),
                                  );
                                  return;
                                }
                                setState(() => _isLoading = true);
                                try {
                                  final userCredential = await AuthService().signInWithKakao();
                                  if (!mounted) return;
                                  if (userCredential != null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('카카오 로그인 성공'),
                                          backgroundColor: Colors.green,
                                        ),
                                    );
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute(builder: (_) => const AuthWrapper()),
                                      (route) => false,
                                    );
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('카카오 로그인 실패: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                } finally {
                                  if (mounted) setState(() => _isLoading = false);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFEE500),
                          foregroundColor: const Color(0xFF3C1E1E),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.chat_bubble, size: 20),
                            SizedBox(width: 8),
                            Text(
                              '카카오로 3초 만에 시작하기',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 네이버 로그인 버튼
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading
                            ? null
                            : () async {
                                if (!_isTermsAccepted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('서비스 이용약관 및 커뮤니티 가이드라인에 동의해주세요.')),
                                  );
                                  return;
                                }
                                setState(() => _isLoading = true);
                                try {
                                  final userCredential = await AuthService().signInWithNaver();
                                  if (!mounted) return;
                                  if (userCredential != null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('네이버 로그인 성공'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute(builder: (_) => const AuthWrapper()),
                                      (route) => false,
                                    );
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('네이버 로그인 실패: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                } finally {
                                  if (mounted) setState(() => _isLoading = false);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF03C75A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Center(
                                child: Text(
                                  'N',
                                  style: TextStyle(
                                    color: Color(0xFF03C75A),
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '네이버로 시작하기',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Google Login Button (실제 작동)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton(
                        onPressed: () async {
                          if (!_isTermsAccepted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('서비스 이용약관 및 커뮤니티 가이드라인에 동의해주세요.')),
                            );
                            return;
                          }

                          // 1. 로딩 시작
                          setState(() {
                            _isLoading = true;
                          });

                          try {
                            // 2. 구글 로그인 시도
                            final result = await authService.signInWithGoogle();

                            if (result != null && context.mounted) {
                              // 3. 성공 시 AuthWrapper로 이동 → 온보딩 여부 검사 후 온보딩/메인 화면 분기
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => const AuthWrapper(),
                                ),
                                (route) => false,
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('로그인 실패: ${e.toString()}'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } finally {
                            // 4. 로딩 종료
                            if (mounted) {
                              setState(() {
                                _isLoading = false;
                              });
                            }
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          side: BorderSide(color: Colors.grey[300]!, width: 1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            _GoogleLogoIcon(size: 20),
                            SizedBox(width: 12),
                            Text(
                              'Google로 시작하기',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 32),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}

/// 구글 G 로고 아이콘
class _GoogleLogoIcon extends StatelessWidget {
  final double size;

  const _GoogleLogoIcon({this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          'G',
          style: TextStyle(
            fontSize: size * 1.1,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF4285F4), // Google blue
            height: 1,
          ),
        ),
      ),
    );
  }
}
