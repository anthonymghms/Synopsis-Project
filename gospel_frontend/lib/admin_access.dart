import 'account_access.dart';
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
  AdminAccess({FirebaseAuth? auth}) : _auth = auth;

  final FirebaseAuth? _auth;

  void clearCache() {}

  Future<bool> currentUserIsAdmin({bool forceRefresh = false}) async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null) return false;
    accountAccess.beginSession(user.uid);
    await accountAccess.refresh(force: forceRefresh);
    return accountAccess.canRead && accountAccess.access?.role == 'admin';
  }
}

final AdminAccess adminAccess = AdminAccess();
