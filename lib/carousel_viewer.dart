part of 'main.dart';

class _CarouselViewer extends StatefulWidget {
  const _CarouselViewer({
    required this.slides,
    required this.initialPage,
    required this.preview,
    required this.videoUri,
  });

  final List<DownloadEntry> slides;
  final int initialPage;
  final Future<Uint8List?> Function(String) preview;
  final Future<String?> Function(String) videoUri;

  @override
  State<_CarouselViewer> createState() => _CarouselViewerState();
}

class _CarouselViewerState extends State<_CarouselViewer> {
  late int _page = widget.initialPage;
  late final _controller = PageController(initialPage: _page);
  final _previews = <String, Future<Uint8List?>>{};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.slides[_page];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          mediaTitle(current),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(child: Text(current['position'] as String)),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.slides.length,
        onPageChanged: (page) => setState(() {
          _previews.removeWhere((id, _) => id != widget.slides[page]['id']);
          _page = page;
        }),
        itemBuilder: (context, index) {
          final slide = widget.slides[index];
          final id = slide['id'] as String;
          final isImage = mediaIsImage(slide);
          if (slide['state'] != 'saved') {
            return const Center(child: Text('This slide hasn’t been saved.'));
          }
          final preview = FutureBuilder<Uint8List?>(
            future: _previews.putIfAbsent(id, () => widget.preview(id)),
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes == null) {
                return Center(
                  child: !isImage
                      ? const Icon(Icons.movie_outlined)
                      : snapshot.connectionState == ConnectionState.done
                      ? const Text('This image is unavailable.')
                      : const CircularProgressIndicator(),
                );
              }
              final image = Image.memory(
                bytes,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => isImage
                    ? const Text('This image is unavailable.')
                    : const Icon(Icons.movie_outlined),
              );
              return Center(
                child: isImage ? InteractiveViewer(child: image) : image,
              );
            },
          );
          if (!isImage && index == _page) {
            return _CarouselVideo(
              loadUri: () => widget.videoUri(id),
              preview: preview,
            );
          }
          return preview;
        },
      ),
    );
  }
}

class _CarouselVideo extends StatefulWidget {
  const _CarouselVideo({required this.loadUri, required this.preview});

  final Future<String?> Function() loadUri;
  final Widget preview;

  @override
  State<_CarouselVideo> createState() => _CarouselVideoState();
}

class _CarouselVideoState extends State<_CarouselVideo> {
  VideoPlayerController? _player;
  bool _loading = false;
  bool _unavailable = false;

  Future<void> _play() async {
    setState(() => _loading = true);
    try {
      final uri = Uri.tryParse(await widget.loadUri() ?? '');
      if (!mounted) return;
      final player = switch (uri?.scheme) {
        'file' => VideoPlayerController.file(File.fromUri(uri!)),
        'content' => VideoPlayerController.contentUri(uri!),
        _ => null,
      };
      if (player == null) {
        setState(() {
          _loading = false;
          _unavailable = true;
        });
        return;
      }
      _player = player;
      await player.initialize();
      if (!mounted) return;
      await player.play();
      if (mounted) setState(() => _loading = false);
    } on PlatformException {
      if (!mounted) return;
      unawaited(_player?.dispose());
      _player = null;
      setState(() {
        _loading = false;
        _unavailable = true;
      });
    }
  }

  @override
  void dispose() {
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_unavailable) {
      return const Center(child: Text('This video is unavailable.'));
    }
    if (player == null) {
      return Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          widget.preview,
          Center(
            child: IconButton.filled(
              tooltip: 'Play video',
              onPressed: _play,
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: player.value.aspectRatio,
              child: VideoPlayer(player),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Row(
            children: [
              ValueListenableBuilder(
                valueListenable: player,
                builder: (context, value, _) => IconButton(
                  tooltip: value.isPlaying ? 'Pause video' : 'Play video',
                  onPressed: value.isPlaying ? player.pause : player.play,
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
              ),
              Expanded(
                child: VideoProgressIndicator(player, allowScrubbing: true),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ],
    );
  }
}
