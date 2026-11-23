import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class AppPreferences extends ChangeNotifier {
  static const _channel = MethodChannel('clipshare/preferences');
  String theme = 'system';
  String filter = 'All';
  String sort = 'newest';
  bool saving = false;
  bool _disposed = false;

  ThemeMode get themeMode => switch (theme) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> load() async {
    try {
      final values = await _channel.invokeMapMethod<String, String>('read');
      if (_disposed) return;
      final t = values?['theme'];
      final f = values?['filter'];
      final s = values?['sort'];
      if (['system', 'light', 'dark'].contains(t)) theme = t!;
      if (['All', 'Photos', 'Videos'].contains(f)) filter = f!;
      if (['newest', 'oldest'].contains(s)) sort = s!;
      notifyListeners();
    } on MissingPluginException {
      // Desktop previews use the defaults; downloads are mobile only.
    } on PlatformException {
      // Keep usable defaults if preferences cannot be read.
    }
  }

  Future<bool> update({String? theme, String? filter, String? sort}) async {
    if (saving) return false;
    final values = {
      'theme': theme ?? this.theme,
      'filter': filter ?? this.filter,
      'sort': sort ?? this.sort,
    };
    saving = true;
    notifyListeners();
    try {
      if (await _channel.invokeMethod<bool>('write', values) != true) {
        return false;
      }
      if (_disposed) return false;
      this.theme = values['theme']!;
      this.filter = values['filter']!;
      this.sort = values['sort']!;
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } finally {
      saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.preferences,
    required this.storage,
    required this.onHelp,
  });
  final AppPreferences preferences;
  final String storage;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _heading(context, 'Appearance'),
              const Text('Choose how ClipShare looks on your device.'),
              const SizedBox(height: 14),
              _choices(
                context,
                {'system': 'System', 'light': 'Light', 'dark': 'Dark'},
                preferences.theme,
                (value) => preferences.update(theme: value),
              ),
              const SizedBox(height: 30),
              _heading(context, 'Your library'),
              const Text('Default media filter'),
              const SizedBox(height: 10),
              _choices(
                context,
                {'All': 'All', 'Photos': 'Photos', 'Videos': 'Videos'},
                preferences.filter,
                (value) => preferences.update(filter: value),
              ),
              const SizedBox(height: 20),
              const Text('Download order'),
              const SizedBox(height: 10),
              _choices(
                context,
                {'newest': 'Newest first', 'oldest': 'Oldest first'},
                preferences.sort,
                (value) => preferences.update(sort: value),
              ),
              const SizedBox(height: 30),
              _heading(context, 'On this device'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storage_rounded),
                title: const Text('Local media'),
                subtitle: Text('$storage stored in ClipShare'),
              ),
              const Text(
                'Downloads are grouped by source automatically. Deleting a download removes its local copy; exported copies stay in Photos, Gallery, or Files.',
              ),
              const SizedBox(height: 24),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.help_outline_rounded),
                title: const Text('Help and feedback'),
                subtitle: const Text(
                  'Supported links, version, and diagnostics',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onHelp,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  Widget _choices(
    BuildContext context,
    Map<String, String> options,
    String selected,
    Future<bool> Function(String) update,
  ) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final option in options.entries)
        ChoiceChip(
          label: Text(option.value),
          selected: selected == option.key,
          onSelected: preferences.saving
              ? null
              : (_) async {
                  final saved = await update(option.key);
                  if (!saved && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Couldn’t save settings. Please try again.',
                        ),
                      ),
                    );
                  }
                },
        ),
    ],
  );
}
