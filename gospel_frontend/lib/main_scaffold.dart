import 'account_access.dart';
import 'user_activity.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'browser_route_link.dart';
import 'settings_screen.dart';
import 'reader_language_route.dart';
import 'interface_translations.dart';
import 'user_profile.dart';

class MainScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? topNavigation;
  final String settingsLabel;
  final String logoutLabel;
  final String accountTooltip;
  final bool showAdmin;
  final String adminLabel;

  const MainScaffold({
    super.key,
    required this.title,
    required this.body,
    this.topNavigation,
    this.settingsLabel = 'Settings',
    this.logoutLabel = 'Logout',
    this.accountTooltip = 'Account',
    this.showAdmin = false,
    this.adminLabel = 'Admin',
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
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: StudyAccountMenu(
              settingsLabel: settingsLabel,
              logoutLabel: logoutLabel,
              accountTooltip: accountTooltip,
              showAdmin: showAdmin,
              adminLabel: adminLabel,
            ),
          ),
        ],
      ),
      body: body,
    );
  }
}

class StudyAccountMenu extends StatelessWidget {
  const StudyAccountMenu({
    super.key,
    required this.settingsLabel,
    required this.logoutLabel,
    required this.accountTooltip,
    required this.showAdmin,
    required this.adminLabel,
    this.onHome = false,
  });
  final String settingsLabel, logoutLabel, accountTooltip, adminLabel;
  final bool showAdmin, onHome;

  @override
  Widget build(BuildContext context) {
    var accountMenuOpen = false;
    void beginAccountMenu() {
      if (accountMenuOpen) return;
      accountMenuOpen = true;
      BrowserRouteLinkNavigation.pushBlock();
    }

    void endAccountMenu() {
      if (!accountMenuOpen) return;
      accountMenuOpen = false;
      BrowserRouteLinkNavigation.popBlockAfterEvent();
    }

    return PopupMenuButton<String>(
      tooltip: accountTooltip,
      icon: const Icon(Icons.account_circle_outlined, size: 29),
      onOpened: beginAccountMenu,
      onCanceled: endAccountMenu,
      onSelected: (value) async {
        endAccountMenu();
        if (value == 'logout') {
          await finishUserActivity();
          accountAccess.clear();
          UserProfileController.instance.clear();
          await FirebaseAuth.instance.signOut();
          if (context.mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        } else if (value == 'settings') {
          if (context.mounted) {
            final saved = await Navigator.of(context).push<bool>(
              StudyPageRoute(
                builder: (_) => SettingsScreen(title: settingsLabel),
              ),
            );
            if (saved == true && context.mounted) {
              final preferences = UserProfileController.instance.preferences;
              final destination = Uri(
                path: '/topics',
                queryParameters: <String, String>{
                  if (preferences.tableLanguageOverride.isNotEmpty)
                    'tableLocale': preferences.tableLanguageOverride,
                  'menuLanguage': preferences.menuLanguage,
                  'topicLanguage': preferences.topicLanguage,
                  'bibleLanguage': preferences.contentLanguage,
                  'language': preferences.contentLanguage,
                  'version': preferences.preferredVersion,
                },
              ).toString();
              final messenger = ScaffoldMessenger.of(context);
              if (!onHome) {
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil(destination, (route) => false);
              }
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    LocalizedUiLabels.forLanguage(
                      preferences.menuLanguage,
                    ).text('settingsSaved'),
                  ),
                ),
              );
            }
          }
        } else if (value == 'admin') {
          if (context.mounted) {
            Navigator.of(context).pushNamed('/admin');
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
        if (showAdmin)
          PopupMenuItem<String>(
            value: 'admin',
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(adminLabel),
            ),
          ),
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
    );
  }
}
