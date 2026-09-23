import 'package:flutter/material.dart';

/// Content conveniences for a verified admin; backend authorization is separate.
class AdminContentScope extends InheritedWidget {
  const AdminContentScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  static bool allowsSelection(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AdminContentScope>()
          ?.enabled ??
      false;

  @override
  bool updateShouldNotify(AdminContentScope oldWidget) =>
      enabled != oldWidget.enabled;
}
