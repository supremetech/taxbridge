import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// `asset://demo/x.jpg` → Image.asset; còn lại Image.network.
Widget evidenceImage(
  String url, {
  BoxFit fit = BoxFit.cover,
  Alignment alignment = Alignment.topCenter,
}) {
  if (url.startsWith('asset://')) {
    return Image.asset(
      'assets/${url.substring('asset://'.length)}',
      fit: fit,
      alignment: alignment,
    );
  }
  return Image.network(
    url,
    fit: fit,
    alignment: alignment,
    errorBuilder: (_, _, _) =>
        const Center(child: Text('Không tải được bằng chứng')),
  );
}

Source _audioSource(String url) => url.startsWith('asset://')
    ? AssetSource(url.substring('asset://'.length))
    : UrlSource(url);

/// Khối **Bằng chứng** dưới hàng chip của Event / Movement Detail.
class EvidenceBlock extends StatefulWidget {
  const EvidenceBlock({
    super.key,
    required this.captureType,
    this.evidenceText,
    this.evidenceUrl,
  });

  final String captureType;
  final String? evidenceText;
  final String? evidenceUrl;

  @override
  State<EvidenceBlock> createState() => _EvidenceBlockState();
}

class _EvidenceBlockState extends State<EvidenceBlock> {
  AudioPlayer? _player;
  bool _playing = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    _player ??= AudioPlayer()
      ..onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      });
    if (_playing) {
      await _player!.stop();
      setState(() => _playing = false);
    } else {
      await _player!.play(_audioSource(widget.evidenceUrl!));
      setState(() => _playing = true);
    }
  }

  void _zoom(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                child: evidenceImage(
                  widget.evidenceUrl!,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Đóng'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.evidenceText;
    final url = widget.evidenceUrl;
    final isImage = widget.captureType.startsWith('IMAGE');
    final isAudio = widget.captureType == 'AUDIO';

    Widget body;
    if (text == null && url == null) {
      body = Text(
        'Không có bằng chứng đính kèm',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.outline,
        ),
      );
    } else if (isImage && url != null) {
      body = GestureDetector(
        onTap: () => _zoom(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 160,
            width: double.infinity,
            child: evidenceImage(url),
          ),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (text != null)
            Text(
              '“$text”',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          if (isAudio && url != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _toggle,
                icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
                label: Text(_playing ? 'Dừng' : 'Nghe lại'),
              ),
            ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bằng chứng',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          body,
        ],
      ),
    );
  }
}
