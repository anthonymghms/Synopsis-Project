import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'profile_editor.dart';
import 'user_profile.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late String _menuLanguage = widget.profile.preferences.menuLanguage;

  bool get _arabic => _menuLanguage.toLowerCase() == 'arabic';

  @override
  Widget build(BuildContext context) {
    final labels = ProfileEditorLabels.forLanguage(_menuLanguage);
    return Directionality(
      textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(labels.completeProfile),
          actions: [
            TextButton.icon(
              onPressed: () async {
                UserProfileController.instance.clear();
                await FirebaseAuth.instance.signOut();
              },
              icon: const Icon(Icons.logout),
              label: Text(_arabic ? 'تسجيل الخروج' : 'Sign out'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: ProfileEditor(
                  initialProfile: widget.profile,
                  setupMode: true,
                  onMenuLanguagePreview: (language) {
                    setState(() => _menuLanguage = language);
                  },
                  onSave: UserProfileController.instance.saveProfile,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
