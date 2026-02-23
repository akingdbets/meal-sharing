/// Utility class for filtering profanity in user-generated content.
/// Used before creating posts, comments, nicknames, etc. to maintain a safe community.
class ProfanityFilter {
  static final ProfanityFilter _instance = ProfanityFilter._internal();
  factory ProfanityFilter() => _instance;
  ProfanityFilter._internal();

  /// List of common Korean bad words (비속어/욕설).
  static const List<String> _badWords = [
    '시발', '씨발', 'ㅅㅂ', 'ㅆㅂ', '씨팔',
    '병신', 'ㅂㅅ', '븅신', '병쉰',
    '지랄', 'ㅈㄹ', '지럴',
    '좆', 'ㅈㅇ', '좃',
    '니애미', '니엄마', '니애비', '니아비',
    '느금', '느금마', '느금빠',
    '염병', '엠병', '엠븽',
    '닥쳐', '닭쳐',
    '꺼져', '꺼지',
    '새끼', '쉐끼', 'ㅅㄲ',
    '니년', '니놈',
    '또라이', '섹스', '보지', '자지', '썅',
  ];

  /// Normalize text for detection: remove spaces so "시 발" is caught.
  static String _normalizeForCheck(String text) {
    final lower = text.toLowerCase().trim();
    return lower
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[\.\,\!\?\*\_\-]+'), '');
  }

  /// Check if text contains any profanity.
  /// Uses normalized text (no spaces) so evasions like "시 발" are caught.
  String? containsProfanity(String text) {
    if (text.isEmpty) return null;
    final normalized = _normalizeForCheck(text);
    final rawLower = text.toLowerCase().trim();
    for (final word in _badWords) {
      if (normalized.contains(word) || rawLower.contains(word)) {
        return word;
      }
    }
    return null;
  }

  /// Returns true if text is safe (no profanity).
  bool isClean(String text) => containsProfanity(text) == null;
}
