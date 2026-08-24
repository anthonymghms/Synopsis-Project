import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

bool hasAdminFlag(Map<String, dynamic> data) {
  final role = data['role']?.toString().trim().toLowerCase();
  final roles = data['roles'];
  return data['isAdmin'] == true ||
      data['admin'] == true ||
      role == 'admin' ||
      (roles is Iterable &&
          roles.any(
            (entry) => entry.toString().trim().toLowerCase() == 'admin',
          ));
}

class AdminAccess {
  AdminAccess({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final Map<String, Future<bool>> _cache = <String, Future<bool>>{};

  Future<bool> currentUserIsAdmin({bool forceRefresh = false}) {
    final user = _auth.currentUser;
    if (user == null) return Future<bool>.value(false);
    if (forceRefresh) _cache.remove(user.uid);
    return _cache.putIfAbsent(user.uid, () => _load(user));
  }

  Future<bool> _load(User user) async {
    try {
      final token = await user.getIdTokenResult(true);
      if (hasAdminFlag(token.claims ?? const <String, dynamic>{})) return true;
    } catch (_) {
      // The profile fallback keeps the navigation usable during claim refresh.
    }
    try {
      final snapshot = await _firestore.collection('users').doc(user.uid).get();
      final role = snapshot.data()?['role']?.toString().trim().toLowerCase();
      return role == 'admin';
    } catch (_) {
      return false;
    }
  }
}

final AdminAccess adminAccess = AdminAccess();
