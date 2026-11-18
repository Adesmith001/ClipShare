import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'social_video.dart';
import 'library.dart';
import 'library_help.dart';
import 'library_dialogs.dart';

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
  const DownloadsScreen({super.key, this.resolveMedia = resolveSocialVideo});
  final Future<ResolvedMedia> Function(Uri) resolveMedia;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  static const _channel = MethodChannel('clipshare/shared_links');
  late final AppLifecycleListener _lifecycle;
  final _link = TextEditingController();
  final _search = TextEditingController();
  Timer? _progressTimer;
  List<Map<Object?, Object?>> _sharedLinks = const [];
  bool _inboxUnavailable = false;
  bool _adding = false;
  bool _busy = false;
  bool _selecting = false;
  String? _folder;
  List<String> _folders = const [];
  final _selected = <String>{};
  String? _lastError;
  int _refreshVersion = 0;
  String _filter = 'All';
  final _thumbnails = <String, Future<Uint8List?>>{};

  bool get _hasNativeDownloads =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: _reload,
      onInactive: () => _progressTimer?.cancel(),
    );
    if (_hasNativeDownloads) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'changed') await _refreshSharedLinks();
      });
      _initialize();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _progressTimer?.cancel();
    _link.dispose();
    _search.dispose();
    if (_hasNativeDownloads) _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _refreshSharedLinks({bool force = false}) async {
    if (!_hasNativeDownloads || (_busy && !force)) return;
    final version = ++_refreshVersion;
    try {
      final links = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'list',
      );
      if (!mounted || version != _refreshVersion) return;
      setState(() {
        final grouped = <String, List<Map<Object?, Object?>>>{};
        for (final link in links ?? <Map<Object?, Object?>>[]) {
          (grouped[link['url'] as String] ??= []).add(link);
        }
        _sharedLinks = [
          for (final group in grouped.values)
            ...(group..sort((a, b) => _position(a).compareTo(_position(b)))),
        ];
        _inboxUnavailable = false;
        _selected.retainAll(_sharedLinks.map((entry) => entry['id'] as String));
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
      if (!mounted || version != _refreshVersion) return;
      setState(() => _inboxUnavailable = true);
    }
  }

  Future<void> _addLink() async {
    if (_adding || _busy) return;
    final text = extractMediaLink(_link.text)?.toString() ?? _link.text.trim();
    final url = Uri.tryParse(text);
    if (isSocialVideo(url)) {
      await _downloadPost(url!);
      return;
    }
    if (!isDirectVideo(url) && !isDirectImage(url)) {
      _showMessage('Paste a supported post link or a direct media link.');
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
    } on PlatformException catch (error) {
      _recordError(error.code);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  static int _position(Map<Object?, Object?> entry) =>
      int.tryParse((entry['position'] as String? ?? '').split('/').first) ?? 0;

  Future<bool> _downloadPost(
    Uri url, {
    String? replacing,
    int? onlySlot,
    bool quiet = false,
    bool refresh = true,
  }) async {
    if (_adding) return false;
    _lastError = null;
    setState(() => _adding = true);
    try {
      final resolved = isDirectImage(url) || isDirectVideo(url)
          ? (
              source: url,
              items: [(url: url, slot: 0, position: null)],
              title: null,
            )
          : await widget.resolveMedia(url);
      if (!mounted) return false;
      final items = resolved.items.where(
        (item) => onlySlot == null || item.slot == onlySlot,
      );
      if (items.isEmpty) throw const FormatException('Media item unavailable.');
      var queued = 0;
      var failed = 0;
      final source = resolved.source.toString();
      final keys = {mediaSourceKey(url), mediaSourceKey(resolved.source)};
      final parent = _sharedLinks
          .where(
            (entry) => replacing != null
                ? entry['id'] == replacing
                : entry['state'] == 'pending' &&
                      keys.contains(
                        mediaSourceKey(Uri.tryParse(entry['url'] as String)),
                      ),
          )
          .firstOrNull;
      final resolutionFolder = parent == null
          ? null
          : parent['folder'] as String? ?? '';
      for (final item in items) {
        final old = _sharedLinks
            .where(
              (entry) =>
                  keys.contains(
                    mediaSourceKey(Uri.tryParse(entry['url'] as String)),
                  ) &&
                  (entry['slot'] as int? ?? 0) == item.slot &&
                  (entry['state'] == 'failed' || entry['state'] == 'cancelled'),
            )
            .firstOrNull;
        try {
          final added = await _channel.invokeMethod<bool>('addResolved', {
            'source': source,
            'sharedSource': url.toString(),
            'folder': resolutionFolder ?? old?['folder'] as String? ?? '',
            'media': item.url.toString(),
            'slot': item.slot.toString(),
            'position': ?item.position,
            'replacing': ?(replacing ?? old?['id'] as String?),
            'title': ?resolved.title,
          });
          if (added == true) {
            queued++;
            replacing = null;
          }
        } on PlatformException catch (error) {
          failed++;
          _recordError(error.code, quiet: true);
        }
        if (!mounted) return false;
      }
      if (!mounted) return false;
      if (onlySlot == null && (queued > 0 || failed == 0)) {
        _link.clear();
        FocusScope.of(context).unfocus();
      }
      final total =
          int.tryParse(items.first.position?.split('/').last ?? '') ??
          items.length;
      if (!quiet && failed > 0) {
        _showMessage(
          queued == 0
              ? downloadErrorMessage(_lastError)
              : 'Queued $queued. Paste the link again to try missing items.',
        );
      } else if (!quiet && onlySlot == null && total > items.length) {
        _showMessage('Found ${items.length} of $total items. Added $queued.');
      } else if (!quiet && queued == 0) {
        _showMessage('Already in Downloads.');
      } else if (!quiet && items.length > 1) {
        _showMessage('Added $queued of ${items.length} items.');
      }
      if (refresh) await _refreshSharedLinks();
      return failed == 0 && queued > 0;
    } on InstagramSignInRequired {
      if (mounted) {
        _recordError(
          'sign_in_required',
          quiet: quiet,
          message: defaultTargetPlatform == TargetPlatform.iOS
              ? 'Instagram requires sign-in. Share the post to ClipShare and continue with Instagram in the share sheet.'
              : 'Instagram requires sign-in. This post is unavailable to the public-link resolver on Android.',
        );
      }
    } on FormatException {
      _recordError('unsupported', quiet: quiet);
    } on PlatformException catch (error) {
      _recordError(error.code, quiet: quiet);
    } on TimeoutException {
      _recordError('timeout', quiet: quiet);
    } on SocketException {
      _recordError('network', quiet: quiet);
    } on HttpException {
      _recordError('unavailable', quiet: quiet);
    } on Exception {
      _recordError('network', quiet: quiet);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
    return false;
  }

  void _recordError(String code, {bool quiet = false, String? message}) {
    _lastError = code;
    if (mounted && !quiet) _showMessage(message ?? downloadErrorMessage(code));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _initialize() async {
    try {
      await _channel.invokeMethod<Object?>('reconcile');
    } on PlatformException catch (error) {
      _lastError = error.code;
    }
    if (mounted) await _reload();
  }

  Future<void> _reload() async {
    if (_busy) return;
    await _refreshSharedLinks();
    if (!_hasNativeDownloads) return;
    try {
      final value = await _channel.invokeMethod<Object?>('folders');
      if (!mounted) return;
      setState(() {
        _folders = value is List ? value.whereType<String>().toList() : [];
        if (_folder != null && _folder != '' && !_folders.contains(_folder)) {
          _folder = null;
        }
      });
    } on PlatformException catch (error) {
      _recordError(error.code);
    }
  }

  Future<void> _showHelp() async {
    Map<Object?, Object?> info = {};
    try {
      final value = await _channel.invokeMethod<Object?>('info');
      if (value is Map) info = Map<Object?, Object?>.from(value);
    } on PlatformException {
      /* Help is still usable when native info is unavailable. */
    }
    if (!mounted) return;
    final snapshot = [
      for (final entry in _sharedLinks) Map<Object?, Object?>.from(entry),
    ];
    if (_lastError != null) info['lastError'] = _lastError;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LibraryHelp(info: info, entries: snapshot),
      ),
    );
  }

  Future<bool> _confirmDelete(int count) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            count == 1 ? 'Delete download?' : 'Delete $count downloads?',
          ),
          content: const Text(
            'This removes local files and entries from ClipShare. Active transfers will be cancelled. Exported copies in Photos, Gallery, or Files remain.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;

  Future<String?> _pickFolder() => showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Move to folder'),
      children: [
        for (final folder in ['', ..._folders])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, folder),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(folder.isEmpty ? 'Unfiled' : folder),
            ),
          ),
      ],
    ),
  );

  Future<void> _editFolder({String? existing}) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => FolderNameDialog(folders: _folders, existing: existing),
    );
    if (name == null || !mounted) return;
    try {
      final done = await _channel.invokeMethod<bool>(
        existing == null ? 'createFolder' : 'renameFolder',
        existing == null ? name : {'from': existing, 'to': name},
      );
      if (done == false) {
        _showMessage('The folder could not be changed. Refresh and try again.');
        return;
      }
      if (mounted) setState(() => _folder = name);
      await _reload();
    } on PlatformException catch (failure) {
      _recordError(failure.code);
    }
  }

  Future<void> _removeFolder(String folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove folder?'),
        content: Text(
          'Items in “$folder” will move to Unfiled. No media will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove folder'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final done = await _channel.invokeMethod<bool>('deleteFolder', folder);
      if (done == false) {
        _showMessage('The folder has changed. Refresh and try again.');
        return;
      }
      if (mounted) setState(() => _folder = '');
      await _reload();
    } on PlatformException catch (error) {
      _recordError(error.code);
    }
  }

  void _toggleSelection(String id) => setState(() {
    if (!_selected.add(id)) _selected.remove(id);
  });

  Future<void> _queueAction(String action, String id) => _runBatch(
    action,
    _sharedLinks.where((entry) => entry['id'] == id).toList(),
  );

  Future<void> _runBatch(String action, List<DownloadEntry> entries) async {
    if (_busy || _adding || entries.isEmpty) return;
    final snapshot = entries
        .map((entry) => Map<Object?, Object?>.from(entry))
        .toList();
    if (action == 'delete' && !await _confirmDelete(snapshot.length)) return;
    if (!mounted) return;
    String? destination;
    if (action == 'move') {
      destination = await _pickFolder();
      if (destination == null || !mounted) return;
    }
    setState(() => _busy = true);
    var completed = 0;
    var failed = 0;
    var skipped = 0;
    String? failureCode;
    try {
      if (action == 'move') {
        final done = await _channel.invokeMethod<bool>('move', {
          'ids': snapshot.map((entry) => entry['id'] as String).toList(),
          'folder': destination,
        });
        if (done == true) {
          completed = snapshot.length;
        } else {
          failed = snapshot.length;
        }
      } else {
        for (final entry in snapshot) {
          final eligibility =
              action == 'saveToPhotos' || action == 'exportToFiles'
              ? 'export'
              : action;
          if (!canApply(eligibility, entry)) {
            skipped++;
            continue;
          }
          try {
            final id = entry['id'] as String;
            final url = Uri.tryParse(entry['url'] as String);
            final bool done;
            String? attemptError;
            if (action == 'retry' &&
                url != null &&
                (isSocialVideo(url) || entry['state'] == 'pending')) {
              done = await _downloadPost(
                url,
                replacing: id,
                onlySlot: entry['state'] == 'pending'
                    ? null
                    : entry['slot'] as int? ?? 0,
                quiet: true,
                refresh: false,
              );
              if (!done) {
                attemptError = _lastError;
                failureCode = attemptError ?? failureCode;
              }
            } else {
              final method =
                  action == 'export' &&
                      defaultTargetPlatform == TargetPlatform.iOS
                  ? 'saveToPhotos'
                  : action;
              done = await _channel.invokeMethod<bool>(method, id) == true;
            }
            if (done) {
              completed++;
            } else if (attemptError != null) {
              failed++;
            } else {
              skipped++;
            }
          } on PlatformException catch (error) {
            failed++;
            failureCode = error.code;
            _recordError(error.code, quiet: true);
          }
          if (!mounted) return;
        }
      }
    } on PlatformException catch (error) {
      failed = snapshot.length;
      failureCode = error.code;
      _recordError(error.code, quiet: true);
    } finally {
      if (mounted) {
        await _refreshSharedLinks(force: true);
        if (mounted) {
          setState(() {
            _busy = false;
            if (action == 'delete') {
              _thumbnails.removeWhere(
                (id, _) => snapshot.any((entry) => entry['id'] == id),
              );
            }
          });
        }
      }
    }
    if (!mounted) return;
    _showMessage(
      '$completed completed · $failed failed · $skipped skipped'
      '${failureCode == null ? '' : '. ${downloadErrorMessage(failureCode)}'}',
    );
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
    final source = mediaSource(entry);
    final isImage = mediaIsImage(entry);
    final title = mediaTitle(entry);
    final position = entry['position'] as String?;
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
    final open = saved && !_selecting && !_busy
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
      width: MediaQuery.sizeOf(context).width < 380 ? 76 : 104,
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
            if (position != null)
              Align(
                alignment: Alignment.topLeft,
                child: Container(
                  margin: const EdgeInsets.all(5),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: plum,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    position,
                    style: const TextStyle(color: ivory, fontSize: 11),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return GestureDetector(
      onLongPress: _busy || _adding
          ? null
          : () => setState(() {
              _selecting = true;
              _selected.add(id);
            }),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_selecting)
            Checkbox(
              key: Key('select:$id'),
              value: _selected.contains(id),
              semanticLabel: 'Select $title',
              onChanged: _busy || _adding ? null : (_) => _toggleSelection(id),
            ),
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
                  if (entry['error'] case final String code)
                    Text(
                      downloadErrorMessage(code),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  if ((entry['folder'] as String? ?? '').isNotEmpty)
                    Text(
                      entry['folder'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!_selecting) ...[
            if (state == 'downloading' && entry['canCancel'] == true)
              IconButton(
                tooltip: 'Cancel download',
                onPressed: _busy || _adding
                    ? null
                    : () => _queueAction('cancel', id),
                icon: const Icon(Icons.close_rounded),
              )
            else if (canApply('retry', entry))
              IconButton(
                tooltip: state == 'pending'
                    ? 'Download media'
                    : 'Retry download',
                onPressed: _busy || _adding
                    ? null
                    : () => _queueAction('retry', id),
                icon: Icon(
                  state == 'pending'
                      ? Icons.download_rounded
                      : Icons.refresh_rounded,
                ),
              ),
            PopupMenuButton<String>(
              enabled: !_busy && !_adding,
              tooltip: saved && entry['canExport'] == true
                  ? (isImage ? 'Export image' : 'Export video')
                  : 'Download actions',
              onSelected: (action) => _queueAction(action, id),
              itemBuilder: (_) => [
                if (saved && entry['canExport'] == true)
                  if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                    const PopupMenuItem(
                      value: 'saveToPhotos',
                      child: Text('Save to Photos'),
                    ),
                    const PopupMenuItem(
                      value: 'exportToFiles',
                      child: Text('Save to Files'),
                    ),
                  ] else
                    const PopupMenuItem(
                      value: 'export',
                      child: Text('Save to Gallery'),
                    ),
                const PopupMenuItem(
                  value: 'move',
                  child: Text('Move to folder'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete download'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<DownloadEntry> get _visible => filterDownloads(
    _sharedLinks,
    query: _search.text,
    type: _filter,
    folder: _folder,
  );

  Widget _linkInput(double width) {
    final field = TextField(
      key: const Key('mediaLink'),
      controller: _link,
      enabled: !_adding && !_busy,
      decoration: InputDecoration(
        labelText: 'Media link',
        hintText: 'Paste a post or file link',
        prefixIcon: const Icon(Icons.link_rounded),
        filled: true,
        fillColor: apricot.withValues(alpha: 0.18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      onSubmitted: (_) => _addLink(),
    );
    final button = FilledButton(
      onPressed: _adding || _busy ? null : _addLink,
      child: const Text('Add link'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (width < 460 || MediaQuery.textScalerOf(context).scale(16) > 20) ...[
          field,
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: button),
        ] else
          Row(
            children: [
              Expanded(child: field),
              const SizedBox(width: 12),
              button,
            ],
          ),
        if (_adding || _busy) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(_adding ? 'Resolving link…' : 'Updating downloads…'),
          ),
        ],
      ],
    );
  }

  Widget _folderControls() => Row(
    children: [
      Expanded(
        child: PopupMenuButton<int>(
          key: const Key('folderFilter'),
          tooltip: 'Choose folder',
          enabled: !_busy && !_adding,
          onSelected: (value) => setState(
            () => _folder = value == -1
                ? null
                : value == 0
                ? ''
                : _folders[value - 1],
          ),
          itemBuilder: (_) => [
            const PopupMenuItem(value: -1, child: Text('All downloads')),
            const PopupMenuItem(value: 0, child: Text('Unfiled')),
            for (final (index, folder) in _folders.indexed)
              PopupMenuItem(value: index + 1, child: Text(folder)),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.folder_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _folder == null
                        ? 'All downloads'
                        : _folder!.isEmpty
                        ? 'Unfiled'
                        : _folder!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.expand_more_rounded),
              ],
            ),
          ),
        ),
      ),
      PopupMenuButton<String>(
        tooltip: 'Manage folders',
        enabled: !_busy && !_adding,
        icon: const Icon(Icons.create_new_folder_outlined),
        onSelected: (value) {
          if (value == 'create') _editFolder();
          if (value == 'rename') _editFolder(existing: _folder);
          if (value == 'remove' && _folder != null) _removeFolder(_folder!);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'create', child: Text('New folder')),
          if (_folder?.isNotEmpty == true) ...[
            const PopupMenuItem(value: 'rename', child: Text('Rename folder')),
            const PopupMenuItem(value: 'remove', child: Text('Remove folder')),
          ],
        ],
      ),
    ],
  );

  Widget _selectionBar(List<DownloadEntry> visible) {
    final entries = _sharedLinks
        .where((entry) => _selected.contains(entry['id']))
        .toList();
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(
          '${_selected.length} selected',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        IconButton(
          tooltip: 'Select all visible',
          onPressed: _busy || _adding
              ? null
              : () => setState(() {
                  final ids = visible
                      .map((entry) => entry['id'] as String)
                      .toSet();
                  if (ids.every(_selected.contains)) {
                    _selected.removeAll(ids);
                  } else {
                    _selected.addAll(ids);
                  }
                }),
          icon: const Icon(Icons.select_all_rounded),
        ),
        PopupMenuButton<String>(
          key: const Key('batchActions'),
          tooltip: 'Batch actions',
          enabled: entries.isNotEmpty && !_busy && !_adding,
          onSelected: (action) => _runBatch(action, entries),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'move', child: Text('Move to folder')),
            PopupMenuItem(
              value: 'retry',
              enabled: entries.any((e) => canApply('retry', e)),
              child: const Text('Retry / download'),
            ),
            PopupMenuItem(
              value: 'cancel',
              enabled: entries.any((e) => canApply('cancel', e)),
              child: const Text('Cancel downloads'),
            ),
            PopupMenuItem(
              value: 'export',
              enabled: entries.any((e) => canApply('export', e)),
              child: Text(
                defaultTargetPlatform == TargetPlatform.iOS
                    ? 'Save to Photos'
                    : 'Save to Gallery',
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete selected'),
            ),
          ],
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Actions'),
                SizedBox(width: 4),
                Icon(Icons.expand_more_rounded),
              ],
            ),
          ),
        ),
        TextButton(
          onPressed: _busy || _adding
              ? null
              : () => setState(() {
                  _selecting = false;
                  _selected.clear();
                }),
          child: const Text('Done'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visible;
    final totalBytes = _sharedLinks.fold<num>(
      0,
      (sum, entry) => sum + (entry['sizeBytes'] as num? ?? 0),
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: LayoutBuilder(
              builder: (context, constraints) => RefreshIndicator(
                onRefresh: _reload,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: apricot,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.download_rounded,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'ClipShare',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Refresh downloads',
                                  onPressed: _busy || _adding ? null : _reload,
                                  icon: const Icon(Icons.refresh_rounded),
                                ),
                                IconButton(
                                  tooltip: 'Help and feedback',
                                  onPressed: _busy ? null : _showHelp,
                                  icon: const Icon(Icons.help_outline_rounded),
                                ),
                                IconButton(
                                  tooltip: 'Select downloads',
                                  onPressed:
                                      _busy || _adding || _sharedLinks.isEmpty
                                      ? null
                                      : () => setState(() {
                                          _selecting = !_selecting;
                                          if (!_selecting) _selected.clear();
                                        }),
                                  icon: Icon(
                                    _selecting
                                        ? Icons.check_box_outlined
                                        : Icons.checklist_rounded,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
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
                            const SizedBox(height: 4),
                            Text(
                              '${_sharedLinks.length} items · ${formatBytes(totalBytes)} on this device',
                              style: theme.textTheme.bodySmall,
                            ),
                            if (_hasNativeDownloads) ...[
                              const SizedBox(height: 18),
                              _linkInput(constraints.maxWidth - 40),
                            ],
                            const SizedBox(height: 16),
                            TextField(
                              key: const Key('librarySearch'),
                              controller: _search,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Search downloads',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear search',
                                        onPressed: () =>
                                            setState(_search.clear),
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            _folderControls(),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final filter in [
                                  'All',
                                  'Photos',
                                  'Videos',
                                ])
                                  ChoiceChip(
                                    label: Text(filter),
                                    selected: _filter == filter,
                                    showCheckmark: false,
                                    selectedColor: apricot,
                                    onSelected: (_) =>
                                        setState(() => _filter = filter),
                                  ),
                              ],
                            ),
                            if (_selecting) _selectionBar(visible),
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                          ],
                        ),
                      ),
                    ),
                    if (_inboxUnavailable || visible.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _inboxUnavailable
                                    ? Icons.cloud_off_outlined
                                    : Icons.download_outlined,
                                size: 36,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _inboxUnavailable
                                    ? 'Downloads are unavailable.'
                                    : _sharedLinks.isEmpty
                                    ? 'No downloads yet'
                                    : 'No matching downloads',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _inboxUnavailable
                                    ? 'Refresh to try loading your library again.'
                                    : _sharedLinks.isEmpty
                                    ? 'Paste a supported link above, or share one from another app to ClipShare.'
                                    : 'Try another search or change the folder and media filters.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _inboxUnavailable
                                    ? _reload
                                    : _sharedLinks.isEmpty
                                    ? _showHelp
                                    : () => setState(() {
                                        _search.clear();
                                        _folder = null;
                                        _filter = 'All';
                                      }),
                                child: Text(
                                  _inboxUnavailable
                                      ? 'Try again'
                                      : _sharedLinks.isEmpty
                                      ? 'How ClipShare works'
                                      : 'Clear filters',
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        sliver:
                            constraints.maxWidth >= 820 &&
                                MediaQuery.textScalerOf(context).scale(16) <= 16
                            ? SliverGrid.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisExtent: 132,
                                      crossAxisSpacing: 24,
                                      mainAxisSpacing: 12,
                                    ),
                                itemCount: visible.length,
                                itemBuilder: (_, index) =>
                                    _downloadRow(visible[index]),
                              )
                            : SliverList.builder(
                                itemCount: visible.length,
                                itemBuilder: (_, index) => Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: _downloadRow(visible[index]),
                                ),
                              ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
