import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import '../models/meeting_note.dart';
import '../services/audio_service.dart';
import '../services/gemini_service.dart';
import '../services/storage_service.dart';
import 'result_screen.dart';
import 'settings_screen.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> with TickerProviderStateMixin {
  final AudioService _audioService = AudioService();
  Timer? _timer;
  int _secondsRecorded = 0;
  bool _isPaused = false;
  bool _isProcessing = false;
  String _processingStep = 'Menyimpan rekaman...';
  String? _errorMessage;

  StreamSubscription<Amplitude>? _amplitudeSub;
  double _currentAmplitude = -160.0;
  final List<double> _waveLevels = List.generate(24, (_) => 0.1);

  @override
  void initState() {
    super.initState();
    _startRecordingFlow();
  }

  Future<void> _startRecordingFlow() async {
    try {
      final sampleRate = await StorageService.getSampleRate();
      await _audioService.startRecording(sampleRate: sampleRate);

      _startTimer();

      _amplitudeSub = _audioService.amplitudeStream.listen((amp) {
        if (mounted) {
          setState(() {
            _currentAmplitude = amp.current;
            // Normalize amplitude (-60dB to 0dB -> 0.0 to 1.0)
            final normalized = ((amp.current + 60) / 60).clamp(0.05, 1.0).toDouble();
            _waveLevels.removeAt(0);
            _waveLevels.add(normalized);
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!_isPaused && mounted) {
        setState(() {
          _secondsRecorded++;
        });
      }
    });
  }

  String _formatTimer(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _togglePause() async {
    if (_isPaused) {
      await _audioService.resume();
      setState(() => _isPaused = false);
    } else {
      await _audioService.pause();
      setState(() => _isPaused = true);
    }
  }

  Future<void> _stopAndProcess() async {
    _timer?.cancel();
    _amplitudeSub?.cancel();

    final apiKey = await StorageService.getApiKey();
    if (apiKey.isEmpty) {
      _showMissingApiKeyDialog();
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingStep = 'Menyimpan file audio rekaman...';
    });

    try {
      final audioPath = await _audioService.stop();
      if (audioPath == null) {
        throw Exception('File rekaman tidak tersimpan.');
      }

      final model = await StorageService.getModel();

      setState(() {
        _processingStep = 'Mengirim audio ke Gemini AI ($model)...';
      });

      // Update progress text after 2 seconds to keep user informed
      Timer(const Duration(seconds: 3), () {
        if (mounted && _isProcessing) {
          setState(() {
            _processingStep = 'Menyaring candaan & obrolan santai...';
          });
        }
      });

      Timer(const Duration(seconds: 7), () {
        if (mounted && _isProcessing) {
          setState(() {
            _processingStep = 'Menyusun keputusan rapat & action items...';
          });
        }
      });

      final note = await GeminiService.processMeetingAudio(
        audioPath: audioPath,
        durationSeconds: _secondsRecorded,
        apiKey: apiKey,
        model: model,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ResultScreen(note: note, isNew: true),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  void _showMissingApiKeyDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181B21),
        title: const Text('API Key Diperlukan', style: TextStyle(color: Color(0xFFF1F5F9))),
        content: const Text(
          'Anda belum mengisi API Key Gemini. Masukkan API Key agar HerzNote dapat memproses audio rapat Anda.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            child: const Text('Buka Pengaturan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelRecording() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181B21),
        title: const Text('Batalkan Rekaman?', style: TextStyle(color: Color(0xFFF1F5F9))),
        content: const Text(
          'Audio yang sedang direkam akan dibuang dan tidak diproses.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Lanjutkan Rapat', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Batalkan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _timer?.cancel();
      _amplitudeSub?.cancel();
      await _audioService.stop();
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amplitudeSub?.cancel();
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isProcessing) {
      return _buildProcessingScreen();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        title: const Text('Perekaman Rapat'),
        backgroundColor: const Color(0xFF181B21),
        foregroundColor: const Color(0xFFF1F5F9),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _cancelRecording,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
          child: Column(
            children: [
              const Spacer(),

              // STATUS BADGE
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _isPaused ? const Color(0xFF334155) : const Color(0xFF7F1D1D).withOpacity(0.4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isPaused ? const Color(0xFF64748B) : const Color(0xFFDC2626),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isPaused ? const Color(0xFF94A3B8) : const Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isPaused ? 'REKAMAN DIJEDA' : 'SEDANG MEREKAM RAPAT...',
                      style: TextStyle(
                        color: _isPaused ? const Color(0xFFCBD5E1) : const Color(0xFFFCA5A5),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // TIMER COUNTER
              Text(
                _formatTimer(_secondsRecorded),
                style: const TextStyle(
                  color: Color(0xFFF1F5F9),
                  fontSize: 54,
                  fontWeight: FontWeight.w300,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                ),
              ),

              const SizedBox(height: 32),

              // AUDIO SOUNDWAVE BARS
              Container(
                height: 80,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(_waveLevels.length, (idx) {
                    final height = _isPaused ? 8.0 : (_waveLevels[idx] * 64).clamp(6.0, 64.0).toDouble();
                    return Container(
                      width: 5,
                      height: height,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: _isPaused ? const Color(0xFF475569) : const Color(0xFF10B981),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 16),

              // GUIDANCE TIP
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF181B21),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF262A34)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Color(0xFF10B981)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Taruh HP di tengah meja rapat. HerzNote akan merekam terus tanpa terputus.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7F1D1D),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Color(0xFFFECACA), fontSize: 13),
                  ),
                ),
              ],

              const Spacer(),

              // CONTROLS
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // PAUSE / RESUME BUTTON
                  IconButton.filled(
                    onPressed: _togglePause,
                    icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 28),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF262A34),
                      foregroundColor: const Color(0xFFF1F5F9),
                      padding: const EdgeInsets.all(18),
                    ),
                  ),

                  // STOP & PROCESS BUTTON
                  SizedBox(
                    height: 64,
                    child: ElevatedButton.icon(
                      onPressed: _stopAndProcess,
                      icon: const Icon(Icons.stop, size: 26),
                      label: const Text(
                        'Selesai & Buat Notulensi',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(32),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFF10B981),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Memproses Rapat...',
                  style: TextStyle(
                    color: Color(0xFFF1F5F9),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _processingStep,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF181B21),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF262A34)),
                  ),
                  child: const Text(
                    'Gemini AI sedang mendengarkan rekaman rapat, menyaring obrolan candaan, dan merangkum keputusan rapat beserta action items.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.5),
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
