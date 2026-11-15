import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'social_video.dart';

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
  final _thumbnails = <String, Future<Uint8List?>>{};

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
    if (isSocialVideo(url)) {
      await _downloadPost(url!);
      return;
    }
    if (!isDirectVideo(url) && !isDirectImage(url)) {
      _showMessage(
        'Paste a supported post link or a direct MP4, JPEG, or PNG link.',
      );
      return;
    }
    setState(() => _adding = true);
    try {
      final added = await _channel.invokeMethod<bool>('add', text);
      if (!mounted) return;
      _link.clear();
      FocusScope.of(context).unfocus();
      if (added == false) _showMessage('This item is already in Downloads.');
      await _refreshSharedLinks();
    } on PlatformException {
      if (mounted) _showMessage('Couldn’t start the download.');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _downloadPost(Uri url, {String? replacing}) async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final resolved = isDirectImage(url)
          ? (source: url, media: url, title: null)
          : await resolveSocialVideo(url);
      if (!mounted) return;
      final added = await _channel.invokeMethod<bool>('addResolved', {
        'source': resolved.source.toString(),
        'media': resolved.media.toString(),
        'replacing': ?replacing,
        'title': ?resolved.title,
      });
      if (!mounted) return;
      if (replacing == null) {
        _link.clear();
        FocusScope.of(context).unfocus();
      }
      if (added == false) _showMessage('This item is already in Downloads.');
      await _refreshSharedLinks();
    } on FormatException {
      if (mounted) _showMessage('This post has no supported image or video.');
    } on PlatformException {
      if (mounted) _showMessage('Couldn’t start the download.');
    } on Exception {
      if (mounted) {
        _showMessage('Couldn’t reach the media provider. Try again.');
      }
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
        _showMessage('Saved to Gallery.');
      }
      if (action == 'saveToPhotos' && completed == true) {
        _showMessage('Saved to Photos.');
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

  Future<Uint8List?> _mediaPreview(String method, String id) async {
    try {
      return await _channel.invokeMethod<Uint8List>(method, id);
    } on PlatformException {
      return null;
    }
  }

  Future<void> _openImage(String id, String title) async {
    final bytes = await _mediaPreview('preview', id);
    if (!mounted) return;
    if (bytes == null) {
      _showMessage('This image is unavailable.');
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          body: Center(child: InteractiveViewer(child: Image.memory(bytes))),
        ),
      ),
    );
  }

  Widget _downloadRow(Map<Object?, Object?> entry) {
    final theme = Theme.of(context);
    final id = entry['id'] as String;
    final url = Uri.tryParse(entry['url'] as String);
    final host = url?.host.replaceFirst(RegExp(r'^(www|m|mobile)\.'), '') ?? '';
    final source = switch (host) {
      'youtube.com' || 'youtu.be' => 'YouTube',
      'pinterest.com' || 'pin.it' => 'Pinterest',
      'twitter.com' || 'x.com' => 'X',
      'instagram.com' => 'Instagram',
      _ => host,
    };
    final isImage = entry['isImage'] == true || isDirectImage(url);
    final isDirect = isDirectVideo(url) || isDirectImage(url);
    final filename = isDirect && url!.pathSegments.isNotEmpty
        ? url.pathSegments.last
              .replaceFirst(RegExp(r'\.[^.]+$'), '')
              .replaceAll(RegExp(r'[_-]+'), ' ')
        : null;
    final title =
        entry['title'] as String? ??
        (filename?.isNotEmpty == true
            ? filename!
            : (source.isEmpty ? 'Shared link' : '$source post'));
    final state = entry['state'];
    final saved = state == 'saved';
    final progress = entry['progress'] as num?;
    final status = switch (state) {
      'downloading' when progress != null =>
        'Downloading · ${(progress * 100).round()}%',
      'downloading' => 'Downloading',
      'saved' => 'Saved',
      'failed' => 'Download failed',
      'cancelled' => 'Cancelled',
      _ => 'Pending download',
    };
    final open = saved
        ? () => isImage ? _openImage(id, title) : _playVideo(id)
        : null;
    final placeholder = ColoredBox(
      color: theme.colorScheme.secondary.withValues(alpha: 0.45),
      child: Center(
        child: Icon(isImage ? Icons.image_outlined : Icons.movie_outlined),
      ),
    );
    if (saved && !_thumbnails.containsKey(id)) {
      if (_thumbnails.length == 64) _thumbnails.remove(_thumbnails.keys.first);
      _thumbnails[id] = _mediaPreview('thumbnail', id);
    }
    final thumbnail = SizedBox(
      width: 120,
      height: 72,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (saved)
              FutureBuilder<Uint8List?>(
                future: _thumbnails[id],
                builder: (context, snapshot) => snapshot.data == null
                    ? placeholder
                    : Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => placeholder,
                      ),
              )
            else
              placeholder,
            if (saved && !isImage)
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: plum,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: ivory,
                      size: 21,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (open == null)
          thumbnail
        else
          Tooltip(
            message: isImage ? 'View image' : 'Play video',
            child: InkWell(
              onTap: open,
              borderRadius: BorderRadius.circular(10),
              child: thumbnail,
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: open,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                if (source.isNotEmpty)
                  Text(
                    source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        if (saved && entry['canExport'] == true)
          PopupMenuButton<String>(
            tooltip: isImage ? 'Export image' : 'Export video',
            onSelected: (action) => _queueAction(action, id),
            itemBuilder: (_) => defaultTargetPlatform == TargetPlatform.iOS
                ? const [
                    PopupMenuItem(
                      value: 'saveToPhotos',
                      child: Text('Save to Photos'),
                    ),
                    PopupMenuItem(
                      value: 'exportToFiles',
                      child: Text('Save to Files'),
                    ),
                  ]
                : const [
                    PopupMenuItem(
                      value: 'export',
                      child: Text('Save to Gallery'),
                    ),
                  ],
          )
        else if (state == 'downloading' && entry['canCancel'] == true)
          IconButton(
            tooltip: 'Cancel download',
            onPressed: () => _queueAction('cancel', id),
            icon: const Icon(Icons.close_rounded),
          )
        else if ((state == 'pending' && isDirectImage(url)) ||
            ((state == 'pending' || entry['canRetry'] == true) &&
                isSocialVideo(url)))
          IconButton(
            tooltip: state == 'pending' ? 'Download media' : 'Retry download',
            onPressed: _adding
                ? null
                : () => _downloadPost(url!, replacing: id),
            icon: Icon(
              state == 'pending'
                  ? Icons.download_rounded
                  : Icons.refresh_rounded,
            ),
          )
        else if (entry['canRetry'] == true)
          IconButton(
            tooltip: 'Retry download',
            onPressed: () => _queueAction('retry', id),
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: LayoutBuilder(
              builder: (context, constraints) => CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ClipShare',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Semantics(
                            header: true,
                            child: Text(
                              'Downloads',
                              style: theme.textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1.6,
                              ),
                            ),
                          ),
                          if (_hasNativeDownloads) ...[
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _link,
                                    decoration: const InputDecoration(
                                      labelText: 'Media link',
                                      hintText: 'Paste a post or file link',
                                      prefixIcon: Icon(Icons.link_rounded),
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.url,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _addLink(),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FilledButton(
                                  onPressed: _adding ? null : _addLink,
                                  child: const Text('Add link'),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),
                          const Divider(height: 1),
                        ],
                      ),
                    ),
                  ),
                  if (_inboxUnavailable || _sharedLinks.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          _inboxUnavailable
                              ? 'Downloads are unavailable.'
                              : 'No downloads yet',
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      sliver:
                          constraints.maxWidth >= 820 &&
                              MediaQuery.textScalerOf(context).scale(16) <= 20
                          ? SliverGrid.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisExtent: 98,
                                    crossAxisSpacing: 24,
                                    mainAxisSpacing: 12,
                                  ),
                              itemCount: _sharedLinks.length,
                              itemBuilder: (_, index) =>
                                  _downloadRow(_sharedLinks[index]),
                            )
                          : SliverList.builder(
                              itemCount: _sharedLinks.length,
                              itemBuilder: (_, index) => Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _downloadRow(_sharedLinks[index]),
                              ),
                            ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
