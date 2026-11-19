import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/meeting_note.dart';
import '../services/docx_service.dart';
import '../services/pdf_service.dart';
import '../services/storage_service.dart';

class ResultScreen extends StatefulWidget {
  final MeetingNote note;
  final bool isNew;

  const ResultScreen({
    super.key,
    required this.note,
    this.isNew = false,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> with SingleTickerProviderStateMixin {
  static const MethodChannel _playerChannel = MethodChannel('com.herz.notulensi/audio_player');

  late MeetingNote _note;
  late TabController _tabController;
  bool _isExportingPdf = false;
  bool _isExportingWord = false;

  // Mini Audio Player state
  bool _hasAudioFile = false;
  bool _isPlaying = false;
  int _positionMs = 0;
  int _durationMs = 0;
  double _playbackSpeed = 1.0;
  static const List<double> _speedOptions = [1.0, 1.25, 1.5, 2.0];
  Timer? _playerTimer;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _tabController = TabController(length: 2, vsync: this);
    _durationMs = _note.durationSeconds * 1000;
    _checkAudioFile();
  }

  void _checkAudioFile() {
    final path = _note.audioPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      _hasAudioFile = true;
    }
  }

  @override
  void dispose() {
    _playerTimer?.cancel();
    _stopAudioPlayer();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _stopAudioPlayer() async {
    try {
      await _playerChannel.invokeMethod('stop');
    } catch (_) {}
  }

  Future<void> _togglePlayPause() async {
    final path = _note.audioPath;
    if (path == null || !File(path).existsSync()) return;

    try {
      if (_isPlaying) {
        final status = await _playerChannel.invokeMethod<Map<dynamic, dynamic>>('pause');
        _applyPlayerStatus(status);
        _playerTimer?.cancel();
      } else {
        final status = await _playerChannel.invokeMethod<Map<dynamic, dynamic>>(
          'play',
          {'path': path, 'speed': _playbackSpeed},
        );
        _applyPlayerStatus(status);
        _startPlayerPolling();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFEF4444),
            content: Text('Tidak dapat memutar berkas audio.'),
          ),
        );
      }
    }
  }

  Future<void> _cyclePlaybackSpeed() async {
    final nextIdx = (_speedOptions.indexOf(_playbackSpeed) + 1) % _speedOptions.length;
    final nextSpeed = _speedOptions[nextIdx];
    setState(() => _playbackSpeed = nextSpeed);
    try {
      await _playerChannel.invokeMethod('setSpeed', {'speed': nextSpeed});
    } catch (_) {}
  }

  String _formatSpeedLabel(double speed) {
    if (speed == 1.0) return '1x';
    if (speed == 2.0) return '2x';
    return '${speed}x';
  }

  void _startPlayerPolling() {
    _playerTimer?.cancel();
    _playerTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (!mounted) {
        _playerTimer?.cancel();
        return;
      }
      try {
        final status = await _playerChannel.invokeMethod<Map<dynamic, dynamic>>('getStatus');
        _applyPlayerStatus(status);
        if (!_isPlaying) {
          _playerTimer?.cancel();
        }
      } catch (_) {
        _playerTimer?.cancel();
      }
    });
  }

  Future<void> _seekAudio(double valueMs) async {
    final targetMs = valueMs.round();
    setState(() => _positionMs = targetMs);
    try {
      final status = await _playerChannel.invokeMethod<Map<dynamic, dynamic>>('seek', {'positionMs': targetMs});
      _applyPlayerStatus(status);
    } catch (_) {}
  }

  void _applyPlayerStatus(Map<dynamic, dynamic>? status) {
    if (status == null || !mounted) return;
    setState(() {
      _isPlaying = status['isPlaying'] == true;
      final pos = (status['positionMs'] is int) ? status['positionMs'] as int : 0;
      final dur = (status['durationMs'] is int) ? status['durationMs'] as int : 0;
      if (dur > 0) _durationMs = dur;
      _positionMs = pos.clamp(0, _durationMs > 0 ? _durationMs : pos);
    });
  }

  String _formatMs(int ms) {
    final totalSeconds = (ms / 1000).floor();
    final mins = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _copyWhatsAppFormat() {
    Clipboard.setData(ClipboardData(text: _note.toWhatsAppFormat()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF10B981),
        content: Text('Format WhatsApp berhasil disalin!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareNotulensi() {
    Share.share(
      _note.toWhatsAppFormat(),
      subject: 'Notulensi: ${_note.title}',
    );
  }

  Future<void> _exportPdf() async {
    setState(() => _isExportingPdf = true);
    try {
      await PdfService.showPdfOptionsSheet(context, _note);
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
    }
  }

  Future<void> _exportWord() async {
    setState(() => _isExportingWord = true);
    try {
      await DocxService.exportDocx(_note, context);
    } finally {
      if (mounted) {
        setState(() => _isExportingWord = false);
      }
    }
  }

  Future<void> _editMeetingInfo() async {
    final locCtrl = TextEditingController(text: _note.location);
    final leaderCtrl = TextEditingController(text: _note.leader);
    final notetakerCtrl = TextEditingController(text: _note.notetaker);
    final partCtrl = TextEditingController(text: _note.participants);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF181B21),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Informasi Tambahan Rapat (Opsional)',
                style: TextStyle(
                  color: Color(0xFFF1F5F9),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Akan dicantumkan pada kop dan kolom tanda tangan Word & PDF.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: locCtrl,
                style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Tempat / Media Rapat',
                  labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  hintText: 'Contoh: Ruang Rapat Lt. 2 / Zoom',
                  hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF0F1115),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: leaderCtrl,
                      style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Pimpinan Rapat',
                        labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        hintText: 'Bpk. Budi Santoso',
                        hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF0F1115),
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: notetakerCtrl,
                      style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Notulis',
                        labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        hintText: 'Rina Lestari',
                        hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF0F1115),
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: partCtrl,
                style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Daftar Peserta Hadir',
                  labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  hintText: 'Budi, Siti, Andi, Deni, Rina',
                  hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF0F1115),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      _note.location = locCtrl.text.trim();
                      _note.leader = leaderCtrl.text.trim();
                      _note.notetaker = notetakerCtrl.text.trim();
                      _note.participants = partCtrl.text.trim();
                      Navigator.pop(ctx, true);
                    },
                    child: const Text('Simpan'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true) {
      setState(() {});
      await StorageService.saveNote(_note);
    }
  }

  Future<void> _editOrAddAgenda({int? index}) async {
    final isEdit = index != null;
    final initialText = isEdit ? _note.agenda[index] : '';
    final controller = TextEditingController(text: initialText);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181B21),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isEdit ? 'Ubah Agenda Rapat' : 'Tambah Agenda Rapat',
          style: const TextStyle(color: Color(0xFFF1F5F9), fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Tuliskan pokok bahasan atau agenda...',
            hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 13),
            filled: true,
            fillColor: const Color(0xFF0F1115),
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          if (isEdit)
            TextButton(
              onPressed: () => Navigator.pop(ctx, {'action': 'delete'}),
              child: const Text('Hapus', style: TextStyle(color: Color(0xFFF87171))),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, {'action': 'save', 'text': controller.text.trim()}),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (result == null) return;
    if (result['action'] == 'delete' && isEdit) {
      setState(() => _note.agenda.removeAt(index));
      await StorageService.saveNote(_note);
    } else if (result['action'] == 'save') {
      final text = (result['text'] ?? '').toString();
      if (text.isEmpty) return;
      setState(() {
        if (isEdit) {
          _note.agenda[index] = text;
        } else {
          _note.agenda.add(text);
        }
      });
      await StorageService.saveNote(_note);
    }
  }

  Future<void> _editTitle() async {
    final controller = TextEditingController(text: _note.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181B21),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ubah Judul Rapat', style: TextStyle(color: Color(0xFFF1F5F9), fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFF1F5F9)),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0F1115),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (newTitle != null && newTitle.isNotEmpty) {
      setState(() => _note.title = newTitle);
      await StorageService.saveNote(_note);
    }
  }

  Future<void> _editOrAddDecision({int? index}) async {
    final isEdit = index != null;
    final controller = TextEditingController(text: isEdit ? _note.decisions[index] : '');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181B21),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isEdit ? 'Ubah Keputusan Rapat' : 'Tambah Keputusan Rapat',
          style: const TextStyle(color: Color(0xFFF1F5F9), fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
          style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Tulis poin keputusan rapat...',
            hintStyle: const TextStyle(color: Color(0xFF64748B)),
            filled: true,
            fillColor: const Color(0xFF0F1115),
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          if (isEdit)
            TextButton(
              onPressed: () => Navigator.pop(ctx, {'action': 'delete'}),
              child: const Text('Hapus', style: TextStyle(color: Color(0xFFF87171))),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, {'action': 'save', 'text': controller.text.trim()}),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (result == null) return;
    if (result['action'] == 'delete' && isEdit) {
      setState(() => _note.decisions.removeAt(index));
      await StorageService.saveNote(_note);
    } else if (result['action'] == 'save') {
      final txt = (result['text'] ?? '').toString();
      if (txt.isEmpty) return;
      setState(() {
        if (isEdit) {
          _note.decisions[index] = txt;
        } else {
          _note.decisions.add(txt);
        }
      });
      await StorageService.saveNote(_note);
    }
  }

  Future<void> _editOrAddActionItem({int? index}) async {
    final isEdit = index != null;
    final existing = isEdit ? _note.actionItems[index] : null;
    final taskCtrl = TextEditingController(text: existing?.task ?? '');
    final picCtrl = TextEditingController(text: existing?.pic ?? '');
    final dlCtrl = TextEditingController(text: (existing?.deadline ?? '-') == '-' ? '' : existing!.deadline);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181B21),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isEdit ? 'Ubah Action Item' : 'Tambah Action Item',
          style: const TextStyle(color: Color(0xFFF1F5F9), fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: taskCtrl,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Tugas / Pekerjaan',
                  labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF0F1115),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: picCtrl,
                style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Penanggung Jawab (PIC)',
                  labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  hintText: 'Contoh: Budi / Tim Desain',
                  hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF0F1115),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: dlCtrl,
                style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Batas Waktu (Opsional)',
                  labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  hintText: 'Contoh: Jumat ini / 25 Nov',
                  hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF0F1115),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (isEdit)
            TextButton(
              onPressed: () => Navigator.pop(ctx, {'action': 'delete'}),
              child: const Text('Hapus', style: TextStyle(color: Color(0xFFF87171))),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, {
              'action': 'save',
              'task': taskCtrl.text.trim(),
              'pic': picCtrl.text.trim().isEmpty ? 'Tim' : picCtrl.text.trim(),
              'deadline': dlCtrl.text.trim().isEmpty ? '-' : dlCtrl.text.trim(),
            }),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (result == null) return;
    if (result['action'] == 'delete' && isEdit) {
      setState(() => _note.actionItems.removeAt(index));
      await StorageService.saveNote(_note);
    } else if (result['action'] == 'save') {
      final task = (result['task'] ?? '').toString();
      if (task.isEmpty) return;
      setState(() {
        if (isEdit) {
          _note.actionItems[index].task = task;
          _note.actionItems[index].pic = result['pic'];
          _note.actionItems[index].deadline = result['deadline'];
        } else {
          _note.actionItems.add(ActionItem(
            task: task,
            pic: result['pic'],
            deadline: result['deadline'],
          ));
        }
      });
      await StorageService.saveNote(_note);
    }
  }

  Future<void> _editSummary() async {
    final controller = TextEditingController(text: _note.summary);
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181B21),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ubah Ringkasan', style: TextStyle(color: Color(0xFFF1F5F9), fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          minLines: 3,
          style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0F1115),
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (updated != null) {
      setState(() => _note.summary = updated);
      await StorageService.saveNote(_note);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, true);
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1115),
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, true),
          ),
          title: const Text('Hasil Notulensi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF181B21),
          foregroundColor: const Color(0xFFF1F5F9),
          elevation: 0,
          actions: [
            IconButton(
              tooltip: 'Ubah Judul',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: _editTitle,
            ),
            IconButton(
              tooltip: 'Ekspor Word (.docx)',
              icon: _isExportingWord
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                    )
                  : const Icon(Icons.description_outlined, size: 20),
              onPressed: _isExportingWord ? null : _exportWord,
            ),
            IconButton(
              tooltip: 'Ekspor PDF',
              icon: _isExportingPdf
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined, size: 20),
              onPressed: _isExportingPdf ? null : _exportPdf,
            ),
            IconButton(
              tooltip: 'Bagikan',
              icon: const Icon(Icons.share_outlined, size: 20),
              onPressed: _shareNotulensi,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF10B981),
            indicatorWeight: 2.5,
            labelColor: const Color(0xFF10B981),
            unselectedLabelColor: const Color(0xFF94A3B8),
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: const [
              Tab(text: 'Notulensi'),
              Tab(text: 'Alur Pembahasan'),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: const Color(0xFF181B21),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _copyWhatsAppFormat,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Salin Format WA', maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isExportingWord ? null : _exportWord,
                icon: _isExportingWord
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)))
                    : const Icon(Icons.description, size: 16),
                label: const Text('Word'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF262A34),
                  foregroundColor: const Color(0xFFF1F5F9),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isExportingPdf ? null : _exportPdf,
                icon: _isExportingPdf
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)))
                    : const Icon(Icons.picture_as_pdf, size: 16),
                label: const Text('PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF262A34),
                  foregroundColor: const Color(0xFFF1F5F9),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildStructuredView(),
            _buildDiscussionFlowView(),
          ],
        ),
      ),
    );
  }

  Widget _buildStructuredView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TITLE CARD
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181B21),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _note.title,
                  style: const TextStyle(
                    color: Color(0xFFF1F5F9),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 13, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 5),
                    Text(
                      _note.formattedDate,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.schedule, size: 13, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 5),
                    Text(
                      _note.formattedDuration,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ],
                ),
                if (_note.location.trim().isNotEmpty ||
                    _note.leader.trim().isNotEmpty ||
                    _note.notetaker.trim().isNotEmpty ||
                    _note.participants.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1115),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_note.location.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              'Tempat/Media: ${_note.location.trim()}',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                            ),
                          ),
                        if (_note.leader.trim().isNotEmpty || _note.notetaker.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              'Pimpinan: ${_note.leader.trim().isNotEmpty ? _note.leader.trim() : "-"}  |  Notulis: ${_note.notetaker.trim().isNotEmpty ? _note.notetaker.trim() : "-"}',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                            ),
                          ),
                        if (_note.participants.trim().isNotEmpty)
                          Text(
                            'Peserta: ${_note.participants.trim()}',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: _editMeetingInfo,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _note.leader.isNotEmpty || _note.location.isNotEmpty ? Icons.edit_note : Icons.add_circle_outline,
                            size: 14,
                            color: const Color(0xFF10B981),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _note.leader.isNotEmpty || _note.location.isNotEmpty ? 'Ubah Info Rapat' : '+ Info Rapat (Pimpinan, Lokasi)',
                            style: const TextStyle(color: Color(0xFF10B981), fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // DECISIONS CARD (Editable + Addable)
          _buildSectionHeader(
            'KEPUTUSAN RAPAT',
            Icons.gavel_rounded,
            actionLabel: 'Tambah',
            actionIcon: Icons.add,
            onAction: () => _editOrAddDecision(),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF181B21),
              borderRadius: BorderRadius.circular(14),
            ),
            child: _note.decisions.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'Belum ada poin keputusan. Ketuk Tambah untuk menambahkan.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    ),
                  )
                : Column(
                    children: List.generate(_note.decisions.length, (idx) {
                      final decision = _note.decisions[idx];
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _editOrAddDecision(index: idx),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7.0, horizontal: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF0F291E),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check, size: 12, color: Color(0xFF10B981)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  decision,
                                  style: const TextStyle(
                                    color: Color(0xFFF1F5F9),
                                    fontSize: 14,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF475569)),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
          ),

          const SizedBox(height: 16),

          // ACTION ITEMS & PIC CARD (Editable + Addable)
          _buildSectionHeader(
            'ACTION ITEMS & PENANGGUNG JAWAB',
            Icons.task_alt,
            actionLabel: 'Tambah',
            actionIcon: Icons.add,
            onAction: () => _editOrAddActionItem(),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF181B21),
              borderRadius: BorderRadius.circular(14),
            ),
            child: _note.actionItems.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Text(
                      'Belum ada action items. Ketuk Tambah untuk menambahkan tugas.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    ),
                  )
                : Column(
                    children: List.generate(_note.actionItems.length, (idx) {
                      final item = _note.actionItems[idx];
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F1115),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _editOrAddActionItem(index: idx),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Checkbox(
                                    value: item.isCompleted,
                                    activeColor: const Color(0xFF10B981),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    onChanged: (val) {
                                      setState(() {
                                        item.isCompleted = val ?? false;
                                      });
                                      StorageService.saveNote(_note);
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.task,
                                          style: TextStyle(
                                            color: item.isCompleted ? const Color(0xFF64748B) : const Color(0xFFF1F5F9),
                                            fontSize: 14,
                                            decoration: item.isCompleted ? TextDecoration.lineThrough : null,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF132238),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'PIC: ${item.pic}',
                                                style: const TextStyle(
                                                  color: Color(0xFF38BDF8),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            if (item.deadline != '-')
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF241E3D),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  'Deadline: ${item.deadline}',
                                                  style: const TextStyle(
                                                    color: Color(0xFFA5B4FC),
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                            if (item.isCompleted)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF0F291E),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'Selesai',
                                                  style: TextStyle(
                                                    color: Color(0xFF10B981),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Icon(Icons.edit_outlined, size: 14, color: Color(0xFF475569)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
          ),

          const SizedBox(height: 16),

          // AGENDA RAPAT (Editable + Addable, Right Above Summary)
          _buildSectionHeader(
            'AGENDA RAPAT',
            Icons.format_list_numbered_rounded,
            actionLabel: 'Tambah',
            actionIcon: Icons.add,
            onAction: () => _editOrAddAgenda(),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF181B21),
              borderRadius: BorderRadius.circular(14),
            ),
            child: _note.agenda.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'Belum ada poin agenda. Ketuk Tambah untuk menambahkan.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    ),
                  )
                : Column(
                    children: List.generate(_note.agenda.length, (idx) {
                      final item = _note.agenda[idx];
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _editOrAddAgenda(index: idx),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7.0, horizontal: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${idx + 1}.',
                                style: const TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item,
                                  style: const TextStyle(
                                    color: Color(0xFFF1F5F9),
                                    fontSize: 13.5,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF475569)),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
          ),

          const SizedBox(height: 16),

          // SUMMARY CARD (Editable)
          _buildSectionHeader(
            'RINGKASAN PEMBAHASAN',
            Icons.notes,
            actionLabel: 'Ubah',
            actionIcon: Icons.edit_outlined,
            onAction: _editSummary,
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181B21),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _note.summary.trim().isEmpty ? 'Tidak ada ringkasan pembahasan.' : _note.summary.trim(),
              textAlign: TextAlign.justify,
              style: const TextStyle(
                color: Color(0xFFF1F5F9),
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildMiniAudioPlayer() {
    final maxMs = _durationMs > 0 ? _durationMs.toDouble() : 1.0;
    final currentMs = _positionMs.toDouble().clamp(0.0, maxMs);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF181B21),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _togglePlayPause,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Rekaman Audio Asli',
                      style: TextStyle(
                        color: Color(0xFFF1F5F9),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    InkWell(
                      onTap: _cyclePlaybackSpeed,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: _playbackSpeed > 1.0 ? const Color(0xFF0F291E) : const Color(0xFF262A34),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _formatSpeedLabel(_playbackSpeed),
                          style: TextStyle(
                            color: _playbackSpeed > 1.0 ? const Color(0xFF10B981) : const Color(0xFFF1F5F9),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: const Color(0xFF10B981),
                    inactiveTrackColor: const Color(0xFF262A34),
                    thumbColor: const Color(0xFF10B981),
                  ),
                  child: Slider(
                    value: currentMs,
                    min: 0.0,
                    max: maxMs,
                    onChanged: (v) => _seekAudio(v),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatMs(_positionMs),
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontFamily: 'monospace'),
                    ),
                    Text(
                      _formatMs(_durationMs),
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscussionFlowView() {
    final text = _note.transcript.trim();
    final paragraphs = text.isEmpty
        ? <String>[]
        : text.split(RegExp(r'\n+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (_hasAudioFile) _buildMiniAudioPlayer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF181B21),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.timeline, size: 16, color: Color(0xFF10B981)),
                    SizedBox(width: 8),
                    Text(
                      'KRONOLOGI & ALUR RAPAT',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (paragraphs.isEmpty)
                  const Text(
                    'Alur pembahasan tidak tersedia.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  )
                else
                  ...paragraphs.map((pText) {
                    final sectionMatch = RegExp(r'^(\d+\.\s+[^:\n]{2,50}:)\s*(.*)$').firstMatch(pText);
                    if (sectionMatch != null) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: RichText(
                          textAlign: TextAlign.justify,
                          text: TextSpan(
                            style: const TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 14,
                              height: 1.7,
                            ),
                            children: [
                              TextSpan(
                                text: '${sectionMatch.group(1)!} ',
                                style: const TextStyle(
                                  color: Color(0xFFF1F5F9),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(text: sectionMatch.group(2) ?? ''),
                            ],
                          ),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        pText,
                        textAlign: TextAlign.justify,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 14,
                          height: 1.7,
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    IconData icon, {
    String? actionLabel,
    IconData? actionIcon,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4, right: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF10B981)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                color: Color(0xFF94A3B8),
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (actionIcon != null) ...[
                      Icon(actionIcon, size: 14, color: const Color(0xFF10B981)),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      actionLabel,
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
