import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../../core/providers.dart';
import '../../models/capture_result.dart';

enum CapturePhase { idle, recording, uploading }

class CaptureState {
  const CaptureState({
    this.phase = CapturePhase.idle,
    this.filePath,
    this.seconds = 0,
  });
  final CapturePhase phase;
  final String? filePath; // ảnh / audio đã chọn, chờ gửi
  final int seconds; // đồng hồ ghi âm

  CaptureState copyWith({
    CapturePhase? phase,
    String? filePath,
    int? seconds,
    bool clearFile = false,
  }) => CaptureState(
    phase: phase ?? this.phase,
    filePath: clearFile ? null : (filePath ?? this.filePath),
    seconds: seconds ?? this.seconds,
  );
}

/// idle / recording / uploading cho màn Capture (4 mode dùng chung).
class CaptureController extends Notifier<CaptureState> {
  AudioRecorder? _recorder;
  Timer? _tick;

  @override
  CaptureState build() {
    ref.onDispose(() {
      _tick?.cancel();
      _recorder?.dispose();
    });
    return const CaptureState();
  }

  void setFile(String? path) =>
      state = state.copyWith(filePath: path, clearFile: path == null);

  /// Copy file trong assets/demo → temp để upload như file thật.
  Future<void> useDemoAsset(String name) async {
    final bytes = await rootBundle.load('assets/demo/$name');
    final f = File('${Directory.systemTemp.path}/$name');
    await f.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    setFile(f.path);
  }

  /// Bắt đầu ghi âm AAC-LC → .m4a; false nếu không có quyền mic.
  Future<bool> startRecording() async {
    _recorder ??= AudioRecorder();
    if (!await _recorder!.hasPermission()) return false;
    final path =
        '${Directory.systemTemp.path}/tb_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder!.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    state = state.copyWith(
      phase: CapturePhase.recording,
      seconds: 0,
      clearFile: true,
    );
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(seconds: state.seconds + 1);
      if (state.seconds >= 60) stopRecording(); // auto-stop 60 s
    });
    return true;
  }

  /// Dừng ghi âm; trả path file (null nếu không có gì).
  Future<String?> stopRecording() async {
    _tick?.cancel();
    if (state.phase != CapturePhase.recording) return null;
    final path = await _recorder!.stop();
    state = state.copyWith(phase: CapturePhase.idle, filePath: path);
    return path;
  }

  Future<CaptureResult> submitText(String text) =>
      _upload(() => ref.read(apiProvider).captureText(text));

  Future<CaptureResult> submitFile(String type, String path) =>
      _upload(() => ref.read(apiProvider).captureFile(type, path));

  Future<CaptureResult> _upload(Future<CaptureResult> Function() fn) async {
    state = state.copyWith(phase: CapturePhase.uploading);
    try {
      return await fn();
    } finally {
      state = state.copyWith(phase: CapturePhase.idle);
    }
  }
}

final captureControllerProvider =
    NotifierProvider.autoDispose<CaptureController, CaptureState>(
      CaptureController.new,
    );
