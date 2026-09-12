import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/widgets.dart';
import '../../models/capture_result.dart';
import 'capture_controller.dart';

/// Một màn, 5 mode: text | voice | receipt | transfer | history (Phase 2 ①).
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key, required this.mode});
  final String mode;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  final _text = TextEditingController();
  final _picker = ImagePicker();

  String get _title => switch (widget.mode) {
    'voice' => 'Nói giao dịch',
    'receipt' => 'Chụp chứng từ',
    'transfer' => 'Chụp chuyển khoản',
    'history' => 'Đối soát lịch sử chuyển khoản',
    _ => 'Nhập giao dịch',
  };

  String get _type => switch (widget.mode) {
    'voice' => 'AUDIO',
    'receipt' => 'IMAGE_RECEIPT',
    'transfer' => 'IMAGE_TRANSFER',
    'history' => 'IMAGE_BANK_HISTORY',
    _ => 'TEXT',
  };

  bool get _isImage =>
      widget.mode == 'receipt' ||
      widget.mode == 'transfer' ||
      widget.mode == 'history';

  CaptureController get _ctl => ref.read(captureControllerProvider.notifier);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Sau `DONE`: EVENT → Event Detail; MONEY_MOVEMENT → Movement Detail;
  /// MONEY_MOVEMENT_BATCH → Đối soát (rỗng → ở lại). FAILED → ở lại.
  Future<void> _handle(Future<CaptureResult> fut) async {
    try {
      final r = await fut;
      if (!mounted) return;
      if (!r.isDone) {
        showInfo(context, 'Không xử lý được. Thử lại.');
        return;
      }
      invalidateAll(ref);
      if (r.isBatch) {
        if (r.resultIds.isEmpty) {
          showInfo(
            context,
            'Không có giao dịch mới (${r.skippedCount} dòng đã có trong sổ)',
          );
          return;
        }
        context.go(
          '/reconcile?ids=${r.resultIds.join(',')}&skipped=${r.skippedCount}',
        );
        return;
      }
      // Phase 2 ②: chứng từ in ngày khác hôm nay.
      final at = r.occurredAt?.toLocal();
      if (at != null && dateKey(at) != todayKey()) {
        showInfo(context, 'Ghi vào ngày ${displayDate(dateKey(at))}');
      }
      final route = r.resultType == 'MONEY_MOVEMENT'
          ? '/movements/${r.resultId}'
          : '/events/${r.resultId}';
      context.push(route);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _sendText() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    FocusScope.of(context).unfocus();
    await _handle(_ctl.submitText(t));
  }

  Future<void> _sendFile() async {
    final path = ref.read(captureControllerProvider).filePath;
    if (path == null) return;
    await _handle(_ctl.submitFile(_type, path));
  }

  Future<void> _pick(ImageSource src) async {
    try {
      final x = await _picker.pickImage(
        source: src,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (x != null) _ctl.setFile(x.path);
    } catch (e) {
      if (mounted) {
        showError(context, e, fallback: 'Không mở được camera / thư viện.');
      }
    }
  }

  Future<void> _toggleRecord() async {
    final s = ref.read(captureControllerProvider);
    if (s.phase == CapturePhase.recording) {
      final path = await _ctl.stopRecording();
      if (path != null) await _sendFile(); // tự upload sau khi dừng
    } else {
      final ok = await _ctl.startRecording();
      if (!ok && mounted) showInfo(context, 'Chưa được cấp quyền micro.');
    }
  }

  /// DEMO=true: chọn file trong assets/demo thay camera / mic.
  Future<void> _useDemo() async {
    if (widget.mode == 'text') {
      // Simulator không gõ được tiếng Việt: điền sẵn câu mẫu UC2.
      _text.text = 'Bán 3 hộp collagen 450 nghìn chuyển khoản';
      return;
    }
    String? name = switch (widget.mode) {
      'voice' => 'sale_voice.m4a',
      'receipt' => 'receipt.jpg',
      'history' => 'bank_history.jpg',
      _ => null,
    };
    if (widget.mode == 'transfer') {
      name = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text(
                  'Chuyển khoản 450.000đ · LAN 3HOP (khớp đơn)',
                ),
                onTap: () => Navigator.pop(ctx, 'transfer_match.jpg'),
              ),
              ListTile(
                leading: const Icon(Icons.savings_outlined),
                title: const Text('Chuyển khoản 380.000đ · COC MINH (đặt cọc)'),
                onTap: () => Navigator.pop(ctx, 'transfer_deposit.jpg'),
              ),
            ],
          ),
        ),
      );
    }
    if (name == null) return;
    try {
      await _ctl.useDemoAsset(name);
    } catch (_) {
      if (mounted) {
        showInfo(context, 'Chưa có file demo $name trong assets/demo.');
      }
      return;
    }
    if (widget.mode == 'voice' && mounted) await _sendFile();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(captureControllerProvider);
    final busy = s.phase == CapturePhase.uploading;

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: BusyOverlay(
        busy: busy,
        text: 'Đang đọc…',
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.mode == 'text') ..._textBody(),
            if (widget.mode == 'voice') ..._voiceBody(s),
            if (_isImage) ..._imageBody(s),
            if (demoMode) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: busy ? null : _useDemo,
                icon: const Icon(Icons.folder_open),
                label: const Text('Dùng file demo'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _textBody() => [
    TextField(
      controller: _text,
      minLines: 3,
      maxLines: 6,
      autofocus: true,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _sendText(),
      decoration: const InputDecoration(
        labelText: 'Nội dung',
        hintText: 'VD: Bán 3 hộp collagen 450 nghìn chuyển khoản',
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 16),
    FilledButton(onPressed: _sendText, child: const Text('Gửi')),
  ];

  List<Widget> _voiceBody(CaptureState s) {
    final rec = s.phase == CapturePhase.recording;
    return [
      const SizedBox(height: 24),
      Center(
        child: GestureDetector(
          onTap: _toggleRecord,
          child: CircleAvatar(
            radius: 56,
            backgroundColor: rec
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
            child: Icon(
              rec ? Icons.stop : Icons.mic,
              size: 48,
              color: Colors.white,
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Center(
        child: Text(
          rec
              ? 'Đang ghi… ${s.seconds}s (tối đa 60s) — chạm để dừng'
              : 'Chạm để bắt đầu nói',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _toggleRecord,
        child: Text(rec ? 'Dừng và gửi' : 'Bắt đầu ghi âm'),
      ),
    ];
  }

  List<Widget> _imageBody(CaptureState s) => [
    if (s.filePath != null)
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(File(s.filePath!), height: 320, fit: BoxFit.contain),
      )
    else
      Container(
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(switch (widget.mode) {
          'transfer' => 'Chụp màn hình báo có / chuyển khoản',
          'history' => 'Chụp màn hình lịch sử giao dịch trong app ngân hàng',
          _ => 'Chụp hóa đơn, phiếu mua hàng',
        }),
      ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pick(ImageSource.camera),
            icon: const Icon(Icons.photo_camera),
            label: const Text('Chụp ảnh'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pick(ImageSource.gallery),
            icon: const Icon(Icons.photo_library),
            label: const Text('Thư viện'),
          ),
        ),
      ],
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: s.filePath == null ? null : _sendFile,
      child: const Text('Gửi'),
    ),
  ];
}
