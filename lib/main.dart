import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import 'social_video.dart';
import 'library.dart';
import 'library_help.dart';
import 'release_notes.dart';
import 'settings.dart';
import 'brand.dart';
import 'app_updates.dart';
import 'build_mode.dart';

part 'carousel_viewer.dart';

const plum = Color(0xFF302435);
const apricot = Color(0xFFF5C5A5);
const ivory = Color(0xFFFAF7F2);

void main() => runApp(const ClipShareApp());

class ClipShareApp extends StatefulWidget {
  const ClipShareApp({super.key});
  @override
  State<ClipShareApp> createState() => _ClipShareAppState();
}

class _ClipShareAppState extends State<ClipShareApp> {
  final _preferences = AppPreferences();
  final _updates = AppUpdates();
  late final AppLifecycleListener _updateLifecycle;
  @override
  void initState() {
    super.initState();
    _preferences.load();
    _updateLifecycle = AppLifecycleListener(onResume: _updates.check);
    unawaited(_updates.check());
  }

  @override
  void dispose() {
    _updateLifecycle.dispose();
    _updates.dispose();
    _preferences.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: plum, brightness: brightness)
        .copyWith(
          primary: dark ? apricot : plum,
          onPrimary: dark ? plum : ivory,
          secondary: apricot,
          onSecondary: plum,
          surface: dark ? const Color(0xFF1D1820) : ivory,
          onSurface: dark ? ivory : plum,
          secondaryContainer: dark
              ? const Color(0xFF503B47)
              : const Color(0xFFF6DFCE),
          onSecondaryContainer: dark ? ivory : plum,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.onSurface.withValues(alpha: 0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.12),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _preferences,
    builder: (context, _) => MaterialApp(
      title: 'ClipShare',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _preferences.themeMode,
      home: DownloadsScreen(preferences: _preferences),
      builder: (context, child) => UpdateGate(updates: _updates, child: child!),
    ),
  );
}

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({
    super.key,
    this.resolveMedia = resolveSocialVideo,
    this.preferences,
  });
  final AppPreferences? preferences;
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
  bool? _initialLibraryEmpty;
  bool _tutorialOpen = false;
  bool _releaseNotesOpen = false;
  int _tutorialStep = 0;
  String? _tutorialSource;
  final _tutorialKnownIds = <Object?>{};

  DownloadEntry? get _tutorialEntry {
    for (final entry in _sharedLinks) {
      if (_tutorialSource != null &&
          (entry['url'] == _tutorialSource ||
              entry['sharedSource'] == _tutorialSource)) {
        return entry;
      }
    }
    return null;
  }

  void _tutorialInputChanged() {
    if (!_tutorialOpen || _tutorialStep < 2 || _tutorialStep > 3) return;
    final url = extractMediaLink(_link.text) ?? Uri.tryParse(_link.text.trim());
    final valid =
        isSocialVideo(url) || isDirectVideo(url) || isDirectImage(url);
    setState(() {
      _tutorialStep = valid ? 3 : 2;
      if (valid) _tutorialSource = url.toString();
    });
  }

  void _endTutorial() {
    setState(() => _tutorialOpen = false);
    unawaited(_preferences.markTutorialSeen());
    _maybeShowWhatsNew();
  }

  Widget _tutorialHint(String title, String text, {VoidCallback? next}) =>
      Container(
        key: const Key('tutorialHint'),
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Text(text),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _endTutorial,
                  child: const Text('Skip tutorial'),
                ),
                if (next != null)
                  FilledButton(onPressed: next, child: const Text('Next')),
              ],
            ),
          ],
        ),
      );
  bool _adding = false;
  bool _busy = false;
  bool _selecting = false;
  String? _folder;
  late final AppPreferences _preferences;
  bool _searching = false;
  final _selected = <String>{};
  String? _lastError;
  int _refreshVersion = 0;
  String? _filter;
  final _thumbnails = <String, Future<Uint8List?>>{};

  bool get _hasNativeDownloads =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    _preferences = widget.preferences ?? AppPreferences();
    if (widget.preferences == null) _preferences.load();
    _preferences.addListener(_preferencesChanged);
    _link.addListener(_tutorialInputChanged);
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
    _preferences.removeListener(_preferencesChanged);
    if (widget.preferences == null) _preferences.dispose();
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
        if (_tutorialOpen && _tutorialStep == 2) {
          for (final entry in _sharedLinks) {
            if (!_tutorialKnownIds.contains(entry['id'])) {
              _tutorialSource = entry['url'] as String;
              _tutorialStep = 4;
              break;
            }
          }
        }
        _initialLibraryEmpty ??= _sharedLinks.isEmpty;
        _inboxUnavailable = false;
        _selected.retainAll(_sharedLinks.map((entry) => entry['id'] as String));
      });
      _maybeShowTutorial();
      _maybeShowWhatsNew();
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
    if (_tutorialOpen && _tutorialStep == 3) setState(() => _tutorialStep = 4);
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
      if (mounted) {
        setState(() {
          _adding = false;
          if (_tutorialOpen && _tutorialStep == 4 && _tutorialEntry == null) {
            _tutorialStep = 3;
          }
        });
      }
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
      if (_tutorialOpen && _tutorialStep == 4 && replacing == null) {
        _tutorialSource = resolved.source.toString();
      }
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
    } on TikTokResolverUnavailable {
      _recordError('tiktok_unavailable', quiet: quiet);
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
      if (mounted) {
        setState(() {
          _adding = false;
          if (_tutorialOpen && _tutorialStep == 4 && _tutorialEntry == null) {
            _tutorialStep = 3;
          }
        });
      }
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

  void _preferencesChanged() {
    if (!mounted) return;
    setState(() => _filter = null);
    _maybeShowTutorial();
    _maybeShowWhatsNew();
  }

  void _maybeShowWhatsNew() {
    if (!_preferences.hasUnseenRelease || _initialLibraryEmpty == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_tutorialOpen &&
          !_shouldShowTutorial &&
          !_searching &&
          !_adding &&
          _link.text.isEmpty &&
          ModalRoute.isCurrentOf(context) == true) {
        unawaited(_showWhatsNew());
      }
    });
  }

  Future<void> _showWhatsNew() async {
    final notes = _preferences.releaseNotes;
    if (notes == null || _releaseNotesOpen) return;
    _releaseNotesOpen = true;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ReleaseNotesScreen(notes: notes)),
    );
    _releaseNotesOpen = false;
    if (mounted) await _preferences.markReleaseSeen();
  }

  bool get _shouldShowTutorial =>
      _initialLibraryEmpty == true &&
      _sharedLinks.isEmpty &&
      !_inboxUnavailable &&
      !_tutorialOpen &&
      _preferences.shouldOfferTutorial;

  void _maybeShowTutorial() {
    if (!_shouldShowTutorial) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _shouldShowTutorial &&
          ModalRoute.isCurrentOf(context) == true &&
          !_searching &&
          !_adding &&
          _link.text.isEmpty) {
        _showTutorial();
      }
    });
  }

  void _showTutorial() {
    if (_tutorialOpen) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _tutorialOpen = true;
      _tutorialStep = 0;
      _tutorialSource = null;
      _tutorialKnownIds.clear();
      _tutorialKnownIds.addAll(_sharedLinks.map((entry) => entry['id']));
      _folder = null;
      _searching = false;
      _search.clear();
      _selecting = false;
      _selected.clear();
      _filter = 'All';
    });
  }

  Future<void> _reload() => _refreshSharedLinks();
  Future<void> _showSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          preferences: _preferences,
          storage: formatBytes(
            _sharedLinks.fold<num>(
              0,
              (sum, entry) => sum + (entry['sizeBytes'] as num? ?? 0),
            ),
          ),
          onHelp: _showHelp,
          onWhatsNew: _showWhatsNew,
          onTestFlight:
              storeBeta &&
                  _hasNativeDownloads &&
                  defaultTargetPlatform == TargetPlatform.iOS
              ? () async {
                  if (!await AppUpdates.openTestFlight() && mounted) {
                    _showMessage('Open TestFlight to check for updates.');
                  }
                }
              : null,
          onTutorial: () {
            Navigator.of(context).pop();
            _showTutorial();
          },
        ),
      ),
    );
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
    setState(() => _busy = true);
    var completed = 0;
    var failed = 0;
    var skipped = 0;
    String? failureCode;
    try {
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
            if (_tutorialOpen &&
                entry['id'] == _tutorialEntry?['id'] &&
                ['export', 'saveToPhotos', 'exportToFiles'].contains(action)) {
              setState(() => _tutorialStep = 6);
            }
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

  Future<void> _openMedia(DownloadEntry entry) async {
    final id = entry['id'] as String;
    final title = mediaTitle(entry);
    if (_position(entry) > 0) {
      final slides =
          _sharedLinks
              .where(
                (slide) => slide['url'] == entry['url'] && _position(slide) > 0,
              )
              .toList()
            ..sort((a, b) => _position(a).compareTo(_position(b)));
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _CarouselViewer(
            slides: slides,
            initialPage: slides.indexOf(entry),
            preview: (id) => _mediaPreview('preview', id),
            videoUri: (id) => _channel.invokeMethod<String>('videoUri', id),
          ),
        ),
      );
    } else if (mediaIsImage(entry)) {
      await _openImage(id, title);
    } else {
      await _playVideo(id);
    }
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
        ? () => _openMedia(entry)
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
    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _selecting && !_busy && !_adding
          ? () => _toggleSelection(id)
          : null,
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
              triggerMode: TooltipTriggerMode.manual,
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
                  value: 'delete',
                  child: Text('Delete download'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    if (_tutorialOpen && _tutorialStep == 5 && id == _tutorialEntry?['id']) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tutorialHint(
            saved ? 'Step 4 - Save your file below' : 'Wait for Saved',
            saved
                ? 'Tap this item’s three-dot menu, then choose ${defaultTargetPlatform == TargetPlatform.iOS ? "Save to Photos or Save to Files" : "Save to Gallery"}. Allow access or choose a location if asked.'
                : 'For Pending download, tap the download arrow on this item. If it fails, tap Retry download. When it says Saved, we will show you how to export it.',
          ),
          row,
        ],
      );
    }
    return row;
  }

  List<DownloadEntry> get _visible {
    final entries = filterDownloads(
      _sharedLinks,
      query: _search.text,
      type: _filter ?? _preferences.filter,
      platform: _folder,
    );
    return _preferences.sort == 'oldest' ? entries.reversed.toList() : entries;
  }

  Widget _linkInput() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('mediaLink'),
              controller: _link,
              enabled: !_adding && !_busy,
              decoration: InputDecoration(
                enabledBorder: _tutorialOpen && _tutorialStep <= 2
                    ? OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      )
                    : null,
                labelText: 'Media link',
                hintText: 'Paste a post or file link',
                prefixIcon: Icon(Icons.link_rounded),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              onSubmitted: (_) => _addLink(),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox.square(
            dimension: 56,
            child: IconButton.filled(
              tooltip: 'Add link',
              onPressed: _adding || _busy ? null : _addLink,
              icon: const Icon(Icons.add_rounded, size: 28),
              style: IconButton.styleFrom(
                side: _tutorialOpen && _tutorialStep == 3
                    ? BorderSide(
                        color: Theme.of(context).colorScheme.secondary,
                        width: 4,
                      )
                    : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
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
  Widget _platformFolders(double width) {
    final platforms =
        ['Instagram', 'X', 'YouTube', 'TikTok', 'Pinterest', 'Other'].where(
          (platform) =>
              _sharedLinks.any((entry) => mediaPlatform(entry) == platform),
        );
    final columns = width >= 650 ? 4 : 2;
    final tileWidth = (width - (columns - 1) * 12) / columns;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final platform in platforms)
          SizedBox(width: tileWidth, child: _platformTile(platform)),
      ],
    );
  }

  Widget _platformTile(String platform) {
    final scheme = Theme.of(context).colorScheme;
    final entries = _sharedLinks.where(
      (entry) => mediaPlatform(entry) == platform,
    );
    final saved = entries.where((entry) => entry['state'] == 'saved').length;
    final color = switch (platform) {
      'Instagram' => const Color(0xFFB9537A),
      'YouTube' => const Color(0xFFC35C49),
      'Pinterest' => const Color(0xFFAD4755),
      'X' => const Color(0xFF677B9D),
      _ => const Color(0xFF6B8875),
    };
    return Material(
      color: color.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.09,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side:
            _tutorialOpen &&
                _tutorialStep == 4 &&
                _tutorialEntry != null &&
                mediaPlatform(_tutorialEntry!) == platform
            ? BorderSide(color: scheme.primary, width: 3)
            : BorderSide.none,
      ),
      child: InkWell(
        key: Key('platform:$platform'),
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() {
          _folder = platform;
          if (_tutorialOpen &&
              _tutorialStep == 4 &&
              _tutorialEntry != null &&
              mediaPlatform(_tutorialEntry!) == platform) {
            _tutorialStep = 5;
          }
        }),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.folder_rounded, color: color, size: 40),
              const SizedBox(height: 12),
              Text(
                platform,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '$saved saved · ${entries.length} total',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectionBar(List<DownloadEntry> visible) {
    final entries = _sharedLinks
        .where((entry) => _selected.contains(entry['id']))
        .toList();
    final visibleIds = visible.map((entry) => entry['id'] as String).toSet();
    final allVisibleSelected =
        visibleIds.isNotEmpty && visibleIds.every(_selected.contains);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(
          '${_selected.length} selected',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        OutlinedButton(
          onPressed: _busy || _adding || visibleIds.isEmpty
              ? null
              : () => setState(() {
                  if (allVisibleSelected) {
                    _selected.removeAll(visibleIds);
                  } else {
                    _selected.addAll(visibleIds);
                  }
                }),
          child: Text(allVisibleSelected ? 'Deselect all' : 'Select all'),
        ),
        PopupMenuButton<String>(
          key: const Key('batchActions'),
          tooltip: 'Batch actions',
          enabled: entries.isNotEmpty && !_busy && !_adding,
          onSelected: (action) => _runBatch(action, entries),
          itemBuilder: (_) => [
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
    final showMedia = _folder != null || _searching;
    final totalBytes = _sharedLinks.fold<num>(
      0,
      (sum, entry) => sum + (entry['sizeBytes'] as num? ?? 0),
    );
    return PopScope<void>(
      canPop: _folder == null && !_searching && !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() {
          if (_selecting) {
            _selecting = false;
            _selected.clear();
          } else if (_searching) {
            _searching = false;
            _search.clear();
            FocusScope.of(context).unfocus();
          } else {
            _folder = null;
          }
        });
      },
      child: Scaffold(
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
                                  const ClipShareMark(),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'ClipShare',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Settings',
                                    onPressed: _busy || _adding
                                        ? null
                                        : _showSettings,
                                    icon: const Icon(Icons.tune_rounded),
                                  ),
                                  IconButton(
                                    tooltip: _searching
                                        ? 'Close search'
                                        : 'Search downloads',
                                    onPressed: () => setState(() {
                                      _searching = !_searching;
                                      if (!_searching) {
                                        _search.clear();
                                        FocusScope.of(context).unfocus();
                                      }
                                    }),
                                    icon: Icon(
                                      _searching
                                          ? Icons.close_rounded
                                          : Icons.search_rounded,
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
                              if (_tutorialOpen && _tutorialStep <= 4)
                                _tutorialHint(
                                  switch (_tutorialStep) {
                                    0 => 'Step 1 - Paste your link here',
                                    1 => 'Step 2 - Get a link from another app',
                                    2 => 'Paste your link below',
                                    3 => 'Tap the highlighted + button',
                                    _ => 'Open the highlighted folder below',
                                  },
                                  switch (_tutorialStep) {
                                    0 => 'The Media link field below is where you paste a copied link. Press and hold the field, then choose Paste.',
                                    1 => 'Open Instagram, TikTok, YouTube, or X. Open a public post, tap Share, then Copy link. Return here and paste it below. You can also choose ClipShare from the Share menu in those apps.',
                                    2 => 'Paste a supported link into Media link below. This guide will wait for you.',
                                    3 => 'Your link is ready. Tap + beside Media link to add your download.',
                                    _ =>
                                      _tutorialEntry == null
                                          ? 'Adding your link. If it fails, paste a fresh public link below and try again.'
                                          : 'Tap ${mediaPlatform(_tutorialEntry!)} below to see your download.',
                                  },
                                  next: _tutorialStep < 2
                                      ? () {
                                          setState(() => _tutorialStep++);
                                          _tutorialInputChanged();
                                        }
                                      : null,
                                ),
                              if (_tutorialOpen && _tutorialStep == 6)
                                _tutorialHint(
                                  'Your file has been saved',
                                  'Replay this guide anytime from Settings.',
                                  next: _endTutorial,
                                ),
                              if (_hasNativeDownloads) ...[
                                const SizedBox(height: 18),
                                _linkInput(),
                              ],
                              if (_searching) ...[
                                const SizedBox(height: 16),
                                TextField(
                                  key: const Key('librarySearch'),
                                  controller: _search,
                                  autofocus: true,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    hintText: 'Search downloads',
                                    prefixIcon: const Icon(
                                      Icons.search_rounded,
                                    ),
                                    suffixIcon: _search.text.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Clear search',
                                            onPressed: () =>
                                                setState(_search.clear),
                                            icon: const Icon(
                                              Icons.close_rounded,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              if (_folder == null &&
                                  !_searching &&
                                  _sharedLinks.isNotEmpty) ...[
                                Text(
                                  'Your folders',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _platformFolders(constraints.maxWidth - 40),
                                const SizedBox(height: 24),
                              ],
                              if (showMedia) ...[
                                Row(
                                  children: [
                                    if (_folder != null)
                                      IconButton(
                                        tooltip: 'All downloads',
                                        onPressed: () =>
                                            setState(() => _folder = null),
                                        icon: const Icon(
                                          Icons.arrow_back_rounded,
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        _folder ?? 'Search results',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Select downloads',
                                      onPressed:
                                          _busy ||
                                              _adding ||
                                              _sharedLinks.isEmpty
                                          ? null
                                          : () => setState(() {
                                              _selecting = !_selecting;
                                              if (!_selecting) {
                                                _selected.clear();
                                              }
                                            }),
                                      icon: Icon(
                                        _selecting
                                            ? Icons.check_box_outlined
                                            : Icons.checklist_rounded,
                                      ),
                                    ),
                                  ],
                                ),
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
                                        selected:
                                            (_filter ?? _preferences.filter) ==
                                            filter,
                                        showCheckmark: false,
                                        selectedColor: theme
                                            .colorScheme
                                            .secondaryContainer,
                                        onSelected: (_) =>
                                            setState(() => _filter = filter),
                                      ),
                                  ],
                                ),
                                if (_selecting) _selectionBar(visible),
                                const SizedBox(height: 12),
                                const Divider(height: 1),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (_inboxUnavailable ||
                          _sharedLinks.isEmpty ||
                          (showMedia && visible.isEmpty))
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
                                      : 'Try another search or change the media filter.',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: _inboxUnavailable
                                      ? _reload
                                      : _sharedLinks.isEmpty
                                      ? _showTutorial
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
                      else if (showMedia)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          sliver:
                              constraints.maxWidth >= 820 &&
                                  MediaQuery.textScalerOf(context).scale(16) <=
                                      16
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
      ),
    );
  }
}
