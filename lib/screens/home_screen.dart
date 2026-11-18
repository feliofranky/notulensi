import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/meeting_note.dart';
import '../services/pdf_service.dart';
import '../services/storage_service.dart';
import 'processing_screen.dart';
import 'recording_screen.dart';
import 'result_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const MethodChannel _filesChannel = MethodChannel('com.herz.notulensi/files');

  List<MeetingNote> _notes = [];
  bool _isLoading = true;
  String _apiKey = '';

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshData();
    }
  }

  Future<void> _refreshData() async {
    final notes = await StorageService.loadNotes();
    final key = await StorageService.getApiKey();

    if (mounted) {
      setState(() {
        _notes = notes;
        _apiKey = key;
        _isLoading = false;
      });
    }
  }

  List<MeetingNote> get _filteredNotes {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _notes;
    return _notes.where((n) {
      if (n.title.toLowerCase().contains(q)) return true;
      if (n.summary.toLowerCase().contains(q)) return true;
      if (n.transcript.toLowerCase().contains(q)) return true;
      if (n.decisions.any((d) => d.toLowerCase().contains(q))) return true;
      if (n.actionItems.any((a) => a.task.toLowerCase().contains(q) || a.pic.toLowerCase().contains(q))) return true;
      return false;
    }).toList();
  }

  Future<void> _importAudioFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory(p.join(dir.path, 'recordings'));
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }

      final result = await _filesChannel.invokeMethod<Map<dynamic, dynamic>>(
        'pickAudioFile',
        {'destDir': recordingsDir.path},
      );

      if (result == null || !mounted) return;

      final audioPath = (result['path'] ?? '').toString();
      final originalName = (result['name'] ?? 'Audio Impor').toString();
      final durationSec = (result['durationSeconds'] is int) ? result['durationSeconds'] as int : 0;

      if (audioPath.isEmpty || !File(audioPath).existsSync()) {
        throw Exception('File audio gagal diimpor.');
      }

      final cleanTitle = originalName.replaceAll(RegExp(r'\.[^.]+$'), '').trim();
      final now = DateTime.now();
      final draft = MeetingNote(
        id: now.millisecondsSinceEpoch.toString(),
        title: cleanTitle.isEmpty ? 'Audio Impor' : cleanTitle,
        date: now,
        durationSeconds: durationSec,
        audioPath: audioPath,
        summary: '',
        decisions: [],
        actionItems: [],
        transcript: '',
        isDraft: true,
      );

      // Simpan ke Draft dulu agar aman bila sinyal putus di tengah jalan
      await StorageService.saveNote(draft);
      await _refreshData();

      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProcessingScreen(draftNote: draft)),
        );
        _refreshData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Gagal mengimpor audio: ${e.toString().replaceAll("Exception: ", "")}'),
          ),
        );
      }
    }
  }

  Future<void> _deleteNote(MeetingNote note) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181B21),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          note.isDraft ? 'Hapus Draft?' : 'Hapus Notulensi?',
          style: const TextStyle(color: Color(0xFFF1F5F9), fontWeight: FontWeight.bold),
        ),
        content: Text(
          '"${note.title}" beserta seluruh berkas audio fisiknya akan dihapus permanen dari HP.',
          style: const TextStyle(color: Color(0xFF94A3B8), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus Bersih'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await StorageService.deleteNote(note.id);
      await _refreshData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF181B21),
            content: Text('Data dan berkas audio berhasil dihapus bersih.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _copyWa(MeetingNote note) {
    Clipboard.setData(ClipboardData(text: note.toWhatsAppFormat()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF10B981),
        content: Text('Format WhatsApp berhasil disalin!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openRecording() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecordingScreen()),
    );
    _refreshData();
  }

  Future<void> _openDraft(MeetingNote draft) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProcessingScreen(draftNote: draft)),
    );
    _refreshData();
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    _refreshData();
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = _apiKey.isNotEmpty;
    final visibleNotes = _filteredNotes;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181B21),
        elevation: 0,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Cari judul, keputusan, atau PIC...',
                  hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'HERZnote',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: Color(0xFFF1F5F9),
                      letterSpacing: 0.4,
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
        actions: _isSearching
            ? [
                IconButton(
                  tooltip: 'Tutup Pencarian',
                  icon: const Icon(Icons.close, color: Color(0xFFF1F5F9)),
                  onPressed: () {
                    setState(() {
                      _isSearching = false;
                      _searchQuery = '';
                      _searchController.clear();
                    });
                  },
                ),
              ]
            : [
                if (_notes.isNotEmpty)
                  IconButton(
                    tooltip: 'Cari Riwayat',
                    icon: const Icon(Icons.search, color: Color(0xFFF1F5F9), size: 22),
                    onPressed: () => setState(() => _isSearching = true),
                  ),
                IconButton(
                  tooltip: 'Import Audio',
                  icon: const Icon(Icons.audio_file_outlined, color: Color(0xFFF1F5F9), size: 22),
                  onPressed: _importAudioFile,
                ),
                IconButton(
                  tooltip: 'Pengaturan',
                  icon: const Icon(Icons.settings_outlined, color: Color(0xFFF1F5F9), size: 22),
                  onPressed: _openSettings,
                ),
              ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // STATUS BAR (Clean & Minimalist: "Ready", No Outlines, No Emojis)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: InkWell(
                onTap: hasKey ? null : _openSettings,
                borderRadius: BorderRadius.circular(6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: hasKey ? const Color(0xFF10B981) : const Color(0xFFF87171),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hasKey ? 'Ready' : 'API Key Belum Diisi',
                      style: TextStyle(
                        color: hasKey ? const Color(0xFF94A3B8) : const Color(0xFFF87171),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (!hasKey) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 14, color: Color(0xFFF87171)),
                    ],
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
                      : visibleNotes.isEmpty
                          ? _buildSearchEmptyState()
                          : _buildNotesList(visibleNotes),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 14, right: 4),
        child: SizedBox(
          height: 46,
          child: FloatingActionButton.extended(
            onPressed: _openRecording,
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            elevation: 2,
            extendedPadding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            icon: const Icon(Icons.mic, size: 18),
            label: const Text(
              'Mulai Rekam',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 42, color: Color(0xFF475569)),
            const SizedBox(height: 12),
            Text(
              'Tidak ditemukan hasil untuk "$_searchQuery"',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            ),
          ],
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
              decoration: const BoxDecoration(
                color: Color(0xFF181B21),
                shape: BoxShape.circle,
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
              'Posisikan perangkat di tengah meja dan tekan tombol "Mulai Rekam" saat rapat dimulai, atau impor file audio dari menu di atas.',
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

  Widget _buildNotesList(List<MeetingNote> list) {
    return RefreshIndicator(
      color: const Color(0xFF10B981),
      backgroundColor: const Color(0xFF181B21),
      onRefresh: _refreshData,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: list.length,
        itemBuilder: (ctx, idx) {
          final note = list[idx];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF181B21),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  if (note.isDraft) {
                    await _openDraft(note);
                  } else {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ResultScreen(note: note)),
                    );
                    _refreshData();
                  }
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
                            elevation: 4,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            onSelected: (val) {
                              if (val == 'process') _openDraft(note);
                              if (val == 'copy') _copyWa(note);
                              if (val == 'pdf') PdfService.showPdfOptionsSheet(context, note);
                              if (val == 'delete') _deleteNote(note);
                            },
                            itemBuilder: (context) => [
                              if (note.isDraft)
                                const PopupMenuItem(
                                  value: 'process',
                                  child: Row(
                                    children: [
                                      Icon(Icons.play_arrow_rounded, size: 18, color: Color(0xFF10B981)),
                                      SizedBox(width: 8),
                                      Text('Proses Sekarang', style: TextStyle(color: Color(0xFFF1F5F9))),
                                    ],
                                  ),
                                )
                              else ...[
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
                                  value: 'pdf',
                                  child: Row(
                                    children: [
                                      Icon(Icons.picture_as_pdf_outlined, size: 16, color: Color(0xFF93C5FD)),
                                      SizedBox(width: 8),
                                      Text('Ekspor PDF', style: TextStyle(color: Color(0xFFF1F5F9))),
                                    ],
                                  ),
                                ),
                              ],
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
                          const SizedBox(width: 5),
                          Text(
                            note.formattedDate,
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                          const SizedBox(width: 14),
                          const Icon(Icons.schedule, size: 12, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 5),
                          Text(
                            note.formattedDuration,
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (note.isDraft)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2B2214),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.hourglass_top_rounded, size: 12, color: Color(0xFFF59E0B)),
                                  SizedBox(width: 5),
                                  Text(
                                    'Draft - Menunggu Diproses',
                                    style: TextStyle(
                                      color: Color(0xFFFCD34D),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _openDraft(note),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(Icons.auto_awesome, size: 14, color: Color(0xFF10B981)),
                              label: const Text(
                                'Proses',
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (note.decisions.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F291E),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.gavel, size: 12, color: Color(0xFF10B981)),
                                    const SizedBox(width: 5),
                                    Text(
                                      '${note.decisions.length} Keputusan',
                                      style: const TextStyle(
                                        color: Color(0xFF6EE7B7),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (note.actionItems.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF132238),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.task_alt, size: 12, color: Color(0xFF38BDF8)),
                                    const SizedBox(width: 5),
                                    Text(
                                      '${note.actionItems.length} Action Items',
                                      style: const TextStyle(
                                        color: Color(0xFF93C5FD),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
