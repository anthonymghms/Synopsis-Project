import 'package:flutter/material.dart';

import 'admin_portal.dart' deferred as portal;
import 'interface_translations.dart';
import 'user_profile.dart';

/// Web readers only download the admin dashboard and import editors when an
/// authorized administrator opens the portal. Native builds link it normally.
class AdminPortal extends StatefulWidget {
  const AdminPortal({super.key, required this.apiBaseUrl});
  final String apiBaseUrl;

  @override
  State<AdminPortal> createState() => _AdminPortalState();
}

class _AdminPortalState extends State<AdminPortal> {
  late Future<void> _load = portal.loadLibrary();

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _load,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        final labels = LocalizedUiLabels.forLanguage(
          UserProfileController.instance.preferences.menuLanguage,
        );
        return Scaffold(
          appBar: AppBar(title: Text(labels.text('admin'))),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(labels.text('admin.loadFailed')),
                TextButton.icon(
                  onPressed: () => setState(() => _load = portal.loadLibrary()),
                  icon: const Icon(Icons.refresh),
                  label: Text(labels.text('home.retry')),
                ),
              ],
            ),
          ),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return portal.AdminPortal(apiBaseUrl: widget.apiBaseUrl);
    },
  );
}
