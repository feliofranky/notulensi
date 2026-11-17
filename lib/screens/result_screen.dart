import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/meeting_note.dart';
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
  late MeetingNote _note;
  late TabController _tabController;
  bool _isExportingPdf = false;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _tabController = TabController(length: 2, vsync: this);
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
      await PdfService.generateAndSharePdf(_note);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Gagal mengekspor PDF: ${e.toString().replaceAll("Exception: ", "")}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
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
      setState(() {
        _note.title = newTitle;
      });
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
              Tab(text: 'Notulensi Rapi'),
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
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _isExportingPdf ? null : _exportPdf,
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF262A34),
                  foregroundColor: const Color(0xFFF1F5F9),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          // TITLE CARD (Seamless flat dark surface without border outline)
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
                borderRadius: BorderRadius.circular(14),
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
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: List.generate(_note.actionItems.length, (idx) {
                  final item = _note.actionItems[idx];
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1115),
                      borderRadius: BorderRadius.circular(10),
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
                                  if (item.deadline != '-') ...[
                                    const SizedBox(width: 8),
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
              borderRadius: BorderRadius.circular(14),
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

  Widget _buildDiscussionFlowView() {
    final text = _note.transcript.trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF181B21),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timeline, size: 16, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                const Text(
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
            Text(
              text.isEmpty ? 'Alur pembahasan tidak tersedia.' : text,
              style: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 14,
                height: 1.7,
                letterSpacing: 0.2,
              ),
            ),
          ],
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
