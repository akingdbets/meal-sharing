import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/meal_log_model.dart';

/// Repository for managing meal logs from Firestore
class MealLogRepository {
  static final MealLogRepository _instance = MealLogRepository._internal();
  factory MealLogRepository() => _instance;
  MealLogRepository._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionPath = 'meal_logs';

  /// Get all meal logs for a user
  Future<List<MealLogModel>> getUserMealLogs(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection(_collectionPath)
          .where('userId', isEqualTo: userId)
          .get();

      final logs = querySnapshot.docs
          .map((doc) => MealLogModel.fromFirestore(doc))
          .toList();
      logs.sort((a, b) => b.date.compareTo(a.date));
      return logs;
    } catch (e) {
      print('Error fetching meal logs: $e');
      return [];
    }
  }

  /// Get meal logs for a specific date range
  Future<List<MealLogModel>> getMealLogsByDateRange(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection(_collectionPath)
          .where('userId', isEqualTo: userId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      final logs = querySnapshot.docs
          .map((doc) => MealLogModel.fromFirestore(doc))
          .toList();
      logs.sort((a, b) => b.date.compareTo(a.date));
      return logs;
    } catch (e) {
      print('Error fetching meal logs by date range: $e');
      return [];
    }
  }

  /// Stream meal logs for a user
  Stream<List<MealLogModel>> streamUserMealLogs(String userId) {
    return _firestore
        .collection(_collectionPath)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final logs = snapshot.docs
              .map((doc) => MealLogModel.fromFirestore(doc))
              .toList();
          logs.sort((a, b) => b.date.compareTo(a.date));
          return logs;
        })
        .handleError((error) {
          print('Error streaming meal logs: $error');
          return <MealLogModel>[];
        });
  }

  /// Create a new meal log entry
  Future<String> createMealLog(MealLogModel log) async {
    try {
      final docRef = await _firestore.collection(_collectionPath).add(log.toJson());
      return docRef.id;
    } catch (e) {
      print('Error creating meal log: $e');
      rethrow;
    }
  }

  /// Delete a meal log entry
  Future<void> deleteMealLog(String id) async {
    try {
      await _firestore.collection(_collectionPath).doc(id).delete();
    } catch (e) {
      print('Error deleting meal log: $e');
      rethrow;
    }
  }

  /// Get statistics for a user
  Future<Map<String, dynamic>> getUserStats(String userId) async {
    try {
      final logs = await getUserMealLogs(userId);
      final now = DateTime.now();
      final thisMonthLogs = logs.where((log) => 
        log.date.year == now.year && log.date.month == now.month
      ).toList();
      
      int mealsCooked = thisMonthLogs.length;

      // Calculate total saved from posts (will be calculated in PostRepository)
      int totalSaved = 0;

      return {
        'totalSaved': totalSaved,
        'mealsCooked': mealsCooked,
      };
    } catch (e) {
      print('Error getting user stats: $e');
      return {
        'totalSaved': 0,
        'mealsCooked': 0,
      };
    }
  }

  /// Stream statistics for a user
  Stream<Map<String, dynamic>> streamUserStats(String userId) {
    return streamUserMealLogs(userId).map((logs) {
      final now = DateTime.now();
      final thisMonthLogs = logs.where((log) => 
        log.date.year == now.year && log.date.month == now.month
      ).toList();
      
      int mealsCooked = thisMonthLogs.length;

      return {
        'totalSaved': 0, // Will be calculated from posts
        'mealsCooked': mealsCooked,
      };
    });
  }

  /// Update meal log by post ID
  Future<void> updateMealLogByPostId(String postId, String newTitle, String? newImageUrl) async {
    try {
      final querySnapshot = await _firestore
          .collection(_collectionPath)
          .where('postId', isEqualTo: postId)
          .get();

      if (querySnapshot.docs.isEmpty) {
        print('No meal log found for postId: $postId');
        return;
      }

      // Update all matching meal logs (should be only one)
      final batch = _firestore.batch();
      for (var doc in querySnapshot.docs) {
        final updateData = <String, dynamic>{
          'mealTitle': newTitle,
        };
        if (newImageUrl != null) {
          updateData['imageUrl'] = newImageUrl;
        }
        batch.update(doc.reference, updateData);
      }
      await batch.commit();
      print('Meal log updated for postId: $postId');
    } catch (e) {
      print('Error updating meal log by postId: $e');
      rethrow;
    }
  }

  /// Delete meal log by post ID
  Future<void> deleteMealLogByPostId(String postId) async {
    try {
      final querySnapshot = await _firestore
          .collection(_collectionPath)
          .where('postId', isEqualTo: postId)
          .get();

      if (querySnapshot.docs.isEmpty) {
        print('No meal log found for postId: $postId');
        return;
      }

      // Delete all matching meal logs (should be only one)
      final batch = _firestore.batch();
      for (var doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      print('Meal log deleted for postId: $postId');
    } catch (e) {
      print('Error deleting meal log by postId: $e');
      rethrow;
    }
  }
}
