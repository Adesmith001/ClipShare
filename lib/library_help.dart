import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'library.dart';

String diagnosticReport(
  Map<Object?, Object?> info,
  List<DownloadEntry> entries,
) {
  final states = <String, int>{};
  final errors = <String>{};
  final lastError = info['lastError'];
  if (lastError is String && RegExp(r'^[a-z_0-9]{1,48}$').hasMatch(lastError)) {
    errors.add(lastError);
  }
  for (final entry in entries) {
    final state = entry['state'];
    if (state is String &&
        const {
          'pending',
          'downloading',
          'saved',
          'failed',
          'cancelled',
        }.contains(state)) {
      states.update(state, (n) => n + 1, ifAbsent: () => 1);
    }
    final code = entry['error'];
    if (code is String && RegExp(r'^[a-z_0-9]{1,48}$').hasMatch(code)) {
      errors.add(code);
    }
  }
  return [
    'ClipShare beta report',
    'Version: ${info['version'] ?? 'unknown'} (${info['build'] ?? 'unknown'})',
    'OS: ${info['os'] ?? defaultTargetPlatform.name}',
    'Local media: ${formatBytes(info['storageBytes'] as num? ?? 0)}',
    'Entries: ${entries.length}',
    for (final state in states.entries) '${state.key}: ${state.value}',
    'Error codes: ${errors.isEmpty ? 'none' : (errors.toList()..sort()).join(', ')}',
    'Recovered records: ${info['recoveredEntries'] ?? 0}',
    '',
    'What happened:',
    '',
    'Steps to reproduce:',
    '',
    'Expected result:',
    '',
    'URLs, media titles, folder names, and account/session data are excluded.',
  ].join('\n');
}

class LibraryHelp extends StatelessWidget {
  const LibraryHelp({super.key, required this.info, required this.entries});
  final Map<Object?, Object?> info;
  final List<DownloadEntry> entries;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Help and feedback')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'ClipShare ${info['version'] ?? 'beta'} · build ${info['build'] ?? 'unknown'}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          '${formatBytes(info['storageBytes'] as num? ?? 0)} of local media · ${info['os'] ?? defaultTargetPlatform.name}',
        ),
        if ((info['recoveredEntries'] as num? ?? 0) > 0)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Some unreadable library records were recovered. Healthy downloads are still available.',
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: diagnosticReport(info, entries)),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Report copied. Add your steps and share it with the beta organiser.',
                  ),
                ),
              );
            }
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy diagnostic report'),
        ),
        const SizedBox(height: 24),
        _section(
          context,
          'Save your first download',
          'Paste a supported HTTPS link in Media link and tap Add link. You can also share a link from another app to ClipShare. '
              'Social links marked Pending download need you to open ClipShare and tap the download button.',
        ),
        _section(
          context,
          'Supported links',
          'Public Pinterest Pins and pin.it links, X posts, Instagram photos/Reels/carousels, and YouTube videos/Shorts with a combined audio/video MP4. '
              'Direct HTTPS MP4, JPEG, PNG, and WebP links are supported. TikTok, playlists, and live streams without a downloadable MP4 are not supported. '
              'Provider restrictions can change; private, deleted, restricted, or sign-in-only posts may be unavailable.',
        ),
        _section(
          context,
          'Instagram sign-in',
          defaultTargetPlatform == TargetPlatform.iOS
              ? 'For posts requiring sign-in, share the Instagram post to ClipShare on iPhone and continue in Instagram’s page inside the share sheet. '
                    'The website session stays in the extension’s on-device WebKit store. Use Disconnect Instagram in the share sheet to clear Instagram website data. '
                    'Pasting in the main app does not use that session.'
              : 'The Android paste and share-link resolver accesses public posts without a signed-in Instagram session. '
                    'If Instagram requires sign-in, that post cannot currently be downloaded on Android.',
        ),
        _section(
          context,
          'Folders, search, and selection',
          'Create folders from the folder menu. Use an item’s menu to move it, or tap Select downloads for batch actions. '
              'Select all visible respects your search and filters. Selected items remain selected when filters change; check the selected count before an action. '
              'Removing a folder moves its items to Unfiled. Search matches titles, sources, and link paths. New links start in Unfiled. Pending items and retries keep their chosen folder across slides. Already-saved duplicates keep their existing folder; use Move to folder to change it.',
        ),
        _section(
          context,
          'Local copies and exports',
          'Saved means a copy is stored in ClipShare. Save to Photos/Gallery or Files creates an exported copy. '
              'Deleting a download removes ClipShare’s copy; exported copies remain. Uninstalling the app may remove its local downloads. '
              'Declining Photos access or cancelling an export keeps the local copy.',
        ),
        _section(
          context,
          'Transfers and recovery',
          'Downloads use your connection, including mobile data. Progress and completion depend on the device’s background scheduling. '
              'Open ClipShare to refresh after an interruption. Retry failed or cancelled items; use the item menu to remove unwanted entries.',
        ),
        _section(
          context,
          'Report a problem',
          'Copy the diagnostic report, add what happened and how to reproduce it, then share it with your beta organiser. '
              'The report excludes links, media titles, folder names, passwords, and website sessions. Add a screenshot only if you want to share its contents.',
        ),
      ],
    ),
  );

  Widget _section(BuildContext context, String title, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(text),
      ],
    ),
  );
}
