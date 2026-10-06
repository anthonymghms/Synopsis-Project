import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gospel_frontend/user_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'reader';

  @override
  String get email => 'reader@example.test';
}

class _Auth extends Fake implements FirebaseAuth {
  @override
  User get currentUser => _User();
}

class _ProfileService extends Fake implements UserProfileService {
  final reads = <Completer<UserProfile>>[];
  final writes = <Map<String, dynamic>>[];
  final writeFinished = Completer<void>();

  @override
  Future<UserProfile> load(User user) {
    final read = Completer<UserProfile>();
    reads.add(read);
    return read.future;
  }

  @override
  Future<void> updatePreferenceFields(User user, Map<String, dynamic> fields) {
    writes.add(fields);
    return writeFinished.future;
  }
}

const _arabicProfile = UserProfile(
  firstName: 'Test',
  lastName: 'Reader',
  displayName: 'Test Reader',
  email: 'reader@example.test',
  profileCompleted: true,
  preferences: UserPreferences(menuLanguage: 'arabic'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'a late profile read cannot undo an optimistic language change',
    () async {
      final service = _ProfileService();
      final controller = UserProfileController(auth: _Auth(), service: service);
      addTearDown(controller.dispose);

      final initialLoad = controller.loadForUser(_User());
      service.reads.single.complete(_arabicProfile);
      await initialLoad;

      final pendingReload = controller.loadForUser(_User(), force: true);
      final pendingSave = controller.updatePreferences(
        controller.preferences.copyWith(
          menuLanguage: 'english',
          topicLanguage: 'english',
          contentLanguage: 'english',
        ),
      );
      expect(controller.preferences.menuLanguage, 'english');

      service.reads.last.complete(_arabicProfile);
      final loaded = await pendingReload;
      expect(loaded.preferences.menuLanguage, 'english');
      expect(controller.preferences.menuLanguage, 'english');
      expect(controller.preferences.topicLanguage, 'english');

      service.writeFinished.complete();
      await pendingSave;
      final cached = await SharedPreferences.getInstance();
      expect(cached.getString('selected_menu_language_code'), 'english');
      expect(service.writes.single['menuLanguage'], 'english');
    },
  );

  test(
    'a profile load from before sign-out cannot restore stale settings',
    () async {
      final service = _ProfileService();
      final controller = UserProfileController(auth: _Auth(), service: service);
      addTearDown(controller.dispose);

      final abandonedLoad = controller.loadForUser(_User());
      controller.clear();
      final currentLoad = controller.loadForUser(_User());
      service.reads.first.complete(_arabicProfile);
      await abandonedLoad;
      expect(controller.hasLoadedProfile, isFalse);

      service.reads.last.complete(
        _arabicProfile.copyWith(
          preferences: const UserPreferences(menuLanguage: 'english'),
        ),
      );
      await currentLoad;
      expect(controller.preferences.menuLanguage, 'english');
    },
  );
}
