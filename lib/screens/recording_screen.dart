import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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
  int _processingSeconds = 0;
  Timer? _processingTimer;
  String _processingStep = 'Menyimpan berkas audio...';
  String? _errorMessage;

  String? _cachedAudioPath;
  bool _hasStopped = false;

  StreamSubscription<Amplitude>? _amplitudeSub;
  double _currentAmplitude = -160.0;
  final List<double> _waveLevels = List.generate(24, (_) => 0.0);

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

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
            // Noise gate di -44 dB agar saat hening bar tetap pendek halus,
            // dan saat ada suara berbicara langsung melompat hidup & responsif
            final raw = ((amp.current + 44) / 40).clamp(0.0, 1.0).toDouble();
            final shaped = math.pow(raw, 1.6).toDouble();
            _waveLevels.removeAt(0);
            _waveLevels.add(shaped);
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
    if (_hasStopped) return;

    if (_isPaused) {
      await _audioService.resume();
      _pulseController.repeat(reverse: true);
      setState(() => _isPaused = false);
    } else {
      await _audioService.pause();
      _pulseController.stop();
      setState(() => _isPaused = true);
    }
  }

  Future<void> _stopAndProcess() async {
    final apiKey = await StorageService.getApiKey();
    if (apiKey.isEmpty) {
      _showMissingApiKeyDialog();
      return;
    }

    // Cegah pengiriman rekaman terlalu singkat (< 5 detik) yang rentan kosong
    if (!_hasStopped && _secondsRecorded < 5) {
      setState(() {
        _errorMessage = 'Durasi rekaman terlalu singkat (minimal 5 detik) untuk menyusun notulensi.';
      });
      return;
    }

    _timer?.cancel();
    _amplitudeSub?.cancel();

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _processingSeconds = 0;
      _processingStep = _hasStopped ? 'Menyiapkan berkas audio...' : 'Menyimpan berkas audio...';
    });

    _processingTimer?.cancel();
    _processingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isProcessing) {
        setState(() {
          _processingSeconds++;
        });
      }
    });

    try {
      // Pastikan layar & CPU tetap terjaga selama upload + pemrosesan AI agar koneksi tidak terputus
      await _audioService.ensureKeepAwake();

      // Hanya panggil stop() jika belum pernah distop sebelumnya (mencegah freeze/hang recorder)
      if (!_hasStopped || _cachedAudioPath == null) {
        final audioPath = await _audioService.stop(releaseService: false);
        if (audioPath == null || !File(audioPath).existsSync()) {
          throw Exception('File rekaman audio tidak dapat disimpan.');
        }
        _cachedAudioPath = audioPath;
        _hasStopped = true;
      }

      final model = await StorageService.getModel();

      setState(() {
        _processingStep = 'Mengirim audio untuk dianalisis...';
      });

      final note = await GeminiService.processMeetingAudio(
        audioPath: _cachedAudioPath!,
        durationSeconds: _secondsRecorded,
        apiKey: apiKey,
        model: model,
        onProgress: (status) {
          if (mounted && _isProcessing) {
            setState(() {
              _processingStep = status;
            });
          }
        },
      );

      _processingTimer?.cancel();

      // Simpan langsung ke database lokal HP agar history langsung ter-update
      await StorageService.saveNote(note);

      // Lepaskan WakeLock & Keep-Screen-On setelah seluruh proses tuntas
      await _audioService.releaseKeepAwake();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ResultScreen(note: note, isNew: false),
          ),
        );
      }
    } catch (e) {
      _processingTimer?.cancel();
      await _audioService.releaseKeepAwake();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('API Key Diperlukan', style: TextStyle(color: Color(0xFFF1F5F9), fontWeight: FontWeight.bold)),
        content: const Text(
          'Anda belum mengisi API Key Gemini. Masukkan API Key agar HerzNote dapat memproses audio rapat Anda.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            child: const Text('Buka Pengaturan'),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Batalkan Rekaman?', style: TextStyle(color: Color(0xFFF1F5F9), fontWeight: FontWeight.bold)),
        content: const Text(
          'Audio rapat yang telah direkam akan dibuang dan tidak diproses.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Lanjutkan Rekaman', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Batalkan'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _timer?.cancel();
      _amplitudeSub?.cancel();
      _processingTimer?.cancel();
      if (!_hasStopped) {
        await _audioService.stop();
      }
      if (_cachedAudioPath != null) {
        try {
          final f = File(_cachedAudioPath!);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amplitudeSub?.cancel();
    _processingTimer?.cancel();
    _pulseController.dispose();
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
        title: const Text(
          'Perekaman Rapat',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
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

              // STATUS BADGE - Sleek, minimalist, borderless (Spotify dark style)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF181B21),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: _isPaused || _hasStopped ? const AlwaysStoppedAnimation(1.0) : _pulseAnimation,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: _hasStopped
                              ? const Color(0xFF10B981)
                              : _isPaused
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFFEF4444),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (_hasStopped
                                      ? const Color(0xFF10B981)
                                      : _isPaused
                                          ? const Color(0xFFF59E0B)
                                          : const Color(0xFFEF4444))
                                  .withOpacity(0.5),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _hasStopped
                          ? 'REKAMAN TERSIMPAN'
                          : _isPaused
                              ? 'REKAMAN DIJEDA'
                              : 'SEDANG MEREKAM',
                      style: TextStyle(
                        color: _hasStopped
                            ? const Color(0xFFA7F3D0)
                            : _isPaused
                                ? const Color(0xFFCBD5E1)
                                : const Color(0xFFF1F5F9),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // TIMER COUNTER
              Text(
                _formatTimer(_secondsRecorded),
                style: const TextStyle(
                  color: Color(0xFFF1F5F9),
                  fontSize: 54,
                  fontWeight: FontWeight.w200,
                  fontFamily: 'monospace',
                  letterSpacing: 3,
                ),
              ),

              const SizedBox(height: 32),

              // AUDIO SOUNDWAVE BARS (Quiet baseline rendah 4px, responsif melompat saat ada suara)
              Container(
                height: 80,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(_waveLevels.length, (idx) {
                    final height = (_isPaused || _hasStopped)
                        ? 4.0
                        : (4.0 + (_waveLevels[idx] * 64.0)).clamp(4.0, 68.0).toDouble();
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      curve: Curves.easeOut,
                      width: 5,
                      height: height,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: (_isPaused || _hasStopped)
                            ? const Color(0xFF334155)
                            : const Color(0xFF10B981),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 20),

              // GUIDANCE TIP CARD
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF181B21),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.mic, size: 16, color: Color(0xFF10B981)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Posisikan perangkat di tengah meja atau dekat sumber suara untuk tangkapan audio optimal.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              // ERROR MESSAGE CARD (Clean, dismissible & with retry button)
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF26191B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.error_outline, size: 18, color: Color(0xFFF87171)),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Gagal Membuat Notulensi',
                              style: TextStyle(
                                color: Color(0xFFFCA5A5),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16, color: Color(0xFF94A3B8)),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => setState(() => _errorMessage = null),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Color(0xFFFECACA), fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _stopAndProcess,
                          icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF10B981)),
                          label: const Text(
                            'Coba Lagi Sekarang',
                            style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(),

              // CONTROLS
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // PAUSE / RESUME BUTTON (Hanya aktif jika belum dihentikan)
                  if (!_hasStopped)
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
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: _stopAndProcess,
                      icon: Icon(_hasStopped ? Icons.auto_awesome : Icons.stop, size: 24),
                      label: Text(
                        _hasStopped ? 'Coba Buat Notulensi Lagi' : 'Selesai & Buat Notulensi',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
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
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // LOADING SPINNER
                Container(
                  width: 72,
                  height: 72,
                  padding: const EdgeInsets.all(8),
                  child: const CircularProgressIndicator(
                    strokeWidth: 3.5,
                    color: Color(0xFF10B981),
                  ),
                ),

                const SizedBox(height: 32),

                const Text(
                  'Menyusun Notulensi...',
                  style: TextStyle(
                    color: Color(0xFFF1F5F9),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  '$_processingStep (${_processingSeconds}s)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 28),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF181B21),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Sistem sedang menganalisis rekaman, menyaring percakapan, dan merangkum poin keputusan beserta tindak lanjutnya secara otomatis.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.5),
                  ),
                ),

                const Spacer(),

                // CANCEL BUTTON (So user is never stuck!)
                TextButton.icon(
                  onPressed: () {
                    _processingTimer?.cancel();
                    _audioService.releaseKeepAwake();
                    setState(() {
                      _isProcessing = false;
                      _errorMessage = 'Pemrosesan dibatalkan. Anda dapat mencoba lagi kapan saja.';
                    });
                  },
                  icon: const Icon(Icons.arrow_back, size: 16, color: Color(0xFF94A3B8)),
                  label: const Text(
                    'Batalkan & Kembali',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
