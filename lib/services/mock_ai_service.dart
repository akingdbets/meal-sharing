/// Mock AI Service for ingredient extraction and delivery price lookup
/// This is a placeholder for actual AI integration
class MockAIService {
  static final MockAIService _instance = MockAIService._internal();
  factory MockAIService() => _instance;
  MockAIService._internal();

  // Comprehensive ingredient database with units (Map<ingredient_name, unit>)
  final Map<String, String> _ingredientDatabase = {
    // 육류 (단위: g)
    '삼겹살': 'g',
    '목살': 'g',
    '항정살': 'g',
    '갈매기살': 'g',
    '앞다리살': 'g',
    '뒷다리살': 'g',
    '대패삼겹살': 'g',
    '등갈비': 'g',
    '갈비': 'g',
    '갈비살': 'g',
    '등심': 'g',
    '안심': 'g',
    '채끝': 'g',
    '채끝살': 'g',
    '차돌박이': 'g',
    '양지': 'g',
    '사태': 'g',
    '소갈비살': 'g',
    '살치살': 'g',
    '우삼겹': 'g',
    '닭' : '마리',
    '닭가슴살': 'g',
    '닭다리': 'g',
    '닭날개': 'g',
    '닭봉': 'g',
    '닭안심': 'g',
    '볶음탕용 닭': 'g',
    '다짐육': 'g',
    '오리고기': 'g',
    '양고기': 'g',
    
    // 편의점 & 가공식품 - 라면류
    '신라면': '개',
    '진라면': '개',
    '불닭볶음면': '개',
    '불닭': '개', // 별칭
    '짜파게티': '개',
    '너구리': '개',
    '안성탕면': '개',
    '공화춘': '컵',
    '틈새라면': '개',
    '컵누들': '컵',
    '육개장사발면': '컵',
    '참깨라면': '개',
    '비빔면': '개',
    
    // 편의점 & 가공식품 - 즉석밥/면
    '햇반': '개',
    '우동사리': '개',
    '라면사리': '개',
    '떡국떡': '봉',
    '떡볶이떡': '봉',
    
    // 편의점 & 가공식품 - 토핑/반찬
    '삼각김밥': '개',
    '스트링치즈': '개',
    '비엔나': '개',
    '후랑크소세지': '개',
    '핫바': '개',
    '감동란': '알',
    '훈제란': '알',
    '맛살': '봉',
    '크래미': '봉',
    '리챔': '캔',
    
    // 편의점 & 가공식품 - 냉동식품
    '만두': '봉',
    '김말이': '봉',
    '치킨너겟': '봉',
    '용가리': '봉',
    '핫도그': '개',
    '피자': '개',
    
    // 편의점 & 가공식품 - 음료(조합용)
    '쿨피스': '개',
    '밀키스': '개',
    '사이다': '개',
    '콜라': '개',
    '갈아만든배': '개',
    
    // 채소/과일 - 단위: 개
    '양파': '개',
    '당근': '개',
    '감자': '개',
    '고구마': '개',
    '오이': '개',
    '호박': '개',
    '애호박': '개',
    '파프리카': '개',
    '피망': '개',
    '토마토': '개',
    '방울토마토': '개',
    '아보카도': '개',
    '고추': '개',
    '청양고추': '개',
    '홍고추': '개',
    '꽈리고추': '개',
    '브로콜리': '개',
    '옥수수': '개',
    
    // 과일류 - 단위: 개
    '사과': '개',
    '배': '개',
    '바나나': '개',
    '귤': '개',
    '포도': '개',
    '샤인머스캣': '개',
    '딸기': '개',
    '참외': '개',
    '멜론': '개',
    
    // 채소 - 단위: 단
    '대파': '단',
    '파': '단',
    '쪽파': '단',
    '부추': '단',
    '시금치': '단',
    '미나리': '단',
    '쑥갓': '단',
    
    // 채소 - 단위: 통
    '배추': '통',
    '양배추': '통',
    '무': '통',
    
    // 채소 - 단위: 쪽
    '마늘': '쪽',
    '다진마늘': 'g',
    
    // 필수 채소/곡류
    '현미': 'g',
    '잡곡': 'g',
    
    // 채소 - 단위: 알
    '밤': '알',
    '대추': '알',
    
    // 버섯
    '표고버섯': '송이',
    '송이버섯': '송이',
    '팽이버섯': '봉',
    '느타리버섯': '봉',
    '새송이버섯': '봉',
    '버섯': '개',
    '양송이버섯': '개',
    
    // 수산물
    '고등어': '마리',
    '갈치': '마리',
    '오징어': '마리',
    '낙지': '마리',
    '쭈꾸미': '마리',
    '새우': 'g',
    '전복': '개',
    '꽃게': '마리',
    '조개': 'g',
    '홍합': 'g',
    '굴': 'g',
    '바지락': 'g',
    '멸치': 'g',
    '연어': 'g',
    '참치': 'g',
    '생선': '마리',
    
    // 가공/유제품 (기본)
    '두부': '모',
    '순두부': '봉',
    '계란': '알',
    '달걀': '알',
    '메추리알': '알',
    '우유': 'ml',
    '생크림': 'ml',
    '치즈': '장',
    '크림치즈': 'g',
    '모짜렐라치즈': 'g',
    '참치캔': '캔',
    '햄': 'g',
    '베이컨': 'g',
    '소세지': '개',
    '어묵': 'g',
    '스팸': '캔',
    
    // 양념/소스
    '고추장': '큰술',
    '된장': '큰술',
    '간장': 'ml',
    '진간장': 'ml',
    '국간장': 'ml',
    '소금': '작은술',
    '설탕': '큰술',
    '고춧가루': '큰술',
    '식초': 'ml',
    '맛술': 'ml',
    '미림': 'ml',
    '참기름': 'ml',
    '들기름': 'ml',
    '식용유': 'ml',
    '올리브유': 'ml',
    '액젓': 'ml',
    '멸치액젓': 'ml',
    '까나리액젓': 'ml',
    '올리고당': 'ml',
    '물엿': 'ml',
    '매실액': 'ml',
    '고추기름': 'ml',
    '후추': '작은술',
    '깨': '큰술',
    '생강': 'g',
    '다시마': 'g',
    
    // 양념/소스 - 추가 소스
    '불닭소스': 'ml',
    '굴소스': 'ml',
    '돈까스소스': 'ml',
    
    // 곡물/면류
    '쌀': 'g',
    '밥': '공기',
    '국수': 'g',
    '파스타': 'g',
    '스파게티': 'g',
    '우동': 'g',
    '소바': 'g',
    '당면': 'g',
    '라면': '개',
    
    // 기타
    '물': 'ml',
    '육수': 'ml',
    '김': '장',
    '미역': 'g',
    '콩나물': 'g',
    '숙주나물': 'g',
    '숙주': 'g',
    '상추': '장',
    '깻잎': '장',
    '치커리': '장',
    '적상추': '장',
    '로메인': '장',
    '아스파라거스': '개',
    '샐러리': '개',
    '완두콩': 'g',
    '강낭콩': 'g',
    '병아리콩': 'g',
    '콩': 'g',
    '버터': 'g',
    '마요네즈': 'g',
    '케첩': 'g',
    '머스타드': 'g',
    '레몬': '개',
    '라임': '개',
    '고수': 'g',
    '바질': 'g',
    '로즈마리': 'g',
    '타임': 'g',
    '빵': '개',
    '식빵': '개',
    '밀떡': '봉',
    '쌀떡': '봉',
    '떡국떡': '봉',
  };

  // Delivery menu prices (Map of menu name to average price per serving)
  final Map<String, int> _deliveryPrices = {
    '김치찌개': 12000,
    '된장찌개': 11000,
    '부대찌개': 13000,
    '순두부찌개': 10000,
    '해물파전': 15000,
    '김치전': 12000,
    '치킨': 20000,
    '양념치킨': 21000,
    '후라이드치킨': 19000,
    '파스타': 16000,
    '크림파스타': 17000,
    '토마토파스타': 15000,
    '볶음밥': 12000,
    '김밥': 4000,
    '떡볶이': 5000,
    '라면': 6000,
    '짜장면': 6000,
    '짬뽕': 8000,
    '탕수육': 15000,
    '짜장밥': 7000,
    '비빔밥': 10000,
    '돈까스': 12000,
    '카레': 9000,
    '오므라이스': 11000,
    '제육볶음': 13000,
    '불고기': 15000,
    '삼겹살': 18000,
    '갈비탕': 12000,
    '설렁탕': 11000,
    '삼계탕': 16000,
    '닭볶음탕': 18000,
    '감자탕': 14000,
    '마라탕': 15000,
    '훠궈': 20000,
    '샤브샤브': 18000,
    '초밥': 25000,
    '회': 30000,
    '우동': 8000,
    '라멘': 10000,
    '돈부리': 12000,
    '카츠동': 13000,
    '규동': 11000,
    '볶음우동': 9000,
    '잡채': 10000,
    '떡국': 7000,
    '만두': 8000,
    '수제비': 8000,
    '칼국수': 9000,
    '냉면': 10000,
    '물냉면': 9000,
    '비빔냉면': 10000,
    '냉삼': 12000,
    '족발': 25000,
    '보쌈': 20000,
    '막국수': 9000,
    '비빔국수': 8000,
    '콩국수': 7000,
    '수육': 18000,
    '곱창': 15000,
    '막창': 16000,
    '대창': 17000,
    '양꼬치': 20000,
    '닭발': 12000,
    '닭갈비': 13000,
    '닭강정': 14000,
    '순대': 6000,
    '어묵': 5000,
  };

  /// Get all ingredient names for autocomplete/search
  /// Returns sorted list in Korean alphabetical order (가나다순)
  List<String> getAllIngredients() {
    final ingredients = _ingredientDatabase.keys.toList();
    // Korean alphabetical sort (가나다순)
    ingredients.sort((a, b) => a.compareTo(b));
    return ingredients;
  }

  /// Get unit for an ingredient with smart matching
  /// - First tries exact match
  /// - Then tries partial match with enhanced logic (e.g., '공화춘 컵라면' -> '공화춘' -> '컵')
  /// - Returns '개' as default if not found
  String getUnitForIngredient(String name) {
    if (name.isEmpty) return '개';
    
    final trimmed = name.trim();
    final normalized = trimmed.toLowerCase();
    
    // Try exact match first
    if (_ingredientDatabase.containsKey(trimmed)) {
      return _ingredientDatabase[trimmed]!;
    }
    
    // Try case-insensitive exact match
    for (final entry in _ingredientDatabase.entries) {
      if (entry.key.toLowerCase() == normalized) {
        return entry.value;
      }
    }
    
    // Enhanced partial match: Try longer keys first for better accuracy
    // This handles cases like "공화춘 컵라면" -> finds "공화춘"
    final sortedKeys = _ingredientDatabase.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    
    for (final key in sortedKeys) {
      final lowerKey = key.toLowerCase();
      // Check if the input contains the key (e.g., "공화춘 컵라면" contains "공화춘")
      // or if the key contains the input (for abbreviations)
      if (normalized.contains(lowerKey) || lowerKey.contains(normalized)) {
        return _ingredientDatabase[key]!;
      }
    }
    
    // Try word-by-word matching for compound names
    // Split by spaces and try to match each word
    final words = trimmed.split(RegExp(r'[\s]+'));
    for (final word in words) {
      if (word.length >= 2) { // Only check words with 2+ characters
        final wordLower = word.toLowerCase();
        for (final key in sortedKeys) {
          final lowerKey = key.toLowerCase();
          if (wordLower == lowerKey || wordLower.contains(lowerKey) || lowerKey.contains(wordLower)) {
            return _ingredientDatabase[key]!;
          }
        }
      }
    }
    
    // Default unit
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

    // Then check against all ingredients in database (longer names first for better accuracy)
    final sortedIngredients = _ingredientDatabase.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final ingredient in sortedIngredients) {
      final lowerIngredient = ingredient.toLowerCase();
      
      // Skip if already found via alias
      if (foundIngredients.contains(ingredient)) continue;
      
      // Check if text contains the ingredient name
      // Use word boundary matching for better accuracy
      if (lowerText.contains(lowerIngredient)) {
        // Additional check: if it's a partial match, verify it's not part of another word
        final regex = RegExp(r'\b' + RegExp.escape(lowerIngredient) + r'\b');
        if (regex.hasMatch(lowerText) || lowerText.contains(lowerIngredient)) {
          foundIngredients.add(ingredient);
        }
      }
    }

    // Remove duplicates and sort
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
