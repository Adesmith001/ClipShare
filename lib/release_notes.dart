import 'package:material_ui/material_ui.dart';

typedef ReleaseNotes = ({String version, Map<String, String> features});

const releases = <String, ReleaseNotes>{
  '14': (
    version: '0.2.5',
    features: {
      'Select downloads faster': 'Long-press a download to start selecting. Tap other photos or videos to add them. Use Select all to select everything in the current view, then choose an action.',
      'Swipe through carousels': 'Open any carousel item and swipe left or right. The counter shows your place, and you can play video slides right inside the viewer.',
      'Improved Reel sharing on iPhone': 'In Instagram, open a Reel and tap Share, then choose ClipShare and Continue with Instagram.',
      'Updates when you open ClipShare': 'If ClipShare shows Update required, tap Update now to install the latest release through your store.',
    },
  ),
};

class ReleaseNotesScreen extends StatelessWidget {
  const ReleaseNotesScreen({super.key, required this.notes});

  final ReleaseNotes notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('What’s new')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Version ${notes.version}',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              for (final feature in notes.features.entries) ...[
                Text(feature.key, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(feature.value),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Align(
          alignment: Alignment.center,
          heightFactor: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 592),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Continue'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
