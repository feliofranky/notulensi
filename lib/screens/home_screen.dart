import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/meeting_note.dart';
import '../services/storage_service.dart';
import 'recording_screen.dart';
import 'result_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MeetingNote> _notes = [];
  bool _isLoading = true;
  String _apiKey = '';
  String _currentModel = StorageService.defaultModel;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    final notes = await StorageService.loadNotes();
    final key = await StorageService.getApiKey();
    final model = await StorageService.getModel();

    setState(() {
      _notes = notes;
      _apiKey = key;
      _currentModel = model;
      _isLoading = false;
    });
  }

  Future<void> _deleteNote(MeetingNote note) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181B21),
        title: const Text('Hapus Notulensi?', style: TextStyle(color: Color(0xFFF1F5F9))),
        content: Text(
          'Notulensi "${note.title}" akan dihapus permanen.',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await StorageService.deleteNote(note.id);
      await _refreshData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notulensi dihapus.')),
        );
      }
    }
  }

  void _copyWa(MeetingNote note) {
    Clipboard.setData(ClipboardData(text: note.toWhatsAppFormat()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF10B981),
        content: Text('✓ Format WhatsApp berhasil disalin!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openRecording() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecordingScreen()),
    ).then((_) => _refreshData());
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    ).then((_) => _refreshData());
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = _apiKey.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'HerzNote',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Color(0xFFF1F5F9),
              ),
            ),
            Text(
              'Notulensi Rapat AI',
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFF94A3B8).withOpacity(0.8),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF181B21),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Pengaturan',
            icon: const Icon(Icons.settings_outlined, color: Color(0xFFF1F5F9)),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // STATUS BANNER
            InkWell(
              onTap: hasKey ? null : _openSettings,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: hasKey ? const Color(0xFF064E3B).withOpacity(0.4) : const Color(0xFF7F1D1D).withOpacity(0.4),
                  border: Border(
                    bottom: BorderSide(
                      color: hasKey ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasKey ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                      size: 16,
                      color: hasKey ? const Color(0xFF34D399) : const Color(0xFFF87171),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasKey
                            ? 'AI Engine Siap: $_currentModel'
                            : 'API Key Gemini belum diatur. Ketuk di sini untuk memasukkan API Key.',
                        style: TextStyle(
                          color: hasKey ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (!hasKey)
                      const Icon(Icons.chevron_right, size: 16, color: Color(0xFFFECACA)),
                  ],
                ),
              ),
            ),

            // NOTES LIST OR EMPTY STATE
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
                  : _notes.isEmpty
                      ? _buildEmptyState()
                      : _buildNotesList(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openRecording,
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.mic, size: 22),
        label: const Text(
          'Mulai Rekam Rapat',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF181B21),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF262A34)),
              ),
              child: const Icon(
                Icons.mic_none_outlined,
                size: 48,
                color: Color(0xFF10B981),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Belum Ada Notulensi',
              style: TextStyle(
                color: Color(0xFFF1F5F9),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Taruh HP di tengah meja rapat dan tekan tombol "Mulai Rekam Rapat" di bawah saat rapat dimulai.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesList() {
    return RefreshIndicator(
      color: const Color(0xFF10B981),
      backgroundColor: const Color(0xFF181B21),
      onRefresh: _refreshData,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        itemCount: _notes.length,
        itemBuilder: (ctx, idx) {
          final note = _notes[idx];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: const Color(0xFF181B21),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF262A34)),
            ),
            elevation: 0,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ResultScreen(note: note)),
                ).then((_) => _refreshData());
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            note.title,
                            style: const TextStyle(
                              color: Color(0xFFF1F5F9),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 20, color: Color(0xFF94A3B8)),
                          color: const Color(0xFF262A34),
                          onSelected: (val) {
                            if (val == 'copy') _copyWa(note);
                            if (val == 'delete') _deleteNote(note);
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'copy',
                              child: Row(
                                children: [
                                  Icon(Icons.copy, size: 16, color: Color(0xFF34D399)),
                                  SizedBox(width: 8),
                                  Text('Salin Format WA', style: TextStyle(color: Color(0xFFF1F5F9))),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, size: 16, color: Color(0xFFF87171)),
                                  SizedBox(width: 8),
                                  Text('Hapus', style: TextStyle(color: Color(0xFFF87171))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 12, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        Text(
                          note.formattedDate,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.timer_outlined, size: 12, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        Text(
                          note.formattedDuration,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (note.decisions.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF064E3B).withOpacity(0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '⚖️ ${note.decisions.length} Keputusan',
                              style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 11),
                            ),
                          ),
                        if (note.actionItems.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '✅ ${note.actionItems.length} Action Items',
                              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
