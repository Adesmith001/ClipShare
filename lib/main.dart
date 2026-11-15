import 'dart:async';

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
  final _link = TextEditingController();
  Timer? _progressTimer;
  List<Map<Object?, Object?>> _sharedLinks = const [];
  bool _inboxUnavailable = false;
  bool _adding = false;

  bool get _hasNativeDownloads =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: _refreshSharedLinks,
      onInactive: () => _progressTimer?.cancel(),
    );
    if (_hasNativeDownloads) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'changed') await _refreshSharedLinks();
      });
      _refreshSharedLinks();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _progressTimer?.cancel();
    _link.dispose();
    if (_hasNativeDownloads) _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _refreshSharedLinks() async {
    if (!_hasNativeDownloads) return;
    try {
      final links = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'list',
      );
      if (!mounted) return;
      setState(() {
        _sharedLinks = links ?? [];
        _inboxUnavailable = false;
      });
      if (_sharedLinks.any((entry) => entry['state'] == 'downloading') &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        if (_progressTimer?.isActive != true) {
          _progressTimer = Timer.periodic(
            const Duration(seconds: 2),
            (_) => _refreshSharedLinks(),
          );
        }
      } else {
        _progressTimer?.cancel();
      }
    } on PlatformException {
      if (!mounted) return;
      setState(() => _inboxUnavailable = true);
    }
  }

  Future<void> _addLink() async {
    if (_adding) return;
    final text = _link.text.trim();
    final url = Uri.tryParse(text);
    if (url == null ||
        url.scheme.toLowerCase() != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        !url.path.toLowerCase().endsWith('.mp4')) {
      _showMessage('Enter a direct HTTPS MP4 link.');
      return;
    }
    setState(() => _adding = true);
    try {
      final added = await _channel.invokeMethod<bool>('add', text);
      if (!mounted) return;
      _link.clear();
      FocusScope.of(context).unfocus();
      if (added == false) _showMessage('This video is already in Downloads.');
      await _refreshSharedLinks();
    } on PlatformException {
      if (mounted) _showMessage('Couldn’t start the download.');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _queueAction(String action, String id) async {
    try {
      final completed = await _channel.invokeMethod<bool>(action, id);
      if (!mounted) return;
      if (completed == false) _showMessage('This download has changed.');
      if (action == 'export' && completed == true) {
        _showMessage('Video saved to Gallery.');
      }
      if (action == 'saveToPhotos' && completed == true) {
        _showMessage('Video saved to Photos.');
      }
      await _refreshSharedLinks();
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(
          error.code == 'photos_denied'
              ? 'Allow Photos access in Settings, or save to Files.'
              : 'Couldn’t complete that action.',
        );
      }
    }
  }

  Future<void> _playVideo(String id) async {
    try {
      await _channel.invokeMethod<void>('play', id);
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This video is unavailable.')),
      );
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
                        if (_hasNativeDownloads) ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _link,
                                  decoration: const InputDecoration(
                                    labelText: 'Video link',
                                    hintText: 'Paste an HTTPS MP4 link',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.url,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _addLink(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton(
                                onPressed: _adding ? null : _addLink,
                                child: const Text('Add link'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
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
                    itemBuilder: (context, index) {
                      final link = _sharedLinks[index];
                      final state = link['state'];
                      final id = link['id'] as String;
                      final progress = link['progress'] as num?;
                      final status = switch (state) {
                        'downloading' when progress != null =>
                          'Downloading · ${(progress * 100).round()}%',
                        'downloading' => 'Downloading',
                        'saved' => 'Saved',
                        'failed' => 'Download failed',
                        'cancelled' => 'Cancelled',
                        _ => 'Pending download',
                      };
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                        ),
                        title: Text(
                          link['url'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(status),
                        trailing: switch (state) {
                          'saved' => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Play video',
                                onPressed: () => _playVideo(id),
                                icon: const Icon(Icons.play_arrow_rounded),
                              ),
                              if (link['canExport'] == true &&
                                  defaultTargetPlatform == TargetPlatform.iOS)
                                PopupMenuButton<String>(
                                  tooltip: 'Export video',
                                  onSelected: (action) =>
                                      _queueAction(action, id),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'saveToPhotos',
                                      child: Text('Save to Photos'),
                                    ),
                                    PopupMenuItem(
                                      value: 'exportToFiles',
                                      child: Text('Save to Files'),
                                    ),
                                  ],
                                )
                              else if (link['canExport'] == true)
                                IconButton(
                                  tooltip: 'Save to Gallery',
                                  onPressed: () => _queueAction('export', id),
                                  icon: const Icon(Icons.save_alt_rounded),
                                ),
                            ],
                          ),
                          'downloading' when link['canCancel'] == true =>
                            IconButton(
                              tooltip: 'Cancel download',
                              onPressed: () => _queueAction('cancel', id),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          'failed' || 'cancelled'
                              when link['canRetry'] == true =>
                            IconButton(
                              tooltip: 'Retry download',
                              onPressed: () => _queueAction('retry', id),
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          _ => null,
                        },
                      );
                    },
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
