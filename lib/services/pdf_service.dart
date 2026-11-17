import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/meeting_note.dart';

class PdfService {
  static const MethodChannel _filesChannel = MethodChannel('com.herz.notulensi/files');

  /// Generate file PDF sementara dengan layout resmi kantor (Justify & Anti Orphan Heading)
  static Future<Map<String, String>> _buildPdfTempFile(MeetingNote note) async {
    final pdf = pw.Document();

    final primaryColor = PdfColor.fromHex('10B981');
    final darkColor = PdfColor.fromHex('111827');
    final grayColor = PdfColor.fromHex('4B5563');
    final lightBg = PdfColor.fromHex('F8FAFC');
    final borderColor = PdfColor.fromHex('E2E8F0');

    final dateStr = DateFormat('EEEE, dd MMMM yyyy - HH:mm', 'id').format(note.date);

    // Pecah teks alur pembahasan menjadi paragraf agar mengalir rapi antar halaman
    final rawTranscript = note.transcript.trim();
    final transcriptParagraphs = rawTranscript.isEmpty
        ? <String>[]
        : rawTranscript
            .split(RegExp(r'\n+'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();

    pw.Widget buildTranscriptParagraph(String text) {
      // Cek jika paragraf diawali pola sub-bab bernomor seperti "1. Pembukaan:"
      final sectionMatch = RegExp(r'^(\d+\.\s+[^:\n]{2,50}:)\s*(.*)$').firstMatch(text);
      if (sectionMatch != null) {
        final headingPart = sectionMatch.group(1)!;
        final bodyPart = sectionMatch.group(2) ?? '';
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.RichText(
            textAlign: pw.TextAlign.justify,
            text: pw.TextSpan(
              style: pw.TextStyle(fontSize: 10, color: darkColor, lineSpacing: 3.5),
              children: [
                pw.TextSpan(
                  text: '$headingPart ',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: darkColor),
                ),
                pw.TextSpan(text: bodyPart),
              ],
            ),
          ),
        );
      }

      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.justify,
          style: pw.TextStyle(fontSize: 10, color: darkColor, lineSpacing: 3.5),
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
        header: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'HERZNOTE | NOTULENSI RAPAT',
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryColor,
                    letterSpacing: 1.2,
                  ),
                ),
                pw.Text(
                  dateStr,
                  style: pw.TextStyle(fontSize: 8.5, color: grayColor),
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Dokumen notulensi resmi disusun oleh HerzNote AI',
                  style: pw.TextStyle(fontSize: 8, color: grayColor),
                ),
                pw.Text(
                  'Halaman ${context.pageNumber} dari ${context.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, color: grayColor),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          final widgets = <pw.Widget>[
            pw.SizedBox(height: 14),

            // JUDUL RAPAT
            pw.Text(
              note.title,
              style: pw.TextStyle(
                fontSize: 17,
                fontWeight: pw.FontWeight.bold,
                color: darkColor,
                lineSpacing: 2,
              ),
            ),
            pw.SizedBox(height: 6),

            // METADATA RAPAT
            pw.Row(
              children: [
                pw.Text(
                  'Tanggal: $dateStr',
                  style: pw.TextStyle(fontSize: 9.5, color: grayColor),
                ),
                pw.SizedBox(width: 16),
                pw.Text(
                  'Durasi Rapat: ${note.formattedDuration}',
                  style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: darkColor),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
          ];

          // RINGKASAN EKSEKUTIF (Justify)
          if (note.summary.trim().isNotEmpty) {
            widgets.add(
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: lightBg,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: borderColor, width: 0.8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'RINGKASAN EKSEKUTIF',
                      style: pw.TextStyle(
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryColor,
                        letterSpacing: 1.1,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      note.summary.trim(),
                      textAlign: pw.TextAlign.justify,
                      style: pw.TextStyle(fontSize: 10, color: darkColor, lineSpacing: 3.5),
                    ),
                  ],
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 18));
          }

          // KEPUTUSAN RAPAT (Justify + Anti Orphan Heading)
          if (note.decisions.isNotEmpty) {
            widgets.add(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'KEPUTUSAN RAPAT',
                    style: pw.TextStyle(
                      fontSize: 11.5,
                      fontWeight: pw.FontWeight.bold,
                      color: darkColor,
                      letterSpacing: 0.8,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  _buildDecisionRow(1, note.decisions.first, primaryColor, darkColor),
                ],
              ),
            );

            for (int i = 1; i < note.decisions.length; i++) {
              widgets.add(_buildDecisionRow(i + 1, note.decisions[i], primaryColor, darkColor));
            }
            widgets.add(pw.SizedBox(height: 16));
          }

          // ACTION ITEMS & PENANGGUNG JAWAB (dengan kolom Status "Selesai")
          if (note.actionItems.isNotEmpty) {
            widgets.add(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'ACTION ITEMS & PENANGGUNG JAWAB',
                    style: pw.TextStyle(
                      fontSize: 11.5,
                      fontWeight: pw.FontWeight.bold,
                      color: darkColor,
                      letterSpacing: 0.8,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Table(
                    border: pw.TableBorder.all(color: borderColor, width: 0.7),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(26),
                      1: const pw.FlexColumnWidth(3.2),
                      2: const pw.FlexColumnWidth(1.3),
                      3: const pw.FlexColumnWidth(1.0),
                      4: const pw.FlexColumnWidth(0.9),
                    },
                    children: [
                      // Table Header
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: primaryColor),
                        children: [
                          _tableHeaderCell('No', align: pw.TextAlign.center),
                          _tableHeaderCell('Tugas / Pekerjaan'),
                          _tableHeaderCell('PIC'),
                          _tableHeaderCell('Deadline', align: pw.TextAlign.center),
                          _tableHeaderCell('Status', align: pw.TextAlign.center),
                        ],
                      ),
                      // Table Rows
                      ...List.generate(note.actionItems.length, (i) {
                        final item = note.actionItems[i];
                        final isEven = i % 2 == 1;
                        return pw.TableRow(
                          decoration: pw.BoxDecoration(color: isEven ? lightBg : PdfColors.white),
                          children: [
                            _tableDataCell('${i + 1}', darkColor, align: pw.TextAlign.center),
                            _tableDataCell(item.task, darkColor, align: pw.TextAlign.left),
                            _tableDataCell(item.pic, darkColor),
                            _tableDataCell(item.deadline, grayColor, align: pw.TextAlign.center),
                            _tableDataCell(
                              item.isCompleted ? 'Selesai' : '-',
                              item.isCompleted ? primaryColor : grayColor,
                              align: pw.TextAlign.center,
                              bold: item.isCompleted,
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ],
              ),
            );
            widgets.add(pw.SizedBox(height: 18));
          }

          // ALUR PEMBAHASAN (Judul + Paragraf pertama diikat satu blok agar tidak pernah kepotong halaman)
          if (transcriptParagraphs.isNotEmpty) {
            widgets.add(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(color: borderColor, width: 0.8)),
                    ),
                    child: pw.Text(
                      'ALUR PEMBAHASAN',
                      style: pw.TextStyle(
                        fontSize: 11.5,
                        fontWeight: pw.FontWeight.bold,
                        color: darkColor,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  buildTranscriptParagraph(transcriptParagraphs.first),
                ],
              ),
            );

            for (int i = 1; i < transcriptParagraphs.length; i++) {
              widgets.add(buildTranscriptParagraph(transcriptParagraphs[i]));
            }
          }

          return widgets;
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final rawClean = note.title.replaceAll(RegExp(r'[^a-zA-Z0-9\s_-]'), '').trim().replaceAll(RegExp(r'\s+'), '_');
    final shortName = rawClean.length > 42 ? rawClean.substring(0, 42) : (rawClean.isEmpty ? 'Rapat' : rawClean);
    final fileName = 'Notulensi_$shortName.pdf';
    final filePath = p.join(dir.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    return {'filePath': filePath, 'fileName': fileName};
  }

  static pw.Widget _buildDecisionRow(int number, String text, PdfColor primaryColor, PdfColor darkColor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 20,
            child: pw.Text(
              '$number.',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: primaryColor),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              text,
              textAlign: pw.TextAlign.justify,
              style: pw.TextStyle(fontSize: 10, color: darkColor, lineSpacing: 3),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tableHeaderCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      ),
    );
  }

  static pw.Widget _tableDataCell(
    String text,
    PdfColor color, {
    pw.TextAlign align = pw.TextAlign.left,
    bool bold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          lineSpacing: 2,
        ),
      ),
    );
  }

  /// Simpan PDF langsung ke folder Download HP via Android MediaStore
  static Future<Map<String, String>> saveToDownloads(MeetingNote note) async {
    final tempInfo = await _buildPdfTempFile(note);
    final savedUri = await _filesChannel.invokeMethod<String>('savePdfToDownloads', {
      'filePath': tempInfo['filePath'],
      'fileName': tempInfo['fileName'],
    });
    return {
      'uri': savedUri ?? '',
      'fileName': tempInfo['fileName']!,
    };
  }

  /// Buka PDF yang tersimpan langsung di aplikasi PDF Viewer HP
  static Future<void> openSavedPdf(String uri) async {
    if (uri.isEmpty) return;
    await _filesChannel.invokeMethod('openPdfUri', {'uri': uri});
  }

  /// Generate dan langsung bagikan file PDF lewat Share Sheet Android
  static Future<void> generateAndSharePdf(MeetingNote note) async {
    final tempInfo = await _buildPdfTempFile(note);
    await Share.shareXFiles(
      [XFile(tempInfo['filePath']!)],
      subject: 'Notulensi: ${note.title}',
      text: 'Lampiran dokumen PDF Notulensi Rapat: ${note.title}',
    );
  }

  /// Tampilkan pop-up 2 pilihan PDF yang minimalis (Simpan ke Folder Download / Bagikan)
  static Future<void> showPdfOptionsSheet(BuildContext context, MeetingNote note) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF181B21),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
                'Dokumen PDF',
                style: TextStyle(
                  color: Color(0xFFF1F5F9),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(ctx, 'download'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1115),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0F291E),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.download_rounded, color: Color(0xFF10B981), size: 20),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Simpan ke Folder Download',
                              style: TextStyle(
                                color: Color(0xFFF1F5F9),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Tersimpan langsung di HP dan bisa langsung dibuka',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(ctx, 'share'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1115),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF262A34),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.share_outlined, color: Color(0xFFF1F5F9), size: 20),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bagikan PDF',
                              style: TextStyle(
                                color: Color(0xFFF1F5F9),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Kirim langsung ke WhatsApp, Email, atau Drive',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (action == null || !context.mounted) return;

    try {
      if (action == 'download') {
        final res = await saveToDownloads(note);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF181B21),
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Tersimpan di Download: ${res['fileName']}',
              style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 13),
            ),
            action: SnackBarAction(
              label: 'Buka',
              textColor: const Color(0xFF10B981),
              onPressed: () {
                openSavedPdf(res['uri'] ?? '');
              },
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      } else if (action == 'share') {
        await generateAndSharePdf(note);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text('Gagal memproses PDF: ${e.toString().replaceAll("Exception: ", "")}'),
        ),
      );
    }
  }
}
