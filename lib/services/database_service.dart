// services/database_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> saveRaceTime(String userId, double time) async {
    await _db.collection('race_times').add({
      'userId': userId,
      'time': time,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getRaceTimes() {
    return _db.collection('race_times').orderBy('timestamp', descending: true).snapshots();
  }
}
