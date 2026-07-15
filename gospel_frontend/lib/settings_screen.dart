import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'profile_editor.dart';
import 'user_profile.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.title = 'Settings'});

  final String title;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _dirty = false;
  late String _menuLanguage =
      UserProfileController.instance.preferences.menuLanguage;

  bool get _arabic => _menuLanguage.toLowerCase() == 'arabic';

  Future<void> _save(UserProfile profile) async {
    await UserProfileController.instance.saveProfile(profile);
    if (mounted) {
      setState(() => _dirty = false);
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_arabic ? 'تجاهل التغييرات؟' : 'Discard changes?'),
        content: Text(
          _arabic ? 'لديك تغييرات غير محفوظة.' : 'You have unsaved changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_arabic ? 'متابعة التعديل' : 'Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_arabic ? 'تجاهل' : 'Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = UserProfileController.instance.profile;
    final title = _arabic ? 'الإعدادات' : 'Settings';
    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Directionality(
      textDirection: _arabic ? TextDirection.rtl : TextDirection.ltr,
      child: PopScope<bool>(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _dirty) {
            _confirmDiscard();
          }
        },
        child: Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ProfileEditor(
                        initialProfile: profile,
                        onSave: _save,
                        onDirtyChanged: (dirty) {
                          setState(() => _dirty = dirty);
                        },
                        onMenuLanguagePreview: (language) {
                          setState(() => _menuLanguage = language);
                        },
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _arabic ? 'إجراءات الحساب' : 'Account actions',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (profile.createdAt != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _arabic
                                      ? 'تاريخ إنشاء الحساب: ${_formatDate(profile.createdAt!)}'
                                      : 'Account created: ${_formatDate(profile.createdAt!)}',
                                ),
                              ],
                              const SizedBox(height: 16),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    UserProfileController.instance.clear();
                                    await FirebaseAuth.instance.signOut();
                                    if (context.mounted) {
                                      Navigator.of(
                                        context,
                                      ).popUntil((route) => route.isFirst);
                                    }
                                  },
                                  icon: const Icon(Icons.logout),
                                  label: Text(
                                    _arabic ? 'تسجيل الخروج' : 'Sign out',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
