import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/meeting_note.dart';
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
  late MeetingNote _note;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _tabController = TabController(length: 2, vsync: this);
    if (widget.isNew) {
      _saveInitialNote();
    }
  }

  Future<void> _saveInitialNote() async {
    await StorageService.saveNote(_note);
  }

  void _copyWhatsAppFormat() {
    Clipboard.setData(ClipboardData(text: _note.toWhatsAppFormat()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF10B981),
        content: Text('✓ Format WhatsApp berhasil disalin ke clipboard!'),
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

  Future<void> _editTitle() async {
    final controller = TextEditingController(text: _note.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181B21),
        title: const Text('Ubah Judul Rapat', style: TextStyle(color: Color(0xFFF1F5F9))),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFF1F5F9)),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0F1115),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (newTitle != null && newTitle.isNotEmpty) {
      setState(() {
        _note.title = newTitle;
      });
      await StorageService.saveNote(_note);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        title: const Text('Hasil Notulensi'),
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
            tooltip: 'Bagikan',
            icon: const Icon(Icons.share_outlined, size: 20),
            onPressed: _shareNotulensi,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF10B981),
          labelColor: const Color(0xFF10B981),
          unselectedLabelColor: const Color(0xFF94A3B8),
          tabs: const [
            Tab(text: 'Notulensi Rapi'),
            Tab(text: 'Transkrip Lengkap'),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: Color(0xFF181B21),
          border: Border(top: BorderSide(color: Color(0xFF262A34))),
        ),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _copyWhatsAppFormat,
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Salin Format WhatsApp'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filled(
              onPressed: _shareNotulensi,
              icon: const Icon(Icons.share, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF262A34),
                foregroundColor: const Color(0xFFF1F5F9),
                padding: const EdgeInsets.all(14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStructuredView(),
          _buildTranscriptView(),
        ],
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
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF262A34)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _note.title,
                        style: const TextStyle(
                          color: Color(0xFFF1F5F9),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 6),
                    Text(
                      _note.formattedDate,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.timer_outlined, size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 6),
                    Text(
                      _note.formattedDuration,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // DECISIONS CARD
          if (_note.decisions.isNotEmpty) ...[
            _buildSectionHeader('KEPUTUSAN RAPAT', Icons.gavel_rounded),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF181B21),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF262A34)),
              ),
              child: Column(
                children: List.generate(_note.decisions.length, (idx) {
                  final decision = _note.decisions[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFF064E3B),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check, size: 12, color: Color(0xFF34D399)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            decision,
                            style: const TextStyle(
                              color: Color(0xFFF1F5F9),
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ACTION ITEMS & PIC CARD
          if (_note.actionItems.isNotEmpty) ...[
            _buildSectionHeader('ACTION ITEMS & PENANGGUNG JAWAB', Icons.task_alt),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF181B21),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF262A34)),
              ),
              child: Column(
                children: List.generate(_note.actionItems.length, (idx) {
                  final item = _note.actionItems[idx];
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1115),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF262A34)),
                    ),
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
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
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
                                  if (item.deadline != '-') ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF312E81),
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
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // SUMMARY CARD
          _buildSectionHeader('RINGKASAN PEMBAHASAN', Icons.notes),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181B21),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF262A34)),
            ),
            child: Text(
              _note.summary.trim().isEmpty ? 'Tidak ada ringkasan pembahasan.' : _note.summary.trim(),
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

  Widget _buildTranscriptView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF181B21),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF262A34)),
        ),
        child: Text(
          _note.transcript.trim().isEmpty ? 'Transkrip tidak tersedia.' : _note.transcript.trim(),
          style: const TextStyle(
            color: Color(0xFFCBD5E1),
            fontSize: 13,
            height: 1.6,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF10B981)),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}
