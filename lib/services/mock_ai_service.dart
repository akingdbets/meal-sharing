import 'ingredient_loader.dart';

/// Mock AI Service for ingredient extraction and delivery price lookup
/// This is a placeholder for actual AI integration
class MockAIService {
  static final MockAIService _instance = MockAIService._internal();
  factory MockAIService() => _instance;
  MockAIService._internal();

  // Delivery menu prices (Map of menu name to average price per serving)
  final Map<String, int> _deliveryPrices = {
    // --- 한식 / 식사류 ---
    '김치찌개': 12000, '된장찌개': 11000, '차돌된장찌개': 12500, '부대찌개': 13000,
    '순두부찌개': 10000, '청국장': 10500, '육개장': 11000, '뼈해장국': 11000,
    '감자탕': 15000, '찜닭': 14000, '닭볶음탕': 14000, '제육볶음': 13000,
    '불고기': 15000, '뚝배기불고기': 11500, '오징어볶음': 14000, '낙지볶음': 16000,
    '비빔밥': 10000, '돌솥비빔밥': 11000, '육회비빔밥': 13500, '설렁탕': 11000,
    '곰탕': 12000, '갈비탕': 15000, '도가니탕': 18000, '추어탕': 12000,
    '삼계탕': 17000, '고등어구이': 13000, '삼치구이': 14000, '보리굴비': 18000,
    '간장게장': 25000, '양념게장': 23000, '수육백반': 13000, '국밥': 9500,
    '돼지국밥': 10000, '순대국밥': 10000, '소머리국밥': 12000, '콩나물국밥': 8500,

    // --- 치킨 / 피자 / 양식 ---
    '치킨': 20000, '양념치킨': 21000, '후라이드치킨': 19000, '간장치킨': 21000,
    '순살치킨': 20000, '치즈시즈닝치킨': 22000, '닭강정': 15000, '구운치킨': 20000,
    '파닭': 22000, '피자': 22000, '콤비네이션피자': 21000, '불고기피자': 23000,
    '페퍼로니피자': 20000, '포테이토피자': 23000, '고구마피자': 23000, '쉬림프피자': 26000,
    '치즈피자': 18000, '시카고피자': 25000, '파스타': 15000, '크림파스타': 16000,
    '토마토파스타': 14000, '로제파스타': 16000, '알리오올리오': 14000, '봉골레파스타': 16000,
    '까르보나라': 15500, '라스베가스스테이크': 28000, '함박스테이크': 14000, '돈까스': 12000,
    '치즈돈까스': 14000, '고구마돈까스': 14000, '생선까스': 13000, '리조또': 15000,
    '필라프': 13000, '오므라이스': 11000, '카레': 10000, '새우카레': 12000,

    // --- 일식 / 중식 ---
    '짜장면': 7000, '간짜장': 8500, '짬뽕': 9000, '차돌짬뽕': 12000,
    '볶음밥': 9000, '잡채밥': 10000, '탕수육': 18000, '꿔바로우': 20000,
    '양장피': 30000, '팔보채': 35000, '마파두부': 15000, '중화비빔밥': 10000,
    '초밥': 18000, '모둠초밥': 20000, '연어초밥': 22000, '광어초밥': 22000,
    '회': 35000, '광어회': 35000, '우럭회': 35000, '연어회': 30000,
    '참치회': 50000, '물회': 16000, '우동': 8500, '튀김우동': 10000,
    '라멘': 10000, '돈코츠라멘': 11000, '소유라멘': 10000, '미소라멘': 10500,
    '가츠동': 11000, '규동': 11000, '에비동': 12000, '사케동': 15000,
    '텐동': 14000, '모밀': 9000, '판모밀': 10000, '냉소바': 10000,

    // --- 야식 / 기타 ---
    '족발': 35000, '보쌈': 33000, '불족발': 37000, '냉채족발': 37000,
    '막국수': 9000, '곱창': 16000, '야채곱창': 13000, '소곱창': 22000,
    '막창': 17000, '대창': 18000, '양꼬치': 15000, '닭발': 17000,
    '무뼈닭발': 18000, '오돌뼈': 16000, '껍데기': 12000, '아귀찜': 35000,
    '해물찜': 40000, '마라탕': 12000, '마라상궈': 18000, '훠궈': 25000,
    '샤브샤브': 18000, '월남쌈': 22000, '쌀국수': 11000, '팟타이': 13000,
    '나시고랭': 12000, '분짜': 15000, '타코': 12000, '부리또': 11000,

    // --- 분식 / 간편식 ---
    '떡볶이': 6000, '로제떡볶이': 11000, '마라떡볶이': 12000, '국물떡볶이': 7000,
    '튀김': 7000, '모둠튀김': 8000, '순대': 5500, '어묵': 5000,
    '김밥': 4500, '참치김밥': 5500, '치즈김밥': 5000, '돈까스김밥': 6000,
    '라면': 5500, '떡라면': 6500, '만두라면': 6500, '칼국수': 9000,
    '수제비': 9000, '잔치국수': 7500, '비빔국수': 8500, '쫄면': 8500,
    '냉면': 10000, '물냉면': 10000, '비빔냉면': 10500, '만두': 6500,
    '군만두': 6500, '찐만두': 6500, '햄버거': 8000, '싸이버거세트': 8500,
    '불고기버거세트': 8000, '치즈버거세트': 9000, '수제버거': 12000,

    // --- 디저트 / 음료 ---
    '아메리카노': 4500, '카페라떼': 5000, '바닐라라떼': 5500, '콜드브루': 5500,
    '에이드': 6000, '스무디': 6500, '밀크티': 6000, '빙수': 13000,
    '팥빙수': 12000, '망고빙수': 15000, '크로플': 5000, '와플': 4500,
    '조각케이크': 7000, '마카롱': 3000, '샌드위치': 7500, '베이글': 4500,
  };

  /// Get all ingredient names for autocomplete/search (from IngredientLoader cache).
  /// Returns list in Korean alphabetical order (가나다순).
  List<String> getAllIngredients() {
    return IngredientLoader().allIngredients;
  }

  /// Get unit for an ingredient. Uses IngredientLoader list; default unit is '개'.
  String getUnitForIngredient(String name) {
    if (name.isEmpty) return '개';
    // Unit per ingredient is no longer stored; use default.
    return '개';
  }

  /// Extract ingredients from text using enhanced keyword matching
  /// Returns a list of unique ingredient names found in the text
  /// Supports aliases and partial matches (e.g., "불닭" -> "불닭볶음면", "치즈" -> "모짜렐라치즈")
  List<String> extractIngredients(String text) {
    if (text.isEmpty) return [];

    final foundIngredients = <String>{};
    final lowerText = text.toLowerCase();

    // Enhanced ingredient aliases and mappings for better detection
    final aliasMap = {
      '불닭': '불닭볶음면',
      '치즈': '모짜렐라치즈',
      '스트링치즈': '스트링치즈',
      '모짜': '모짜렐라치즈',
      '모짜렐라': '모짜렐라치즈',
      '계란': '계란',
      '달걀': '계란',
      '라면': '신라면', // Default to 신라면 if just "라면"
      '소세지': '비엔나',
      '비엔나소세지': '비엔나',
      '후랑크': '후랑크소세지',
      '참치': '참치캔',
      '참치캔': '참치캔',
      '스팸': '스팸',
      '햄': '햄',
      '만두': '만두',
      '치킨너겟': '치킨너겟',
      '너겟': '치킨너겟',
      '핫바': '핫바',
      '핫도그': '핫도그',
      '피자': '피자',
      '김말이': '김말이',
      '용가리': '용가리',
      '맛살': '맛살',
      '크래미': '크래미',
      '삼각김밥': '삼각김밥',
      '햇반': '햇반',
      '오뚜기밥': '오뚜기밥',
      '우동사리': '우동사리',
      '라면사리': '라면사리',
      '떡국떡': '떡국떡',
      '떡볶이떡': '떡볶이떡',
    };

    // First, check for aliases and map them to full ingredient names
    for (final aliasEntry in aliasMap.entries) {
      if (lowerText.contains(aliasEntry.key.toLowerCase())) {
        foundIngredients.add(aliasEntry.value);
      }
    }

    // allIngredients를 글자 길이 내림차순으로 정렬 후 매칭 (긴 이름 먼저 → '대패삼겹살'을 '삼겹살'로 잘못 인식 방지)
    final allIngredients = IngredientLoader().allIngredients;
    final sortedByLength = List<String>.from(allIngredients)
      ..sort((a, b) => b.length.compareTo(a.length));

    // 매칭된 구간을 제거해 두어, 짧은 재료가 긴 재료 안에서 중복 매칭되지 않도록 함
    String remainingText = lowerText;

    for (final ingredient in sortedByLength) {
      final lowerIngredient = ingredient.toLowerCase();
      if (lowerIngredient.isEmpty) continue;
      if (foundIngredients.contains(ingredient)) continue;

      if (remainingText.contains(lowerIngredient)) {
        foundIngredients.add(ingredient);
        // 해당 구간을 공백으로 치환해 같은 구간에서 짧은 재료가 다시 매칭되지 않게 함
        remainingText = remainingText.replaceFirst(lowerIngredient, ' ' * lowerIngredient.length);
      }
    }

    return foundIngredients.toList()..sort();
  }

  /// Get delivery price for a menu name
  /// Returns the average delivery price per serving, or 10000 as default
  int getDeliveryPrice(String menuName) {
    if (menuName.isEmpty) return 10000;

    // Try exact match first
    if (_deliveryPrices.containsKey(menuName)) {
      return _deliveryPrices[menuName]!;
    }

    // Try partial match (case-insensitive)
    final lowerMenuName = menuName.toLowerCase();
    for (final entry in _deliveryPrices.entries) {
      if (entry.key.toLowerCase().contains(lowerMenuName) ||
          lowerMenuName.contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }

    // Default price
    return 10000;
  }

  /// Get suggestions for menu names (for Autocomplete)
  List<String> getMenuSuggestions(String query) {
    if (query.isEmpty) {
      return _deliveryPrices.keys.take(10).toList();
    }

    final lowerQuery = query.toLowerCase();
    return _deliveryPrices.keys
        .where((menu) => menu.toLowerCase().contains(lowerQuery))
        .take(10)
        .toList();
  }

  /// Detect a delivery menu keyword from text (e.g. description).
  /// Returns the first matching menu name from _deliveryPrices (longer matches first).
  /// Used for auto-setting the delivery calculator from title/description.
  String? detectDeliveryMenuFromText(String text) {
    if (text.isEmpty) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final lowerText = trimmed.toLowerCase();
    final sortedKeys = _deliveryPrices.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final menuName in sortedKeys) {
      if (lowerText.contains(menuName.toLowerCase())) {
        return menuName;
      }
    }
    return null;
  }

  /// Detect servings from text (e.g. "1인분", "2명", "두 마리").
  /// Returns the first detected number, or null.
  int? detectServingsFromText(String text) {
    if (text.isEmpty) return null;
    final trimmed = text.trim();
    // (\d+)\s*인분
    final servingsMatch = RegExp(r'(\d+)\s*인분').firstMatch(trimmed);
    if (servingsMatch != null) {
      final n = int.tryParse(servingsMatch.group(1) ?? '');
      if (n != null && n >= 1 && n <= 99) return n;
    }
    // (\d+)\s*명
    final countMatch = RegExp(r'(\d+)\s*명').firstMatch(trimmed);
    if (countMatch != null) {
      final n = int.tryParse(countMatch.group(1) ?? '');
      if (n != null && n >= 1 && n <= 99) return n;
    }
    // 한/두/세/네... 인분 or 명
    const koreanNumbers = {'한': 1, '두': 2, '세': 3, '네': 4, '다섯': 5, '여섯': 6, '일곱': 7, '여덟': 8, '아홉': 9, '열': 10};
    for (final entry in koreanNumbers.entries) {
      if (trimmed.contains(entry.key + ' 인분') || trimmed.contains(entry.key + '인분') ||
          trimmed.contains(entry.key + ' 명') || trimmed.contains(entry.key + '명') ||
          trimmed.contains(entry.key + ' 마리')) {
        return entry.value;
      }
    }
    return null;
  }
}
