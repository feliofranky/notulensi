import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;
  DateTime? _startTime;

  AudioRecorder get recorder => _recorder;
  String? get currentPath => _currentPath;

  Future<bool> checkAndRequestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<String> startRecording({int sampleRate = 16000}) async {
    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) {
      throw Exception('Izin mikrofon tidak diberikan. Silakan izinkan perekaman audio di pengaturan HP.');
    }

    final dir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory(p.join(dir.path, 'recordings'));
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = p.join(recordingsDir.path, 'meeting_$timestamp.wav');
    _currentPath = filePath;
    _startTime = DateTime.now();

    // 16kHz mono WAV provides crystal-clear human voice clarity with native Gemini multimodal support
    final config = RecordConfig(
      encoder: AudioEncoder.wav,
      bitRate: 64000,
      sampleRate: sampleRate,
      numChannels: 1,
    );

    await _recorder.start(config, path: filePath);
    return filePath;
  }

  Future<void> pause() async {
    if (await _recorder.isRecording()) {
      await _recorder.pause();
    }
  }

  Future<void> resume() async {
    if (await _recorder.isPaused()) {
      await _recorder.resume();
    }
  }

  Future<String?> stop() async {
    final path = await _recorder.stop();
    _currentPath = path;
    return path;
  }

  Future<bool> isRecording() async {
    return await _recorder.isRecording();
  }

  Future<bool> isPaused() async {
    return await _recorder.isPaused();
  }

  Stream<Amplitude> get amplitudeStream {
    return _recorder.onAmplitudeChanged(const Duration(milliseconds: 100));
  }

  void dispose() {
    _recorder.dispose();
  }
}
