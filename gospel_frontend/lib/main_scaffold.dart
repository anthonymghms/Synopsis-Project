// main_scaffold.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'settings_screen.dart';

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
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                } else if (value == 'settings') {
                  if (context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SettingsScreen(title: settingsLabel),
                      ),
                    );
                  }
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(FirebaseAuth.instance.currentUser?.uid)
                        .get(),
                    builder: (context, snapshot) {
                      final user = FirebaseAuth.instance.currentUser;
                      final name =
                          snapshot.data?.get('fullName') ??
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
