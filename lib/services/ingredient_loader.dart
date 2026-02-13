import 'package:flutter/services.dart';

/// data/*.txt 파일에서 재료 목록을 로드하여 MockAIService 등에서 사용
class IngredientLoader {
  static final IngredientLoader _instance = IngredientLoader._internal();
  factory IngredientLoader() => _instance;
  IngredientLoader._internal();

  static const List<String> _dataFiles = [
    'data/meat.txt',
    'data/vegetable.txt',
    'data/fruit.txt',
    'data/seafood.txt',
    'data/etc.txt',
  ];

  List<String> _allIngredients = [];
  bool _loaded = false;

  /// data 파일들에서 재료 목록 로드 (앱 시작 시 main에서 호출)
  Future<void> loadIngredients() async {
    if (_loaded) return;

    final all = <String>{};
    for (final path in _dataFiles) {
      try {
        final content = await rootBundle.loadString(path);
        final lines = content.split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty) {
            all.add(trimmed);
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('[IngredientLoader] Failed to load $path: $e');
      }
    }

    _allIngredients = all.toList()..sort();
    _loaded = true;
  }

  /// 로드된 전체 재료 목록 (가나다순)
  List<String> get allIngredients => List.unmodifiable(_allIngredients);

  /// 로드 완료 여부
  bool get isLoaded => _loaded;
}
