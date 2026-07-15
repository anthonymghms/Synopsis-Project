// main_scaffold.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'settings_screen.dart';
import 'user_profile.dart';

class MainScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? topNavigation;
  final String settingsLabel;
  final String logoutLabel;
  final String accountTooltip;

  const MainScaffold({
    super.key,
    required this.title,
    required this.body,
    this.topNavigation,
    this.settingsLabel = 'Settings',
    this.logoutLabel = 'Logout',
    this.accountTooltip = 'Account',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 12,
        title: topNavigation ?? Text(title),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12.0),
            child: PopupMenuButton<String>(
              tooltip: accountTooltip,
              icon: const Icon(Icons.account_circle, size: 32),
              onSelected: (value) async {
                if (value == 'logout') {
                  UserProfileController.instance.clear();
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                } else if (value == 'settings') {
                  if (context.mounted) {
                    final saved = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(title: settingsLabel),
                      ),
                    );
                    if (saved == true && context.mounted) {
                      final preferences =
                          UserProfileController.instance.preferences;
                      final destination = Uri(
                        path: '/',
                        queryParameters: <String, String>{
                          'language': preferences.contentLanguage,
                          'version': preferences.preferredVersion,
                        },
                      ).toString();
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil(destination, (route) => false);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            preferences.menuLanguage == 'arabic'
                                ? 'تم حفظ الإعدادات.'
                                : 'Settings saved.',
                          ),
                        ),
                      );
                    }
                  }
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: AnimatedBuilder(
                    animation: UserProfileController.instance,
                    builder: (context, _) {
                      final user = FirebaseAuth.instance.currentUser;
                      final name =
                          UserProfileController
                              .instance
                              .profile
                              ?.effectiveDisplayName ??
                          user?.email ??
                          'User';
                      return Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(name),
                      );
                    },
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'settings',
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(settingsLabel),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'logout',
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(logoutLabel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: body,
    );
  }
}
