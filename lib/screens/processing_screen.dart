import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/meeting_note.dart';
import '../services/audio_service.dart';
import '../services/gemini_service.dart';
import '../services/storage_service.dart';
import 'result_screen.dart';
import 'settings_screen.dart';

class ProcessingScreen extends StatefulWidget {
  final MeetingNote draftNote;

  const ProcessingScreen({super.key, required this.draftNote});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  final AudioService _audioService = AudioService();
  bool _isProcessing = true;
  int _elapsedSeconds = 0;
  Timer? _timer;
  String _statusText = 'Menyiapkan berkas audio...';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startProcessing();
  }

  Future<void> _startProcessing() async {
    final apiKey = await StorageService.getApiKey();
    if (apiKey.isEmpty) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'API Key belum diatur. Silakan isi API Key di menu Pengaturan lalu coba lagi.';
        });
      }
      return;
    }

    final audioPath = widget.draftNote.audioPath;
    if (audioPath == null || !File(audioPath).existsSync()) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Berkas audio untuk draft ini tidak ditemukan di penyimpanan perangkat.';
        });
      }
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _elapsedSeconds = 0;
      _statusText = 'Menyiapkan berkas audio...';
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isProcessing) {
        setState(() => _elapsedSeconds++);
      }
    });

    try {
      await _audioService.ensureKeepAwake();
      final model = await StorageService.getModel();

      final note = await GeminiService.processMeetingAudio(
        audioPath: audioPath,
        durationSeconds: widget.draftNote.durationSeconds,
        apiKey: apiKey,
        model: model,
        existingId: widget.draftNote.id,
        existingDate: widget.draftNote.date,
        onProgress: (status) {
          if (mounted && _isProcessing) {
            setState(() => _statusText = status);
          }
        },
      );

      note.isDraft = false;
      await StorageService.saveNote(note);

      _timer?.cancel();
      await _audioService.releaseKeepAwake();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ResultScreen(note: note)),
        );
      }
    } catch (e) {
      _timer?.cancel();
      await _audioService.releaseKeepAwake();
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioService.releaseKeepAwake();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: _isProcessing
          ? null
          : AppBar(
              title: const Text('Proses Draft', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFF181B21),
              foregroundColor: const Color(0xFFF1F5F9),
              elevation: 0,
            ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: _isProcessing ? _buildLoadingBody() : _buildErrorBody(),
        ),
      ),
    );
  }

  Widget _buildLoadingBody() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        const SizedBox(
          width: 68,
          height: 68,
          child: CircularProgressIndicator(
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
          '$_statusText (${_elapsedSeconds}s)',
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
        TextButton.icon(
          onPressed: () {
            _timer?.cancel();
            _audioService.releaseKeepAwake();
            Navigator.pop(context, true);
          },
          icon: const Icon(Icons.bookmark_border, size: 16, color: Color(0xFF94A3B8)),
          label: const Text(
            'Simpan di Draft & Kembali',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildErrorBody() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Color(0xFF26191B),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.error_outline, size: 42, color: Color(0xFFF87171)),
        ),
        const SizedBox(height: 20),
        const Text(
          'Belum Dapat Memproses',
          style: TextStyle(color: Color(0xFFF1F5F9), fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF181B21),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            _errorMessage ?? 'Terjadi kendala saat memproses audio.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.5),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _startProcessing,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Coba Lagi Sekarang', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_errorMessage?.contains('API Key') == true)
          TextButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
            child: const Text('Buka Pengaturan', style: TextStyle(color: Color(0xFF10B981))),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Biarkan di Draft & Kembali', style: TextStyle(color: Color(0xFF94A3B8))),
        ),
      ],
    );
  }
}
