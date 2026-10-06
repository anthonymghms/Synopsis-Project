import 'package:flutter/material.dart';

/// Register on the app's Navigator to restore the visible reader's language.
final readerLanguageRouteObserver = RouteObserver<PageRoute<dynamic>>();

/// Applies a reader route's language only when that route becomes visible.
///
/// The activation callback is captured when this widget is mounted. Ordinary
/// rebuilds, including those of a covered route, must not restore an older
/// language selection. Give a replacement route a new instance of this widget.
class ReaderLanguageRoute extends StatefulWidget {
  const ReaderLanguageRoute({
    super.key,
    required this.onActivated,
    required this.child,
  });

  final VoidCallback onActivated;
  final Widget child;

  @override
  State<ReaderLanguageRoute> createState() => _ReaderLanguageRouteState();
}

class _ReaderLanguageRouteState extends State<ReaderLanguageRoute>
    with RouteAware {
  late final VoidCallback _onActivated;
  PageRoute<dynamic>? _route;
  bool _activationScheduled = false;

  @override
  void initState() {
    super.initState();
    // Capture before a later parent rebuild supplies a different closure.
    _onActivated = widget.onActivated;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final modalRoute = ModalRoute.of(context);
    final route = modalRoute is PageRoute<dynamic> ? modalRoute : null;
    if (identical(route, _route)) return;
    if (_route != null) readerLanguageRouteObserver.unsubscribe(this);
    _route = route;
    if (route != null) {
      // subscribe also calls didPush, including when asynchronous loading
      // mounts this widget after its route was originally pushed. Only full
      // pages activate languages: dismissing a popup must not undo a selection
      // made inside that popup while its persistence is still in progress.
      readerLanguageRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPush() => _scheduleActivation();

  @override
  void didPopNext() => _scheduleActivation();

  void _scheduleActivation() {
    if (_activationScheduled) return;
    _activationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activationScheduled = false;
      if (!mounted || _route?.isCurrent != true) return;
      // A controller notification during build would invalidate ancestors.
      _onActivated();
    });
  }

  @override
  void dispose() {
    readerLanguageRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
