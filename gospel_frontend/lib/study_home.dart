part of 'main.dart';

const _collections = [
  (
    id: 'harmony',
    title: 'home.topics',
    description: 'home.topicDescription',
    action: 'home.browseTopics',
    image: 'topics',
    icon: Icons.menu_book_outlined,
  ),
  (
    id: 'miracles',
    title: 'home.miracles',
    description: 'home.miracleDescription',
    action: 'home.browseMiracles',
    image: 'miracles',
    icon: Icons.wb_twilight_outlined,
  ),
  (
    id: 'parables',
    title: 'home.parables',
    description: 'home.parableDescription',
    action: 'home.browseParables',
    image: 'parables',
    icon: Icons.eco_outlined,
  ),
];

/// The public landing page. Only the authorized instance can mount the live
/// preview, which uses exactly the same cached data as the Harmony table.
class GospelHomeScreen extends StatefulWidget {
  const GospelHomeScreen({
    super.key,
    this.authenticated = false,
    this.topicLanguage,
  });
  final String? topicLanguage;
  final bool authenticated;

  @override
  State<GospelHomeScreen> createState() => _GospelHomeScreenState();
}

class _GospelHomeScreenState extends State<GospelHomeScreen> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _open(String dataset) {
    final route = Uri(
      path: '/topics',
      queryParameters: dataset == 'harmony' ? null : {'dataset': dataset},
    );
    Navigator.of(context).pushNamed(route.toString());
  }

  Future<void> _selectLanguage(String code) async {
    if (!widget.authenticated) {
      MenuLanguageController.instance.update(code);
      return;
    }
    MenuLanguageController.instance.update(code);
    final preferences = UserProfileController.instance.preferences;
    await _updateUserPreferencesBestEffort(
      preferences.copyWith(menuLanguage: code),
    );
  }

  void _how(LocalizedUiLabels labels) {
    showBrowserSafeDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(labels.text('home.how')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final step in [
                  (Icons.table_rows_outlined, 'home.stepOne'),
                  (Icons.filter_alt_outlined, 'home.stepTwo'),
                  (Icons.menu_book_outlined, 'home.stepThree'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(step.$1, color: StudyTheme.plum),
                        const SizedBox(width: 14),
                        Expanded(child: Text(labels.text(step.$2))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(labels.done),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = MenuLanguageScope.of(context);
    final labels = language.ui;
    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final compact =
        size.width < StudyTheme.compact || size.width / textScale < 580;
    final wide = size.width / textScale >= StudyTheme.wide;
    final actions = [
      PopupMenuButton<String>(
        tooltip: labels.menuLanguage,
        icon: const Icon(Icons.language_rounded),
        onSelected: _selectLanguage,
        itemBuilder: (_) => [
          for (final code in {
            ...bundledInterfaceTranslations.keys,
            if (widget.authenticated)
              ..._supportedTopicLanguages.map((option) => option.code),
          })
            CheckedPopupMenuItem(
              value: code,
              checked: language.code == code,
              child: Text(
                nativeLanguageName(
                  code,
                  resolveDatasetTopicLanguage('harmony', code).label,
                ),
              ),
            ),
        ],
      ),
      if (widget.authenticated)
        StudyAccountMenu(
          settingsLabel: labels.settings,
          logoutLabel: labels.logout,
          accountTooltip: labels.account,
          showAdmin: AdminContentScope.allowsSelection(context),
          adminLabel: labels.text('admin'),
          onHome: true,
        )
      else if (compact)
        IconButton(
          tooltip: labels.text('home.signIn'),
          icon: const Icon(Icons.person_outline),
          onPressed: () => _open('harmony'),
        )
      else
        OutlinedButton.icon(
          onPressed: () => _open('harmony'),
          icon: const Icon(Icons.person_outline, size: 18),
          label: Text(labels.text('home.signIn')),
        ),
    ];
    return Directionality(
      textDirection: language.direction,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          toolbarHeight: compact ? 60 : 72,
          titleSpacing: 0,
          title: _HomeContainer(
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: StudyBrand(
                      name: labels.text('home.brand'),
                      small: compact,
                    ),
                  ),
                ),
                if (!compact) ...[
                  for (final item in _collections)
                    TextButton(
                      onPressed: () => _open(item.id),
                      child: Text(labels.text(item.title)),
                    ),
                  const SizedBox(width: StudyTheme.gap),
                ],
                if (wide)
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: actions,
                    ),
                  )
                else
                  ...actions,
              ],
            ),
          ),
        ),
        bottomNavigationBar: compact
            ? NavigationBar(
                selectedIndex: 0,
                onDestinationSelected: (index) {
                  if (index == 0) {
                    if (_scroll.hasClients) _scroll.jumpTo(0);
                  } else {
                    _open(_collections[index - 1].id);
                  }
                },
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.home_outlined),
                    selectedIcon: const Icon(Icons.home_rounded),
                    label: labels.text('home.home'),
                  ),
                  for (final item in _collections)
                    NavigationDestination(
                      icon: Icon(item.icon),
                      label: labels.text(item.title),
                    ),
                ],
              )
            : null,
        body: SafeArea(
          top: false,
          bottom: !compact,
          child: CustomPaint(
            painter: wide ? const _HomeBorder() : null,
            child: ListView(
              controller: _scroll,
              children: [
                _StudyHero(
                  compact: compact,
                  labels: labels,
                  onExplore: () => _open('harmony'),
                  onHow: () => _how(labels),
                ),
                _HomeContainer(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: compact ? 18 : 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (wide)
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final item in _collections) ...[
                                  if (item != _collections.first)
                                    const SizedBox(width: 18),
                                  Expanded(
                                    child: _CollectionCard(
                                      item: item,
                                      labels: labels,
                                      compact: false,
                                      onTap: () => _open(item.id),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          )
                        else
                          for (final item in _collections)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _CollectionCard(
                                item: item,
                                labels: labels,
                                compact: true,
                                onTap: () => _open(item.id),
                              ),
                            ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 25),
                          child: Divider(height: 1),
                        ),
                        _ComparisonSection(
                          wide: wide,
                          authenticated: widget.authenticated,
                          topicLanguage: widget.topicLanguage,
                          labels: labels,
                          onOpen: () => _open('harmony'),
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
    );
  }
}

class _HomeBorder extends CustomPainter {
  const _HomeBorder();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(0, h - 45)
      ..cubicTo(w * .22, h + 30, w * .32, h - 36, w * .45, h - 26)
      ..cubicTo(w * .66, h + 12, w * .82, h + 15, w, h - 64)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = StudyTheme.lavender.withValues(alpha: .55),
    );
  }

  @override
  bool shouldRepaint(_HomeBorder oldDelegate) => false;
}

class _HomeContainer extends StatelessWidget {
  const _HomeContainer({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: StudyTheme.maxWidth),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: StudyTheme.inset(MediaQuery.sizeOf(context).width),
        ),
        child: child,
      ),
    ),
  );
}

class _StudyHero extends StatelessWidget {
  const _StudyHero({
    required this.compact,
    required this.labels,
    required this.onExplore,
    required this.onHow,
  });
  final bool compact;
  final LocalizedUiLabels labels;
  final VoidCallback onExplore, onHow;
  static const warmth = Color(0xfff7e9da);
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final align = compact
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;
    final textAlign = compact ? TextAlign.center : TextAlign.start;
    final copy = Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          labels.text('home.eyebrow').toUpperCase(),
          textAlign: textAlign,
          style: const TextStyle(
            color: StudyTheme.plum,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.6,
          ),
        ),
        SizedBox(height: compact ? 12 : 16),
        Semantics(
          header: true,
          child: Text(
            labels.text('home.headline'),
            textAlign: textAlign,
            style: StudyTheme.heading(
              compact ? 36 : (width * .04).clamp(42.0, 66.0).toDouble(),
              color: const Color(0xff43283f),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          labels.text('home.intro'),
          textAlign: textAlign,
          style: TextStyle(
            fontSize: compact ? 15 : 17,
            height: 1.5,
            color: StudyTheme.ink,
          ),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: compact ? WrapAlignment.center : WrapAlignment.start,
          children: [
            FilledButton.icon(
              key: const ValueKey('home-explore'),
              onPressed: onExplore,
              icon: const Icon(Icons.menu_book_outlined, size: 19),
              label: Text(labels.text('home.explore')),
            ),
            OutlinedButton.icon(
              onPressed: onHow,
              style: OutlinedButton.styleFrom(
                backgroundColor: StudyTheme.paper,
              ),
              icon: const Icon(Icons.play_circle_outline, size: 19),
              label: Text(labels.text('home.how')),
            ),
          ],
        ),
      ],
    );
    if (compact) {
      return ColoredBox(
        color: warmth,
        child: Column(
          children: [
            ClipPath(
              clipper: _HeroCurve(),
              child: SizedBox(
                height: (width * .47).clamp(160.0, 290.0),
                width: double.infinity,
                child: const StudyPhoto(
                  compact: true,
                  alignment: Alignment(.4, .3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
              child: copy,
            ),
          ],
        ),
      );
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ColoredBox(
      color: warmth,
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FractionallySizedBox(
                widthFactor: .65,
                heightFactor: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const StudyPhoto(
                      compact: false,
                      alignment: Alignment(.6, .28),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: rtl
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          end: rtl
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          colors: const [
                            warmth,
                            Color(0xe6f7e9da),
                            Color(0x00f7e9da),
                          ],
                          stops: const [0, .06, .37],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _HomeContainer(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: .465,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: width > 1100 ? 40 : 28,
                  ),
                  child: copy,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCurve extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..lineTo(0, size.height - 9)
    ..quadraticBezierTo(
      size.width * .18,
      size.height - 30,
      size.width * .45,
      size.height - 12,
    )
    ..quadraticBezierTo(
      size.width * .76,
      size.height + 6,
      size.width,
      size.height - 16,
    )
    ..lineTo(size.width, 0)
    ..close();
  @override
  bool shouldReclip(_HeroCurve oldClipper) => false;
}

typedef _Collection = ({
  String id,
  String title,
  String description,
  String action,
  String image,
  IconData icon,
});

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.item,
    required this.labels,
    required this.compact,
    required this.onTap,
  });
  final _Collection item;
  final LocalizedUiLabels labels;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final photo = Image.asset(
      'assets/study/${item.image}.webp',
      fit: BoxFit.cover,
      excludeFromSemantics: true,
      width: double.infinity,
      height: double.infinity,
    );
    final copy = Padding(
      padding: EdgeInsets.all(compact ? 16 : 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(item.icon, color: StudyTheme.plum, size: 22),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  labels.text(item.title),
                  style: StudyTheme.heading(compact ? 24 : 25),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            labels.text(item.description),
            style: const TextStyle(fontSize: 14, height: 1.42),
          ),
          if (!compact) ...[
            const SizedBox(height: 13),
            DecoratedBox(
              decoration: const ShapeDecoration(
                color: StudyTheme.lavender,
                shape: StadiumBorder(),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        labels.text(item.action),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: StudyTheme.plum,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Icon(
                      Icons.arrow_forward,
                      color: StudyTheme.plum,
                      size: 15,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      child: Card(
        child: InkWell(
          key: ValueKey('home-card-${item.id}'),
          onTap: onTap,
          child: compact
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FractionallySizedBox(
                          widthFactor: .43,
                          heightFactor: 1,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              photo,
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: rtl
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    end: rtl
                                        ? Alignment.centerLeft
                                        : Alignment.centerRight,
                                    colors: const [
                                      StudyTheme.paper,
                                      Color(0x00fffbf7),
                                    ],
                                    stops: const [0, .62],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(flex: 68, child: copy),
                        const Spacer(flex: 32),
                      ],
                    ),
                    PositionedDirectional(
                      end: 12,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: StudyTheme.paper,
                            shape: BoxShape.circle,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.arrow_forward, size: 17),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Stack(
                  alignment: AlignmentDirectional.centerEnd,
                  children: [
                    Positioned.fill(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FractionallySizedBox(
                          widthFactor: .31,
                          heightFactor: 1,
                          child: photo,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Spacer(flex: 31),
                        Expanded(flex: 69, child: copy),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ComparisonSection extends StatelessWidget {
  const _ComparisonSection({
    required this.wide,
    required this.authenticated,
    required this.topicLanguage,
    required this.labels,
    required this.onOpen,
  });
  final bool wide, authenticated;
  final String? topicLanguage;
  final LocalizedUiLabels labels;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            labels.text('home.compare'),
            style: StudyTheme.heading(30),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          labels.text('home.compareDescription'),
          style: const TextStyle(height: 1.5),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: onOpen,
          label: Text(labels.text('home.openHarmony')),
          icon: const Icon(Icons.arrow_forward, size: 17),
          iconAlignment: IconAlignment.end,
        ),
      ],
    );
    final topic = resolveDatasetTopicLanguage(
      'harmony',
      authenticated
          ? _matchingTableLanguage(
              topicLanguage ??
                  TopicLanguageSelectionController.instance.languageCode,
              _supportedTopicLanguages.map((option) => option.code),
            )
          : MenuLanguageScope.of(context).code,
    );
    final preview = _HarmonyPreview(
      authenticated: authenticated,
      labels: labels,
      topicLanguage: topic,
    );
    return wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 4, child: copy),
              const SizedBox(width: 40),
              Expanded(flex: 6, child: preview),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [copy, const SizedBox(height: 16), preview],
          );
  }
}

class _HarmonyPreview extends StatefulWidget {
  const _HarmonyPreview({
    required this.authenticated,
    required this.labels,
    required this.topicLanguage,
  });
  final bool authenticated;
  final LocalizedUiLabels labels;
  final TopicLanguageOption topicLanguage;
  @override
  State<_HarmonyPreview> createState() => _HarmonyPreviewState();
}

class _HarmonyPreviewState extends State<_HarmonyPreview> {
  Future<List<Topic>>? _rows;
  bool _visible = false;
  void _load() {
    _rows = widget.authenticated && _visible
        ? _ApiCache.fetchTopics(topicLanguage: widget.topicLanguage.code)
        : null;
  }

  void _reload() => setState(_load);
  @override
  void initState() {
    super.initState();
    catalogRevision.addListener(_reload);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = ModalRoute.isCurrentOf(context) ?? true;
    if (_visible && _rows == null) _load();
  }

  @override
  void didUpdateWidget(_HarmonyPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authenticated != widget.authenticated ||
        oldWidget.topicLanguage.code != widget.topicLanguage.code) {
      _load();
    }
  }

  @override
  void dispose() {
    catalogRevision.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.topicLanguage;
    final labels = widget.labels;
    final header = [locale.subjectsLabel, ...locale.gospelNames];
    Widget row(List<String> cells, {bool heading = false}) => DecoratedBox(
      decoration: BoxDecoration(
        color: heading ? StudyTheme.lavender : StudyTheme.paper,
        border: const Border(bottom: BorderSide(color: StudyTheme.line)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              flex: i == 0 ? 2 : 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 11,
                ),
                child: Text(
                  cells[i],
                  textAlign: i == 0 ? TextAlign.start : TextAlign.center,
                  style: TextStyle(
                    color: StudyTheme.ink,
                    fontSize: 13,
                    fontWeight: heading || i == 0
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return Card(
      child: Directionality(
        textDirection: locale.direction,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columnsWidth = math.max(510.0, constraints.maxWidth);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: columnsWidth,
                    child: Column(
                      children: [
                        row(header, heading: true),
                        if (widget.authenticated)
                          FutureBuilder<List<Topic>>(
                            future: _rows,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState !=
                                  ConnectionState.done) {
                                return const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: LinearProgressIndicator(),
                                );
                              }
                              if (snapshot.hasError) {
                                return Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(labels.text('home.previewError')),
                                      TextButton(
                                        onPressed: _reload,
                                        child: Text(labels.text('home.retry')),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              final topics = snapshot.data ?? const [];
                              if (topics.isEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Text(labels.text('home.previewEmpty')),
                                );
                              }
                              return Column(
                                children: [
                                  for (final topic in topics.take(3))
                                    row([
                                      topic.name,
                                      for (final gospel in Gospel.values)
                                        _harmonyReferenceCellText(
                                          topic,
                                          gospel,
                                          locale.code,
                                        ),
                                    ]),
                                ],
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                if (!widget.authenticated)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          size: 19,
                          color: StudyTheme.muted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            labels.text('home.previewGate'),
                            style: const TextStyle(color: StudyTheme.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
