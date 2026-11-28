import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

typedef RequiredUpdate = ({String store, Uri? url});

class AppUpdates extends ChangeNotifier {
  static const _channel = MethodChannel('clipshare/updates');
  static const _iosFeed = String.fromEnvironment('IOS_UPDATE_FEED');
  static final _testFlight = Uri.https(
    'testflight.apple.com',
    '/join/Cp62apYT',
  );
  RequiredUpdate? requiredUpdate;
  bool starting = false;
  bool startFailed = false;
  bool _checking = false;
  bool _disposed = false;

  Future<void> check() async {
    if (kIsWeb || _checking || starting) return;
    _checking = true;
    try {
      final update = switch (defaultTargetPlatform) {
        TargetPlatform.android => await _checkPlay(),
        TargetPlatform.iOS when _iosFeed.isNotEmpty => await _checkIOS(),
        _ => null,
      };
      if (_disposed || update == requiredUpdate) return;
      requiredUpdate = update;
      startFailed = false;
      notifyListeners();
    } on PlatformException {
      // A failed check does not establish whether an update is available.
    } on MissingPluginException {
      // App updates are handled by the mobile platform.
    } on IOException {
      // Continue with the last confirmed check when the feed is unavailable.
    } on TimeoutException {
      // An unavailable feed does not block users on first launch.
    } on FormatException {
      // Ignore malformed release metadata.
    } finally {
      _checking = false;
    }
  }

  Future<RequiredUpdate?> _checkPlay() async {
    final store = await _channel.invokeMethod<String>('check');
    return store == 'Google Play' ? (store: store!, url: null) : null;
  }

  Future<RequiredUpdate?> _checkIOS() async {
    final endpoint = Uri.tryParse(_iosFeed);
    if (endpoint == null ||
        endpoint.scheme != 'https' ||
        endpoint.host.isEmpty) {
      return null;
    }
    final install = await _channel.invokeMapMethod<String, Object?>(
      'iosInstall',
    );
    if (install == null) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(endpoint);
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw const HttpException('Release feed unavailable');
      }
      final data = <int>[];
      await for (final bytes in response.timeout(const Duration(seconds: 5))) {
        if (data.length + bytes.length > 8192) {
          throw const FormatException('Release feed too large');
        }
        data.addAll(bytes);
      }
      return iosUpdateFor(install, jsonDecode(utf8.decode(data)));
    } finally {
      client.close(force: true);
    }
  }

  @visibleForTesting
  static RequiredUpdate? iosUpdateFor(
    Map<String, Object?> install,
    Object? feed,
  ) {
    if (feed is! Map) return null;
    final releases = feed[install['bundleId']];
    if (releases is! Map) return null;
    final distribution = install['distribution'];
    final release = releases[distribution];
    if (release is! Map) return null;
    final installedBuild = install['build'];
    final minimumBuild = release['minimumBuild'];
    final installedOS = _osVersion(install['osVersion']);
    final minimumOS = _osVersion(release['minimumOS']);
    if (installedBuild is! int ||
        installedBuild <= 0 ||
        minimumBuild is! int ||
        minimumBuild <= installedBuild ||
        installedOS == null ||
        minimumOS == null ||
        installedOS < minimumOS) {
      return null;
    }
    if (distribution == 'testflight') {
      return (store: 'TestFlight', url: _testFlight);
    }
    final appId = release['appStoreId'];
    if (distribution == 'appStore' &&
        appId is String &&
        RegExp(r'^[0-9]+$').hasMatch(appId)) {
      return (
        store: 'the App Store',
        url: Uri.https('apps.apple.com', '/app/id$appId'),
      );
    }
    return null;
  }

  static int? _osVersion(Object? value) {
    if (value is! String ||
        !RegExp(r'^\d{1,3}(\.\d{1,3}){0,2}$').hasMatch(value)) {
      return null;
    }
    final parts = value.split('.').map(int.parse).toList();
    return parts[0] * 1000000 +
        (parts.length > 1 ? parts[1] * 1000 : 0) +
        (parts.length > 2 ? parts[2] : 0);
  }

  Future<void> start() async {
    final update = requiredUpdate;
    if (update == null || starting) return;
    starting = true;
    startFailed = false;
    notifyListeners();
    var started = false;
    try {
      final url = update.url;
      started = url == null
          ? await _channel.invokeMethod<bool>('start') == true
          : await _openStore(url);
    } on PlatformException {
      // Leave the update screen visible so the user can try again.
    } on MissingPluginException {
      // A platform store handler is required to start an update.
    } finally {
      starting = false;
      startFailed = !started;
      if (!_disposed) {
        notifyListeners();
        unawaited(check());
      }
    }
  }

  static Future<bool> _openStore(Uri url) async =>
      await _channel.invokeMethod<bool>('openStore', url.toString()) == true;

  static Future<bool> openTestFlight() async {
    try {
      return await _openStore(_testFlight);
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class UpdateGate extends StatelessWidget {
  const UpdateGate({super.key, required this.updates, required this.child});

  final AppUpdates updates;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: updates,
    builder: (context, _) {
      final update = updates.requiredUpdate;
      return Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: update != null,
            child: ExcludeFocus(excluding: update != null, child: child),
          ),
          if (update != null)
            Scaffold(
              body: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Update required',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Install the latest version of ClipShare from ${update.store} to continue.',
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: updates.starting ? null : updates.start,
                            child: Text(
                              updates.starting
                                  ? 'Opening update…'
                                  : 'Update now',
                            ),
                          ),
                          if (updates.startFailed)
                            const Text(
                              'The update didn’t finish. Tap Update now to try again.',
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
