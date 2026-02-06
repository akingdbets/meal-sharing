import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'dart:io';
import 'dart:async';
import '../models/post_model.dart';
import '../models/meal_log_model.dart';
import '../repositories/post_repository.dart';
import '../services/auth_service.dart';
import '../services/mock_ai_service.dart';
import '../repositories/meal_log_repository.dart';

class CreatePostScreen extends StatefulWidget {
  final bool isSurvival;

  const CreatePostScreen({
    super.key,
    required this.isSurvival,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final PageController _pageController = PageController();
  final PostRepository _postRepository = PostRepository();
  final AuthService _authService = AuthService();
  final MealLogRepository _mealLogRepository = MealLogRepository();
  final MockAIService _aiService = MockAIService();

  // Step 1: Image & Basic Info
  String? _imageUrl;
  File? _pickedImageFile;
  bool _isUploadingImage = false;
  late bool _isSurvival;
  final _contentController = TextEditingController();

  // Step 2: Recipe Details
  final _cookingTimeController = TextEditingController();
  int _servings = 1;
  final List<TextEditingController> _recipeStepControllers = [];
  List<String> _detectedIngredients = [];
  Timer? _ingredientExtractionTimer;
  
  // Recipe type selection: true = recipe steps, false = youtube video
  bool _useRecipeSteps = true;
  final _youtubeLinkController = TextEditingController();
  String? _youtubeVideoId;
  final _cookingTipsController = TextEditingController();

  // Step 3: Tags & Value
  final List<String> _ingredients = [];
  final Map<String, TextEditingController> _ingredientControllers = {};
  final Map<String, String> _selectedUnits = {}; // 액체류 단위 선택 (큰술/작은술)
  final _ingredientController = TextEditingController();
  /// Autocomplete 재료 검색 필드 컨트롤러 참조 (추가 시 검색칸 초기화용)
  TextEditingController? _ingredientFieldController;
  final _tagController = TextEditingController();
  final List<String> _selectedTags = [];
  final _menuNameController = TextEditingController();
  String? _deliveryMenuName;
  int _deliveryPricePerServing = 0;
  int _calculatedSavedAmount = 0;
  int _totalSaved = 0;

  // 액체류 재료 목록 (큰술/작은술 단위 선택 가능)
  static const Set<String> _liquidIngredients = {
    '간장',
    '진간장',
    '국간장',
    '식초',
    '맛술',
    '미림',
    '참기름',
    '들기름',
    '액젓',
    '멸치액젓',
    '까나리액젓',
    '올리고당',
    '물엿',
    '매실액',
    '굴소스',
    '고추기름',
  };


  int _currentStep = 0;
  bool _isLoading = false;
  final ImagePicker _imagePicker = ImagePicker();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// 배달비 계산기 자동 연동: 설명에서 음식 감지 시 SnackBar 한 번만 표시
  bool _hasShownAutoDetectSnackBar = false;

  @override
  void initState() {
    super.initState();
    _isSurvival = widget.isSurvival;
    _addRecipeStep();
    _loadUserStats();
    _menuNameController.addListener(_onMenuNameChanged);
    _contentController.addListener(_onContentChangedForDelivery);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _contentController.dispose();
    _cookingTimeController.dispose();
    _ingredientController.dispose();
    _tagController.dispose();
    _menuNameController.dispose();
    _youtubeLinkController.dispose();
    _cookingTipsController.dispose();
    for (var controller in _recipeStepControllers) {
      controller.dispose();
    }
    for (var controller in _ingredientControllers.values) {
      controller.dispose();
    }
    _ingredientControllers.clear();
    _ingredientExtractionTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserStats() async {
    try {
      final user = _authService.currentUser;
      if (user != null) {
        final stats = await _mealLogRepository.getUserStats(user.uid);
        if (mounted) {
          setState(() {
            _totalSaved = stats['totalSaved'] ?? 0;
          });
        }
      }
    } catch (e) {
      print('Error loading user stats: $e');
    }
  }

  void _onMenuNameChanged() {
    final menuName = _menuNameController.text.trim();
    if (menuName.isNotEmpty) {
      _deliveryMenuName = menuName;
      _deliveryPricePerServing = _aiService.getDeliveryPrice(menuName);
      _updateSavedAmount();
    } else {
      _deliveryMenuName = null;
      _deliveryPricePerServing = 0;
      _updateSavedAmount();
    }
    setState(() {});
  }

  /// 설명(제목) 텍스트에서 배달 메뉴·인분 감지 후 계산기 자동 연동
  void _onContentChangedForDelivery() {
    final text = _contentController.text.trim();
    if (text.isEmpty) return;

    // 배달 메뉴 감지: 계산기에서 지원하는 음식 키워드가 포함되면 자동 설정
    final detectedMenu = _aiService.detectDeliveryMenuFromText(text);
    if (detectedMenu != null) {
      final currentMenu = _deliveryMenuName?.trim() ?? '';
      if (currentMenu.isEmpty || currentMenu != detectedMenu) {
        _menuNameController.text = detectedMenu;
        _onMenuNameChanged();
        if (!_hasShownAutoDetectSnackBar && mounted) {
          _hasShownAutoDetectSnackBar = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('설명에서 음식을 감지하여 계산기를 설정했습니다: $detectedMenu'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }

    // 인분 감지 (선택): "1인분", "2명", "두 마리" 등
    final detectedServings = _aiService.detectServingsFromText(text);
    if (detectedServings != null && detectedServings >= 1 && detectedServings <= 99) {
      if (_servings != detectedServings) {
        setState(() {
          _servings = detectedServings;
          _updateSavedAmount();
        });
      }
    }
  }

  void _updateSavedAmount() {
    _calculatedSavedAmount = _deliveryPricePerServing * _servings;
    setState(() {});
  }

  /// '변경' 탭 시 메뉴 검색 다이얼로그 표시. 선택 시 _deliveryMenuName·배달비 갱신.
  Future<void> _showDeliveryMenuSearchDialog() async {
    String? selected;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('메뉴 선택'),
          content: SizedBox(
            width: double.maxFinite,
            child: Autocomplete<String>(
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return Iterable<String>.empty();
                }
                return _aiService.getMenuSuggestions(textEditingValue.text);
              },
              onSelected: (value) {
                selected = value;
                Navigator.of(ctx).pop();
              },
              fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                return TextField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    hintText: '메뉴 이름 검색 (예: 치킨, 김치찌개)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.search),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('취소'),
            ),
          ],
        );
      },
    );
    if (selected != null && mounted) {
      _menuNameController.text = selected!;
      _onMenuNameChanged();
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (pickedFile == null) return;

      // 이미지를 바로 할당 (크롭 단계 제거)
      if (mounted) {
        setState(() {
          _pickedImageFile = File(pickedFile.path);
          _imageUrl = null; // Reset uploaded URL when new image is picked
        });
      }
    } catch (e) {
      print('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('이미지를 선택하는 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (_pickedImageFile == null) {
      return null;
    }

    try {
      setState(() {
        _isUploadingImage = true;
      });

      final user = _authService.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'post_images/${user.uid}/$timestamp.jpg';
      final ref = _storage.ref().child(fileName);

      await ref.putFile(_pickedImageFile!);
      final downloadUrl = await ref.getDownloadURL();

      if (mounted) {
        setState(() {
          _imageUrl = downloadUrl;
          _isUploadingImage = false;
        });
      }

      return downloadUrl;
    } catch (e) {
      print('Error uploading image: $e');
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('이미지 업로드에 실패했습니다.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
    }
  }

  void _addRecipeStep() {
    final controller = TextEditingController();
    controller.addListener(() {
      _ingredientExtractionTimer?.cancel();
      _ingredientExtractionTimer = Timer(const Duration(milliseconds: 500), () {
        _extractIngredientsFromSteps();
      });
    });
    setState(() {
      _recipeStepControllers.add(controller);
    });
  }

  void _removeRecipeStep(int index) {
    if (_recipeStepControllers.length > 1) {
      _recipeStepControllers[index].dispose();
      setState(() {
        _recipeStepControllers.removeAt(index);
      });
      _extractIngredientsFromSteps();
    }
  }

  void _extractIngredientsFromSteps() {
    final allText = _recipeStepControllers
        .map((c) => c.text)
        .join(' ');
    final extracted = _aiService.extractIngredients(allText);
    
    setState(() {
      _detectedIngredients = extracted;
      // Merge with existing ingredients (no duplicates)
      for (final ingredient in extracted) {
        if (!_ingredients.contains(ingredient)) {
          _ingredients.add(ingredient);
          // Initialize controller for new ingredient
          _ingredientControllers[ingredient] = TextEditingController();
          // 액체류 재료인 경우 기본 단위를 '큰술'로 설정
          if (_liquidIngredients.contains(ingredient)) {
            _selectedUnits[ingredient] = '큰술';
          }
        }
      }
    });
  }

  void _addIngredient(String ingredient) {
    final trimmed = ingredient.trim();
    if (trimmed.isEmpty) return;
    
    if (_ingredients.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('메인 식재료는 최대 5개까지만 입력 가능합니다.'),
        ),
      );
      return;
    }
    
    // Check if ingredient exists in AI service database
    final allIngredients = _aiService.getAllIngredients();
    final normalized = trimmed.toLowerCase();
    final exists = allIngredients.any((ing) => ing.toLowerCase() == normalized);
    
    if (!exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$trimmed"은(는) 등록된 재료가 아닙니다. 기존 재료 목록에서 선택해주세요.')),
      );
      return;
    }
    
    // Find the exact match from ingredient database
    final exactMatch = allIngredients.firstWhere(
      (ing) => ing.toLowerCase() == normalized,
      orElse: () => trimmed,
    );
    
    if (!_ingredients.contains(exactMatch)) {
      setState(() {
        _ingredients.add(exactMatch);
        _ingredientControllers[exactMatch] = TextEditingController();
        // 액체류 재료인 경우 기본 단위를 '큰술'로 설정
        if (_liquidIngredients.contains(exactMatch)) {
          _selectedUnits[exactMatch] = '큰술';
        }
      });
      _ingredientController.clear();
      _ingredientFieldController?.clear();
      if (mounted) setState(() {});
    }
  }

  void _removeIngredient(String ingredient) {
    setState(() {
      _ingredients.remove(ingredient);
      _ingredientControllers[ingredient]?.dispose();
      _ingredientControllers.remove(ingredient);
      _selectedUnits.remove(ingredient); // 액체류 단위 선택도 제거
    });
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isEmpty) return;
    
    // Remove # if user added it manually, then add it back
    final normalizedTag = tag.startsWith('#') ? tag : '#$tag';
    
    if (!_selectedTags.contains(normalizedTag)) {
      setState(() {
        _selectedTags.add(normalizedTag);
        _tagController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _selectedTags.remove(tag);
    });
  }

  /// Extract YouTube video ID from URL (supports watch?v= and shorts/)
  String? _extractYoutubeVideoId(String url) {
    if (url.isEmpty) return null;
    return YoutubePlayer.convertUrlToId(url);
  }

  /// Handle YouTube link input change
  void _onYoutubeLinkChanged(String url) {
    final videoId = _extractYoutubeVideoId(url);
    setState(() {
      _youtubeVideoId = videoId;
    });
  }

  bool _canGoToNextStep() {
    switch (_currentStep) {
      case 0:
        return (_pickedImageFile != null || _imageUrl != null) && 
               _contentController.text.trim().isNotEmpty;
      case 1:
        // If using recipe steps, check if at least one step is filled
        // If using youtube video, check if video ID is valid
        if (_useRecipeSteps) {
          return _recipeStepControllers.any((c) => c.text.trim().isNotEmpty);
        } else {
          return _youtubeVideoId != null && _youtubeVideoId!.isNotEmpty;
        }
      case 2:
        // Step 3: 식재료(모두 수량 입력)만 필수. 태그·배달비 방어는 선택
        if (_ingredients.isEmpty) return false;
        for (final ingredient in _ingredients) {
          final controller = _ingredientControllers[ingredient];
          final quantity = controller?.text.trim() ?? '';
          if (quantity.isEmpty) return false;
          final quantityNum = int.tryParse(quantity);
          if (quantityNum == null || quantityNum < 1) return false;
        }
        return true;
      default:
        return false;
    }
  }

  void _nextStep() {
    if (_currentStep == 0) {
      // Validate Step 1: Image and content
      if (_pickedImageFile == null && _imageUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진을 추가해주세요')),
        );
        return;
      }
      if (_contentController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('설명을 입력해주세요')),
        );
        return;
      }
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else if (_currentStep == 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else if (_currentStep == 2) {
      // Validate Step 3: 식재료(모두 수량)만 필수. 태그·배달비 방어는 선택
      if (_ingredients.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메인 식재료를 최소 1개 이상 추가해주세요.')),
        );
        return;
      }
      for (final ingredient in _ingredients) {
        final controller = _ingredientControllers[ingredient];
        final quantity = controller?.text.trim() ?? '';
        if (quantity.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"$ingredient"의 수량을 입력해주세요. 모든 재료에 수량이 필요합니다.')),
          );
          return;
        }
        final quantityNum = int.tryParse(quantity);
        if (quantityNum == null || quantityNum < 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"$ingredient"의 수량은 1 이상이어야 합니다.')),
          );
          return;
        }
      }
      _submitPost();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _submitPost() async {
    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다')),
      );
      return;
    }

    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설명(내용)을 입력해주세요.')),
      );
      return;
    }

    // 유효성 검사: 식재료(모두 수량)만 필수. 태그·배달비 방어는 선택
    if (_ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메인 식재료를 최소 1개 이상 추가해주세요.')),
      );
      return;
    }
    for (final ingredient in _ingredients) {
      final controller = _ingredientControllers[ingredient];
      final quantity = controller?.text.trim() ?? '';
      if (quantity.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$ingredient"의 수량을 입력해주세요.')),
        );
        return;
      }
      final quantityNum = int.tryParse(quantity);
      if (quantityNum == null || quantityNum < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$ingredient"의 수량은 1 이상이어야 합니다.')),
        );
        return;
      }
    }

    // Get recipe steps only if using recipe steps mode
    final recipeSteps = _useRecipeSteps
        ? _recipeStepControllers
            .map((c) => c.text.trim())
            .where((step) => step.isNotEmpty)
            .toList()
        : <String>[];
    
    // Validate: either recipe steps or youtube video must be provided
    if (_useRecipeSteps && recipeSteps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('조리 순서를 최소 1개 이상 입력해주세요')),
      );
      return;
    }
    
    if (!_useRecipeSteps && (_youtubeVideoId == null || _youtubeVideoId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유효한 유튜브 링크를 입력해주세요')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Upload image first if there's a picked image
      String? uploadedImageUrl;
      if (_pickedImageFile != null) {
        uploadedImageUrl = await _uploadImage();
        if (uploadedImageUrl == null) {
          // Upload failed, stop submission
          setState(() {
            _isLoading = false;
          });
          return;
        }
      } else if (_imageUrl == null) {
        // No image selected
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진을 추가해주세요')),
        );
        return;
      } else {
        // Use existing uploaded URL
        uploadedImageUrl = _imageUrl;
      }

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

        final ingredients = _ingredients.map((name) {
          final controller = _ingredientControllers[name];
          final quantity = controller?.text.trim();
          // 액체류는 선택된 단위 사용, 그 외는 AI 추천 단위 사용
          final unit = _liquidIngredients.contains(name)
              ? (_selectedUnits[name] ?? '큰술')
              : _aiService.getUnitForIngredient(name);
          return Ingredient(
            name: name,
            coupangLink: '',
            quantity: quantity?.isNotEmpty == true ? quantity : null,
            unit: unit,
          );
        }).toList();

      final cookingTime = int.tryParse(_cookingTimeController.text.trim());

      final cookingTipsTrimmed = _cookingTipsController.text.trim();
      final post = PostModel(
        id: '',
        userId: user.uid,
        authorName: authorName,
        authorProfileImage: null,
        content: content,
        recipeSteps: recipeSteps,
        mainImageUrl: uploadedImageUrl,
        tags: _selectedTags,
        isSurvival: _isSurvival,
        savedAmount: _calculatedSavedAmount,
        ingredients: ingredients,
        deliveryMenuName: _deliveryMenuName,
        servings: _servings,
        deliveryPricePerServing: _deliveryPricePerServing,
        cookingTime: cookingTime,
        createdAt: DateTime.now(),
        youtubeVideoId: _useRecipeSteps ? null : _youtubeVideoId,
        cookingTips: cookingTipsTrimmed.isNotEmpty ? cookingTipsTrimmed : null,
      );

      final postId = await _postRepository.createPost(post).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('게시글 저장 시간이 초과되었습니다. 네트워크 연결을 확인해주세요.');
        },
      );

      // Create meal log entry automatically with postId
      try {
        final mealLog = MealLogModel(
          id: '',
          userId: user.uid,
          mealTitle: content.length > 30 ? '${content.substring(0, 30)}...' : content,
          imageUrl: uploadedImageUrl,
          postId: postId, // Link to post
          date: DateTime.now(),
          createdAt: DateTime.now(),
        );
        await _mealLogRepository.createMealLog(mealLog);
        print('Meal log created successfully with postId: $postId');
      } catch (e) {
        print('Error creating meal log: $e');
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('게시글이 작성되었습니다')),
        );
      }
    } catch (e) {
      print('Error submitting post: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류가 발생했습니다: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatNumber(int number) {
    return number.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: _currentStep == 0,
      onPopInvoked: (didPop) {
        if (!didPop && _currentStep > 0) {
          // 이전 단계로 이동
          _pageController.previousPage(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
          setState(() {
            _currentStep--;
          });
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.black),
            onPressed: () {
              if (_currentStep == 0) {
                Navigator.pop(context);
              } else {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
                setState(() {
                  _currentStep--;
                });
              }
            },
          ),
        title: Text(
          '${_currentStep + 1}/3',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Progress Indicator
          Container(
            height: 4,
            color: Colors.grey[200],
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (_currentStep + 1) / 3,
              child: Container(
                color: theme.colorScheme.primary,
              ),
            ),
          ),

          // PageView
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                setState(() {
                  _currentStep = index;
                });
              },
              children: [
                _buildStep1(theme, screenHeight),
                _buildStep2(theme),
                _buildStep3(theme),
              ],
            ),
          ),

          // Bottom Navigation Buttons
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _previousStep,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: theme.colorScheme.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        '이전',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: 12),
                Expanded(
                  flex: _currentStep > 0 ? 1 : 1,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _canGoToNextStep() ? _nextStep : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                      disabledBackgroundColor: Colors.grey[300],
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            _currentStep == 2 ? '완료' : '다음',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  // Step 1: Image & Basic Info
  Widget _buildStep1(ThemeData theme, double screenHeight) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Large Image Preview (4:3 aspect ratio)
          GestureDetector(
            onTap: _pickImage,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.grey[300]!,
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _isUploadingImage
                      ? Container(
                          color: Colors.grey[100],
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : _pickedImageFile != null
                          ? Image.file(
                              _pickedImageFile!,
                              fit: BoxFit.cover,
                            )
                          : _imageUrl != null
                              ? Image.network(
                                  _imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return _buildImagePlaceholder(theme);
                                  },
                                )
                              : _buildImagePlaceholder(theme),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Category Selector
          Text(
            '카테고리',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[900],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _CategoryButton(
                  label: '👩‍🍳 현실 집밥',
                  isSelected: !_isSurvival,
                  onTap: () {
                    setState(() {
                      _isSurvival = false;
                    });
                  },
                  theme: theme,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CategoryButton(
                  label: '🏠 자취 밥상',
                  isSelected: _isSurvival,
                  onTap: () {
                    setState(() {
                      _isSurvival = true;
                    });
                  },
                  theme: theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Description
          Text(
            '이 요리에 대한 설명을 적어주세요',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[900],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contentController,
            decoration: InputDecoration(
              hintText: '맛있게 만든 요리를 소개해주세요...',
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
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            maxLines: 5,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  // Step 2: Recipe Details & AI Ingredient Detection
  Widget _buildStep2(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cooking Time
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                '조리 시간',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _cookingTimeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '분',
                suffixText: '분',
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
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Servings
          Row(
            children: [
              const Icon(Icons.people_outline, size: 20),
              const SizedBox(width: 8),
              Text(
                '인분 수',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () {
                  if (_servings > 1) {
                    setState(() {
                      _servings--;
                      _updateSavedAmount();
                    });
                  }
                },
              ),
              Container(
                width: 60,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '$_servings',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () {
                  setState(() {
                    _servings++;
                    _updateSavedAmount();
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Recipe Type Selection (조리방법 or 동영상 링크)
          Text(
            '레시피 유형',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[900],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _RecipeTypeButton(
                  icon: Icons.format_list_numbered,
                  label: '조리방법',
                  isSelected: _useRecipeSteps,
                  onTap: () {
                    setState(() {
                      _useRecipeSteps = true;
                    });
                  },
                  theme: theme,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RecipeTypeButton(
                  icon: Icons.play_circle_outline,
                  label: '동영상 링크',
                  isSelected: !_useRecipeSteps,
                  onTap: () {
                    setState(() {
                      _useRecipeSteps = false;
                    });
                  },
                  theme: theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Conditional content based on recipe type
          if (_useRecipeSteps) ...[
            // Recipe Steps
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '조리 순서',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[900],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.help_outline, color: Colors.grey[600], size: 22),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text(
                              '조리법 작성 팁',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            content: Text(
                              '거창한 레시피가 아니어도 돼요!\n다른 분들이 따라 할 수 있게 핵심만 간단히 적어주세요. 📝',
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.6,
                                color: Colors.grey[800],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('알겠어요'),
                              ),
                            ],
                          ),
                        );
                      },
                      tooltip: '조리법 작성 팁',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _addRecipeStep,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('조리 순서 추가'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(_recipeStepControllers.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.only(top: 8, right: 12),
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
                    Expanded(
                      child: TextField(
                        controller: _recipeStepControllers[index],
                        decoration: InputDecoration(
                          hintText: '조리 과정을 입력하세요...',
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
                            borderSide: BorderSide(
                              color: theme.colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        maxLines: 2,
                      ),
                    ),
                    if (_recipeStepControllers.length > 1)
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: Colors.red[300]),
                        onPressed: () => _removeRecipeStep(index),
                      ),
                  ],
                ),
              );
            }),

            // 조리법 작성 팁 (항시 노출)
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🥕 작성 팁',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[900],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '거창한 레시피가 아니어도 돼요!\n다른 분들이 쉽게 따라 할 수 있게 핵심만 간단히 적어주세요.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.orange[900],
                    ),
                  ),
                ],
              ),
            ),

            // AI Detected Ingredients Info
            if (_detectedIngredients.isNotEmpty) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.primary.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'AI가 ${_detectedIngredients.length}개의 재료를 감지했습니다',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ] else ...[
            // YouTube Link Input
            Text(
              '유튜브 링크',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '일반 영상 또는 쇼츠 링크를 입력해주세요',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _youtubeLinkController,
                    onChanged: _onYoutubeLinkChanged,
                    decoration: InputDecoration(
                      hintText: '여기를 꾹 눌러 붙여넣기 하세요',
                      prefixIcon: Icon(
                        Icons.link,
                        color: theme.colorScheme.primary,
                      ),
                      suffixIcon: _youtubeVideoId != null
                          ? Icon(
                              Icons.check_circle,
                              color: Colors.green,
                            )
                          : _youtubeLinkController.text.isNotEmpty
                              ? Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                )
                              : null,
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
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.help_outline, color: Colors.grey[600]),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(
                          '유튜브 영상 올리는 법',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        content: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '1. 유튜브 앱에서 올리고 싶은 영상을 켜세요.',
                                style: TextStyle(fontSize: 15, height: 1.5),
                              ),
                              const SizedBox(height: 12),
                              RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: 15,
                                    height: 1.5,
                                    color: Colors.grey[900],
                                  ),
                                  children: [
                                    const TextSpan(text: '2. 영상 아래의 '),
                                    TextSpan(
                                      text: '\'공유\'',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                    const TextSpan(text: ' 버튼을 누르세요.'),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: 15,
                                    height: 1.5,
                                    color: Colors.grey[900],
                                  ),
                                  children: [
                                    const TextSpan(text: '3. '),
                                    TextSpan(
                                      text: '\'링크 복사\'',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                    const TextSpan(text: ' 버튼을 누르세요.'),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '4. 여기로 돌아와서 입력창을 꾹 누르고 \'붙여넣기\' 하세요.',
                                style: TextStyle(fontSize: 15, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('알겠어요'),
                          ),
                        ],
                      ),
                    );
                  },
                  tooltip: '유튜브 링크 복사 방법 보기',
                ),
              ],
            ),
            // 유튜브 올리는 법 팁 (항시 노출)
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💡 유튜브 영상 올리는 법',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[900],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. 유튜브 앱에서 \'공유\' → \'링크 복사\'를 누르세요.\n2. 여기 입력창을 꾹 누르고 \'붙여넣기\' 하세요.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Colors.blue[900],
                    ),
                  ),
                ],
              ),
            ),

            // YouTube Preview
            if (_youtubeVideoId != null) ...[
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      YoutubePlayer.getThumbnail(
                        videoId: _youtubeVideoId!,
                        quality: ThumbnailQuality.high,
                      ),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[200],
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.play_circle_outline,
                                  size: 48,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '영상 미리보기',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 20,
                      color: Colors.green[700],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '유효한 유튜브 링크입니다. 상세 페이지에서 앱 내 재생이 가능합니다.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_youtubeLinkController.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 20,
                      color: Colors.red[700],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '유효하지 않은 유튜브 링크입니다. 다시 확인해주세요.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // 조리 팁 (선택) - 조리법/동영상 입력란 아래
            const SizedBox(height: 24),
            Text(
              '조리 팁 (선택)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: TextField(
                controller: _cookingTipsController,
                decoration: InputDecoration(
                  hintText: '나만의 비법이나 주의사항을 적어주세요!',
                  hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  isDense: true,
                ),
                maxLines: 3,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Step 3: Tags & Value Confirmation
  Widget _buildStep3(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ingredients Section
          Text(
            '메인 식재료 (최대 5개)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[900],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Autocomplete<String>(
                  optionsBuilder: (textEditingValue) {
                    final query = textEditingValue.text.toLowerCase().trim();
                    if (query.isEmpty) {
                      return Iterable<String>.empty();
                    }
                    return _aiService.getAllIngredients().where((ingredient) {
                      return ingredient.toLowerCase().contains(query) &&
                          !_ingredients.contains(ingredient);
                    });
                  },
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    _ingredientFieldController = controller;
                    controller.addListener(() {
                      if (_ingredientController.text != controller.text) {
                        _ingredientController.text = controller.text;
                      }
                    });
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        hintText: '재료를 검색하세요',
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
                          borderSide: BorderSide(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onSubmitted: (value) {
                        _addIngredient(value);
                      },
                    );
                  },
                  onSelected: (value) {
                    _addIngredient(value);
                    // Clear the Autocomplete field after selection
                    Future.microtask(() {
                      if (mounted) {
                        // The controller will be cleared in _addIngredient
                        setState(() {});
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _ingredients.length >= 5
                    ? null
                    : () {
                        if (_ingredientController.text.trim().isNotEmpty) {
                          _addIngredient(_ingredientController.text);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('추가'),
              ),
            ],
          ),
          if (_ingredients.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: _ingredients.asMap().entries.map((entry) {
                  final index = entry.key;
                  final ingredient = entry.value;
                  final unit = _aiService.getUnitForIngredient(ingredient);
                  
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
                                ingredient,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[900],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // 수량 입력 필드
                            SizedBox(
                              width: 60,
                              child: TextField(
                                controller: _ingredientControllers[ingredient],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.right,
                                onChanged: (_) {
                                  // 값이 변경될 때마다 버튼 상태 업데이트
                                  setState(() {});
                                },
                                decoration: InputDecoration(
                                  hintText: '0',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.primary,
                                      width: 2,
                                    ),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 단위 표시 (액체류는 드롭다운, 그 외는 텍스트)
                            _liquidIngredients.contains(ingredient)
                                ? DropdownButton<String>(
                                    value: _selectedUnits[ingredient] ?? '큰술',
                                    items: const [
                                      DropdownMenuItem(value: '큰술', child: Text('큰술')),
                                      DropdownMenuItem(value: '작은술', child: Text('작은술')),
                                    ],
                                    onChanged: (String? newValue) {
                                      if (newValue != null) {
                                        setState(() {
                                          _selectedUnits[ingredient] = newValue;
                                        });
                                      }
                                    },
                                    underline: Container(),
                                    isDense: true,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  )
                                : SizedBox(
                                    width: 40,
                                    child: Text(
                                      unit,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                            const SizedBox(width: 8),
                            // 삭제 버튼
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                size: 20,
                                color: Colors.grey[400],
                              ),
                              onPressed: () => _removeIngredient(ingredient),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                      if (index < _ingredients.length - 1)
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
          ],
          const SizedBox(height: 24),

          // Tags Section
          Text(
            '태그',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[900],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagController,
                  decoration: InputDecoration(
                    hintText: '태그를 입력하세요',
                    prefixText: '#',
                    prefixStyle: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onSubmitted: (_) => _addTag(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addTag,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('추가'),
              ),
            ],
          ),
          if (_selectedTags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedTags.map((tag) {
                return Chip(
                  label: Text(
                    tag,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  backgroundColor: theme.colorScheme.primaryContainer,
                  deleteIcon: Icon(
                    Icons.close,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  onDeleted: () => _removeTag(tag),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 24),

          // Delivery Calculator
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.green[50],
              border: Border.all(
                color: Colors.green[200]!,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💲 배달비 방어 계산기',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[900],
                  ),
                ),
                const SizedBox(height: 12),
                // 선택된 메뉴 표시 + 변경 버튼 (자동 감지된 값도 여기서 확인·수정 가능)
                Row(
                  children: [
                    Text(
                      '선택된 메뉴: ',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _deliveryMenuName != null ? theme.colorScheme.primaryContainer.withOpacity(0.5) : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _deliveryMenuName ?? '없음',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _deliveryMenuName != null ? theme.colorScheme.primary : Colors.grey[600],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _showDeliveryMenuSearchDialog(),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('변경'),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _deliveryMenuName != null && _deliveryPricePerServing > 0
                              ? '이 메뉴는 배달로 시키면 약 ${_formatNumber(_deliveryPricePerServing * _servings)}원인데, 직접 해서 아꼈어요! 🎉'
                              : '메뉴를 선택하면 자동으로 계산됩니다',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _deliveryMenuName != null && _deliveryPricePerServing > 0
                                ? theme.colorScheme.primary
                                : Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '이번 달 누적 절약액: ${_formatNumber(_totalSaved)}원',
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
    );
  }

  Widget _buildImagePlaceholder(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate,
            size: 50,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 12),
          Text(
            '사진 추가',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ThemeData theme;

  const _CategoryButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary
              : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecipeTypeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ThemeData theme;

  const _RecipeTypeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary
              : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: theme.colorScheme.primary, width: 2)
              : Border.all(color: Colors.grey[300]!, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
