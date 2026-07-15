import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String defaultProfileMenuLanguage = 'english';
const String defaultProfileContentLanguage = 'english';
const String defaultProfileVersion = 'kjv';
const double minimumProfileZoom = 0.8;
const double maximumProfileZoom = 1.6;

class UserPreferences {
  const UserPreferences({
    this.menuLanguage = defaultProfileMenuLanguage,
    this.contentLanguage = defaultProfileContentLanguage,
    this.preferredVersion = defaultProfileVersion,
    this.showDiacritics = false,
    this.zoomLevel = 1.0,
    this.interlinearEnabled = false,
    this.showTopicNamesInChapter = false,
  });

  final String menuLanguage;
  final String contentLanguage;
  final String preferredVersion;
  final bool showDiacritics;
  final double zoomLevel;
  final bool interlinearEnabled;
  final bool showTopicNamesInChapter;

  factory UserPreferences.fromMap(
    Map<String, dynamic>? preferences, {
    Map<String, dynamic> legacy = const <String, dynamic>{},
  }) {
    final data = preferences ?? const <String, dynamic>{};
    final contentLanguage = _nonEmptyString(
      data['contentLanguage'] ??
          legacy['contentLanguage'] ??
          legacy['preferredLanguage'] ??
          legacy['language'],
      defaultProfileContentLanguage,
    ).toLowerCase();
    final menuLanguage = _nonEmptyString(
      data['menuLanguage'] ?? legacy['menuLanguage'],
      defaultProfileMenuLanguage,
    ).toLowerCase();
    final fallbackVersion = contentLanguage == 'arabic'
        ? 'Van Dyke-'
        : defaultProfileVersion;
    final zoom = _asDouble(data['zoomLevel'] ?? legacy['zoomLevel']) ?? 1.0;

    return UserPreferences(
      menuLanguage: menuLanguage,
      contentLanguage: contentLanguage,
      preferredVersion: _nonEmptyString(
        data['preferredVersion'] ??
            legacy['preferredVersion'] ??
            legacy['version'],
        fallbackVersion,
      ),
      showDiacritics:
          _asBool(data['showDiacritics'] ?? legacy['showDiacritics']) ?? false,
      zoomLevel: zoom.clamp(minimumProfileZoom, maximumProfileZoom).toDouble(),
      interlinearEnabled:
          _asBool(data['interlinearEnabled'] ?? legacy['interlinearEnabled']) ??
          false,
      showTopicNamesInChapter:
          _asBool(
            data['showTopicNamesInChapter'] ??
                legacy['showTopicNamesInChapter'],
          ) ??
          false,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'menuLanguage': menuLanguage,
    'contentLanguage': contentLanguage,
    'preferredVersion': preferredVersion,
    'showDiacritics': showDiacritics,
    'zoomLevel': zoomLevel.clamp(minimumProfileZoom, maximumProfileZoom),
    'interlinearEnabled': interlinearEnabled,
    'showTopicNamesInChapter': showTopicNamesInChapter,
  };

  UserPreferences copyWith({
    String? menuLanguage,
    String? contentLanguage,
    String? preferredVersion,
    bool? showDiacritics,
    double? zoomLevel,
    bool? interlinearEnabled,
    bool? showTopicNamesInChapter,
  }) {
    return UserPreferences(
      menuLanguage: menuLanguage ?? this.menuLanguage,
      contentLanguage: contentLanguage ?? this.contentLanguage,
      preferredVersion: preferredVersion ?? this.preferredVersion,
      showDiacritics: showDiacritics ?? this.showDiacritics,
      zoomLevel: (zoomLevel ?? this.zoomLevel)
          .clamp(minimumProfileZoom, maximumProfileZoom)
          .toDouble(),
      interlinearEnabled: interlinearEnabled ?? this.interlinearEnabled,
      showTopicNamesInChapter:
          showTopicNamesInChapter ?? this.showTopicNamesInChapter,
    );
  }
}

class UserProfile {
  const UserProfile({
    required this.firstName,
    required this.lastName,
    required this.displayName,
    required this.email,
    required this.preferences,
    this.country = '',
    this.timezone = '',
    this.yearOfBirth,
    this.organization = '',
    this.bio = '',
    this.profileCompleted = false,
    this.createdAt,
    this.updatedAt,
  });

  final String firstName;
  final String lastName;
  final String displayName;
  final String email;
  final String country;
  final String timezone;
  final int? yearOfBirth;
  final String organization;
  final String bio;
  final UserPreferences preferences;
  final bool profileCompleted;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get effectiveDisplayName {
    final explicit = displayName.trim();
    if (explicit.isNotEmpty) {
      return explicit;
    }
    final fullName = '$firstName $lastName'.trim();
    return fullName.isNotEmpty ? fullName : email;
  }

  factory UserProfile.emptyFor(User user) => UserProfile(
    firstName: '',
    lastName: '',
    displayName: user.displayName?.trim() ?? '',
    email: user.email?.trim() ?? '',
    preferences: const UserPreferences(),
  );

  factory UserProfile.fromMap(Map<String, dynamic> data, User user) {
    final legacyFullName = _string(data['fullName']);
    final explicitFirstName = _string(data['firstName']);
    final explicitLastName = _string(data['lastName']);
    final legacyNameParts = legacyFullName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final firstName = explicitFirstName.isNotEmpty
        ? explicitFirstName
        : (legacyNameParts.isNotEmpty ? legacyNameParts.first : '');
    final lastName = explicitLastName.isNotEmpty
        ? explicitLastName
        : (legacyNameParts.length > 1
              ? legacyNameParts.sublist(1).join(' ')
              : '');
    final authEmail = user.email?.trim() ?? '';
    final storedEmail = _string(data['email']);
    final year = _asInt(data['yearOfBirth']) ?? _yearFromLegacyDob(data['dob']);
    final rawPreferences = data['preferences'];

    return UserProfile(
      firstName: firstName,
      lastName: lastName,
      displayName: _nonEmptyString(
        data['displayName'],
        legacyFullName.isNotEmpty
            ? legacyFullName
            : (user.displayName?.trim() ?? ''),
      ),
      email: authEmail.isNotEmpty ? authEmail : storedEmail,
      country: _string(data['country']),
      timezone: _string(data['timezone']),
      yearOfBirth: year,
      organization: _nonEmptyString(
        data['organization'] ?? data['church'] ?? data['institution'],
        '',
      ),
      bio: _nonEmptyString(data['bio'] ?? data['description'], ''),
      preferences: UserPreferences.fromMap(
        rawPreferences is Map
            ? Map<String, dynamic>.from(rawPreferences)
            : null,
        legacy: data,
      ),
      // Legacy documents deliberately enter the one-time setup flow. Their
      // existing values are prefilled and are never overwritten by defaults.
      profileCompleted: data['profileCompleted'] == true,
      createdAt: _asDateTime(data['createdAt']),
      updatedAt: _asDateTime(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'firstName': firstName.trim(),
    'lastName': lastName.trim(),
    'displayName': displayName.trim(),
    'email': email.trim(),
    'country': country.trim(),
    'timezone': timezone.trim(),
    'yearOfBirth': yearOfBirth,
    'organization': organization.trim(),
    'bio': bio.trim(),
    'preferences': preferences.toMap(),
    'profileCompleted': profileCompleted,
  };

  UserProfile copyWith({
    String? firstName,
    String? lastName,
    String? displayName,
    String? email,
    String? country,
    String? timezone,
    int? yearOfBirth,
    bool clearYearOfBirth = false,
    String? organization,
    String? bio,
    UserPreferences? preferences,
    bool? profileCompleted,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      country: country ?? this.country,
      timezone: timezone ?? this.timezone,
      yearOfBirth: clearYearOfBirth ? null : (yearOfBirth ?? this.yearOfBirth),
      organization: organization ?? this.organization,
      bio: bio ?? this.bio,
      preferences: preferences ?? this.preferences,
      profileCompleted: profileCompleted ?? this.profileCompleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class UserProfileService {
  UserProfileService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _document(String uid) =>
      _firestore.collection('users').doc(uid);

  Future<UserProfile> load(User user) async {
    final document = _document(user.uid);
    final snapshot = await document.get();
    if (!snapshot.exists) {
      final empty = UserProfile.emptyFor(user);
      await document.set(<String, dynamic>{
        'email': empty.email,
        'profileCompleted': false,
        'preferences': empty.preferences.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      // A non-null marker prevents the completion write from replacing the
      // server-created account timestamp. The authoritative value is loaded
      // from Firestore on the next refresh/sign-in.
      return empty.copyWith(
        createdAt: user.metadata.creationTime ?? DateTime.now().toUtc(),
      );
    }
    return UserProfile.fromMap(snapshot.data() ?? <String, dynamic>{}, user);
  }

  Future<void> save(User user, UserProfile profile) async {
    final data = profile
        .copyWith(email: user.email?.trim() ?? profile.email)
        .toMap();
    data['updatedAt'] = FieldValue.serverTimestamp();
    if (profile.createdAt == null) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    await _document(user.uid).set(data, SetOptions(merge: true));
  }

  Future<void> updatePreferenceFields(
    User user,
    Map<String, dynamic> fields,
  ) async {
    if (fields.isEmpty) {
      return;
    }
    await _document(user.uid).update(<String, dynamic>{
      for (final entry in fields.entries)
        'preferences.${entry.key}': entry.value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class UserProfileController extends ChangeNotifier {
  UserProfileController({FirebaseAuth? auth, UserProfileService? service})
    : _auth = auth ?? FirebaseAuth.instance,
      _service = service ?? UserProfileService();

  static final UserProfileController instance = UserProfileController();

  final FirebaseAuth _auth;
  final UserProfileService _service;
  UserProfile? _profile;
  String? _loadedUid;
  Future<UserProfile>? _loadFuture;
  Future<void> _writeQueue = Future<void>.value();

  UserProfile? get profile => _profile;
  UserPreferences get preferences =>
      _profile?.preferences ?? const UserPreferences();
  bool get hasLoadedProfile => _profile != null && _loadedUid != null;
  bool hasProfileFor(String uid) => _profile != null && _loadedUid == uid;

  Future<UserProfile> loadForUser(User user, {bool force = false}) {
    if (!force && _loadedUid == user.uid && _profile != null) {
      return Future<UserProfile>.value(_profile);
    }
    if (!force && _loadedUid == user.uid && _loadFuture != null) {
      return _loadFuture!;
    }

    if (_loadedUid != user.uid) {
      _profile = null;
      _loadFuture = null;
    }
    _loadedUid = user.uid;
    final future = _service.load(user).then((profile) async {
      if (_loadedUid != user.uid) {
        return profile;
      }
      _profile = profile;
      await _syncLocalCache(profile.preferences);
      notifyListeners();
      return profile;
    });
    _loadFuture = future;
    return future.whenComplete(() {
      if (identical(_loadFuture, future)) {
        _loadFuture = null;
      }
    });
  }

  Future<void> saveProfile(UserProfile profile) async {
    final user = _requireUser();
    final sanitized = profile.copyWith(
      email: user.email?.trim() ?? profile.email,
    );
    await _enqueueWrite(() => _service.save(user, sanitized));
    _loadedUid = user.uid;
    _profile = sanitized;
    await _syncLocalCache(sanitized.preferences);
    notifyListeners();
  }

  Future<void> updatePreferences(UserPreferences next) async {
    final user = _requireUser();
    final currentProfile = _profile ?? await loadForUser(user);
    final current = currentProfile.preferences;
    final changedFields = <String, dynamic>{};
    final nextMap = next.toMap();
    final currentMap = current.toMap();
    for (final entry in nextMap.entries) {
      if (currentMap[entry.key] != entry.value) {
        changedFields[entry.key] = entry.value;
      }
    }
    if (changedFields.isEmpty) {
      return;
    }

    _profile = currentProfile.copyWith(preferences: next);
    await _syncLocalCache(next);
    notifyListeners();
    await _enqueueWrite(
      () => _service.updatePreferenceFields(user, changedFields),
    );
  }

  void clear() {
    if (_profile == null && _loadedUid == null && _loadFuture == null) {
      return;
    }
    _profile = null;
    _loadedUid = null;
    _loadFuture = null;
    notifyListeners();
  }

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('An authenticated user is required.');
    }
    return user;
  }

  Future<void> _enqueueWrite(Future<void> Function() operation) {
    final write = _writeQueue.then((_) => operation());
    _writeQueue = write.catchError((Object _) {});
    return write;
  }

  Future<void> _syncLocalCache(UserPreferences preferences) async {
    try {
      final local = await SharedPreferences.getInstance();
      await Future.wait(<Future<bool>>[
        local.setString('selected_language_code', preferences.contentLanguage),
        local.setString(
          'selected_menu_language_code',
          preferences.menuLanguage,
        ),
        local.setString(
          'selected_version_${preferences.contentLanguage}',
          preferences.preferredVersion,
        ),
        local.setBool('arabic_with_diacritics', preferences.showDiacritics),
        local.setDouble('reader_zoom_scale', preferences.zoomLevel),
        local.setBool(
          'default_interlinear_enabled',
          preferences.interlinearEnabled,
        ),
        local.setBool(
          'show_topic_names_in_chapter',
          preferences.showTopicNamesInChapter,
        ),
      ]);
    } catch (_) {
      // Firestore remains the source of truth if local browser storage fails.
    }
  }
}

String _string(dynamic value) => value?.toString().trim() ?? '';

String _nonEmptyString(dynamic value, String fallback) {
  final string = _string(value);
  return string.isEmpty ? fallback : string;
}

double? _asDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(_string(value));
}

int? _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(_string(value));
}

bool? _asBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  final normalized = _string(value).toLowerCase();
  if (normalized == 'true') {
    return true;
  }
  if (normalized == 'false') {
    return false;
  }
  return null;
}

int? _yearFromLegacyDob(dynamic value) {
  final dob = _string(value);
  if (dob.length < 4) {
    return null;
  }
  return int.tryParse(dob.substring(0, 4));
}

DateTime? _asDateTime(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  return DateTime.tryParse(_string(value));
}
