import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/meeting_note.dart';

class PdfService {
  /// Generate file PDF profesional berstandar laporan resmi kantor dan bagikan langsung
  static Future<String> generateAndSharePdf(MeetingNote note) async {
    final pdf = pw.Document();

    final primaryColor = PdfColor.fromHex('10B981'); // Emerald green
    final darkColor = PdfColor.fromHex('111827');
    final grayColor = PdfColor.fromHex('4B5563');
    final lightBg = PdfColor.fromHex('F3F4F6');
    final borderColor = PdfColor.fromHex('E5E7EB');

    final dateStr = DateFormat('EEEE, dd MMMM yyyy - HH:mm', 'id').format(note.date);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 12),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 1)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'HERZNOTE | NOTULENSI RAPAT',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryColor,
                    letterSpacing: 1.2,
                  ),
                ),
                pw.Text(
                  dateStr,
                  style: pw.TextStyle(fontSize: 9, color: grayColor),
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 12),
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
          return [
            pw.SizedBox(height: 12),

            // JUDUL RAPAT
            pw.Text(
              note.title,
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: darkColor,
              ),
            ),
            pw.SizedBox(height: 6),

            // INFO HEADER
            pw.Row(
              children: [
                pw.Text(
                  'Tanggal: $dateStr',
                  style: pw.TextStyle(fontSize: 10, color: grayColor),
                ),
                pw.SizedBox(width: 16),
                pw.Text(
                  'Durasi Rapat: ${note.formattedDuration}',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: darkColor),
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // RINGKASAN EKSEKUTIF
            if (note.summary.trim().isNotEmpty) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: lightBg,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: borderColor),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'RINGKASAN EKSEKUTIF',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: primaryColor,
                        letterSpacing: 1.1,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      note.summary.trim(),
                      style: pw.TextStyle(fontSize: 10, color: darkColor, lineSpacing: 3),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
            ],

            // KEPUTUSAN RAPAT
            if (note.decisions.isNotEmpty) ...[
              pw.Text(
                'KEPUTUSAN RAPAT',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: darkColor,
                  letterSpacing: 1,
                ),
              ),
              pw.SizedBox(height: 8),
              ...note.decisions.asMap().entries.map((entry) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 18,
                        child: pw.Text(
                          '${entry.key + 1}.',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: primaryColor),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          entry.value,
                          style: pw.TextStyle(fontSize: 10, color: darkColor, lineSpacing: 2),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              pw.SizedBox(height: 16),
            ],

            // ACTION ITEMS & PENANGGUNG JAWAB
            if (note.actionItems.isNotEmpty) ...[
              pw.Text(
                'ACTION ITEMS & PENANGGUNG JAWAB',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: darkColor,
                  letterSpacing: 1,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: pw.BoxDecoration(color: primaryColor),
                cellStyle: pw.TextStyle(fontSize: 9, color: darkColor),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                headers: ['No', 'Tugas / Pekerjaan', 'Penanggung Jawab (PIC)', 'Batas Waktu'],
                columnWidths: {
                  0: const pw.FixedColumnWidth(28),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(1.2),
                },
                data: List<List<String>>.generate(note.actionItems.length, (i) {
                  final item = note.actionItems[i];
                  return [
                    '${i + 1}',
                    item.task,
                    item.pic,
                    item.deadline,
                  ];
                }),
              ),
              pw.SizedBox(height: 16),
            ],

            // ALUR PEMBAHASAN RAPAT
            if (note.transcript.trim().isNotEmpty) ...[
              pw.Text(
                'ALUR PEMBAHASAN LENGKAP',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: darkColor,
                  letterSpacing: 1,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: lightBg,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: borderColor),
                ),
                child: pw.Text(
                  note.transcript.trim(),
                  style: pw.TextStyle(fontSize: 9.5, color: darkColor, lineSpacing: 3),
                ),
              ),
            ],
          ];
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final cleanTitle = note.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final filePath = p.join(dir.path, 'Notulensi_$cleanTitle.pdf');
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    // Bagikan langsung via native share sheet
    await Share.shareXFiles(
      [XFile(filePath)],
      subject: 'Notulensi: ${note.title}',
      text: 'Berikut lampiran dokumen PDF Notulensi Rapat: ${note.title}',
    );

    return filePath;
  }
}
