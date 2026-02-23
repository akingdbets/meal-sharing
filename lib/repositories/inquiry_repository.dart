import 'package:cloud_firestore/cloud_firestore.dart';

/// 문의하기 / 의견 보내기 저장.
/// Firestore 컬렉션: inquiries
class InquiryRepository {
  static final InquiryRepository _instance = InquiryRepository._internal();
  factory InquiryRepository() => _instance;
  InquiryRepository._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collectionPath = 'inquiries';

  /// 문의 또는 의견을 저장합니다.
  /// [userId] 현재 사용자 uid
  /// [userEmail] 사용자 이메일 (선택)
  /// [displayName] 표시 이름 (선택)
  /// [type] 'inquiry' | 'feedback' | 'content_request' 등
  /// [content] 문의/의견 내용
  Future<String> submit({
    required String userId,
    String? userEmail,
    String? displayName,
    required String type,
    required String content,
  }) async {
    try {
      final docRef = await _firestore.collection(_collectionPath).add({
        'userId': userId,
        'userEmail': userEmail,
        'displayName': displayName,
        'type': type,
        'content': content.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      return docRef.id;
    } catch (e) {
      // ignore: avoid_print
      print('Error submitting inquiry: $e');
      rethrow;
    }
  }
}
