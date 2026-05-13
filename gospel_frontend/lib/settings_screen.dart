import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  final String title;

  const SettingsScreen({super.key, this.title = 'Settings'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text(title)),
    );
  }
}
