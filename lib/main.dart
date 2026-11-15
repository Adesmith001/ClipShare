import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const plum = Color(0xFF302435);
const apricot = Color(0xFFF5C5A5);
const ivory = Color(0xFFFAF7F2);

void main() => runApp(const ClipShareApp());

class ClipShareApp extends StatelessWidget {
  const ClipShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClipShare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.light(
          primary: plum,
          onPrimary: ivory,
          secondary: apricot,
          onSecondary: plum,
          surface: ivory,
          onSurface: plum,
        ),
        scaffoldBackgroundColor: ivory,
      ),
      home: const DownloadsScreen(),
    );
  }
}

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  static const _channel = MethodChannel('clipshare/shared_links');
  late final AppLifecycleListener _lifecycle;
  List<String> _sharedLinks = const [];
  bool _inboxUnavailable = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refreshSharedLinks);
    _refreshSharedLinks();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refreshSharedLinks() async {
    if (defaultTargetPlatform != TargetPlatform.iOS || kIsWeb) return;
    try {
      final links = await _channel.invokeListMethod<String>('list') ?? [];
      if (!mounted) return;
      setState(() {
        _sharedLinks = links;
        _inboxUnavailable = false;
      });
    } on PlatformException {
      if (!mounted) return;
      setState(() => _inboxUnavailable = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ClipShare',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Semantics(
                          header: true,
                          child: Text(
                            'Downloads',
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Divider(
                          height: 1,
                          color: colors.primary.withValues(alpha: 0.15),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_inboxUnavailable)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Shared links are unavailable.'),
                    ),
                  )
                else if (_sharedLinks.isNotEmpty)
                  SliverList.builder(
                    itemCount: _sharedLinks.length,
                    itemBuilder: (context, index) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                      ),
                      title: Text(
                        _sharedLinks[index],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: const Text('Pending download'),
                    ),
                  )
                else
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.secondary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Icon(
                                  Icons.download_rounded,
                                  size: 28,
                                  color: colors.onSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No downloads yet',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ),
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
