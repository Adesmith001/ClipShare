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

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

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
