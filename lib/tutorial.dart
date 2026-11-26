import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

class ClipShareTutorial extends StatefulWidget {
  const ClipShareTutorial({super.key});

  @override
  State<ClipShareTutorial> createState() => _ClipShareTutorialState();
}

class _ClipShareTutorialState extends State<ClipShareTutorial> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    final steps = [
      (
        icon: Icons.add_rounded,
        title: 'Copy and paste a link',
        instructions:
            'Open a public post in Instagram, X, YouTube, TikTok, or Pinterest. In its share menu, choose Copy link. A direct HTTPS link to a photo or MP4 works too.\n\n'
            'In ClipShare, press and hold the Media link field and tap Paste. Then tap the + button to start the download.',
      ),
      (
        icon: Icons.share_outlined,
        title: 'Share from another app',
        instructions:
            'Open the post’s Share menu and choose ClipShare. If you only see options for sharing inside that app, look for More or Share via.\n\n'
            '${isIOS ? 'Tap Add to ClipShare for a post or Download for a direct media link. For Instagram, tap Continue with Instagram and sign in if prompted.' : 'Tap Add for a post or Download for a direct media link.'}',
      ),
      (
        icon: Icons.download_rounded,
        title: 'Check your download',
        instructions:
            'Open Downloads and tap the folder for the source, such as TikTok. Direct file links usually appear in Other.\n\n'
            'If the item says Pending download, tap its download arrow. Wait until it says Saved. If it fails, tap Retry download next to the item.',
      ),
      (
        icon: Icons.play_circle_outline_rounded,
        title: 'Open and export saved media',
        instructions:
            'Tap a saved thumbnail to play the video or view the photo.\n\n'
            'To keep a copy outside ClipShare, open the item’s menu and choose ${isIOS ? 'Save to Photos or Save to Files.' : 'Save to Gallery.'}',
      ),
      (
        icon: Icons.search_rounded,
        title: 'Find and manage downloads',
        instructions:
            'Tap the search icon to find items by title or source. Inside a folder or search, use Photos or Videos to filter the results.\n\n'
            'Open an item’s menu to delete it, or tap Select downloads to manage several items at once. You can replay this tutorial in Settings.',
      ),
    ];
    final step = steps[_step];
    final lastStep = _step == steps.length - 1;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('ClipShare tutorial')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              key: ValueKey(_step),
              padding: const EdgeInsets.all(24),
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Icon(
                        step.icon,
                        color: theme.colorScheme.onSecondaryContainer,
                        size: 32,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Step ${_step + 1} of ${steps.length}',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  header: true,
                  child: Text(step.title, style: theme.textTheme.headlineSmall),
                ),
                const SizedBox(height: 12),
                Text(step.instructions, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 28),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Skip tutorial'),
                    ),
                    if (_step > 0)
                      OutlinedButton(
                        onPressed: () => setState(() => _step--),
                        child: const Text('Back'),
                      ),
                    FilledButton(
                      onPressed: lastStep
                          ? () => Navigator.of(context).pop()
                          : () => setState(() => _step++),
                      child: Text(lastStep ? 'Done' : 'Next'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
