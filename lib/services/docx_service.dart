import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/meeting_note.dart';

class DocxService {
  static const MethodChannel _filesChannel = MethodChannel('com.herz.notulensi/files');

  /// Escape string agar aman di dalam XML OpenXML
  static String _esc(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Generate berkas Word (.docx) sementara dan kembalikan path serta nama berkas
  static Future<Map<String, String>> _buildDocxTempFile(MeetingNote note) async {
    final dateStr = DateFormat('EEEE, dd MMMM yyyy - HH:mm', 'id').format(note.date);

    // 1. [Content_Types].xml
    const contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''';

    // 2. _rels/.rels
    const relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    // 3. word/_rels/document.xml.rels
    const docRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';

    // 4. word/styles.xml (Standar tipografi Calibri / Arial, bersih & kompatibel Word/WPS/Docs)
    const stylesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>
        <w:sz w:val="22"/>
        <w:szCs w:val="22"/>
        <w:color w:val="111827"/>
        <w:lang w:val="id-ID"/>
      </w:rPr>
    </w:rPrDefault>
    <w:pPrDefault>
      <w:pPr>
        <w:spacing w:after="140" w:line="276" w:lineRule="auto"/>
      </w:pPr>
    </w:pPrDefault>
  </w:docDefaults>
</w:styles>''';

    // 5. word/document.xml
    final docBuffer = StringBuffer();
    docBuffer.write('''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>
''');

    // KOP KECIL ATAS
    docBuffer.write('''
    <w:p>
      <w:pPr>
        <w:spacing w:before="0" w:after="80"/>
      </w:pPr>
      <w:r>
        <w:rPr>
          <w:b/>
          <w:sz w:val="18"/>
          <w:szCs w:val="18"/>
          <w:color w:val="10B981"/>
        </w:rPr>
        <w:t>HERZNOTE | NOTULENSI RAPAT RESMI</w:t>
      </w:r>
    </w:p>
''');

    // JUDUL RAPAT (20pt Bold)
    docBuffer.write('''
    <w:p>
      <w:pPr>
        <w:spacing w:before="0" w:after="120"/>
      </w:pPr>
      <w:r>
        <w:rPr>
          <w:b/>
          <w:sz w:val="36"/>
          <w:szCs w:val="36"/>
          <w:color w:val="111827"/>
        </w:rPr>
        <w:t>${_esc(note.title)}</w:t>
      </w:r>
    </w:p>
''');

    // METADATA RAPAT (Tabel Sejajar Tanpa Garis Standar Format Resmi Kantor)
    docBuffer.write('''
    <w:tbl>
      <w:tblPr>
        <w:tblW w:w="9026" w:type="dxa"/>
        <w:tblBorders>
          <w:top w:val="none"/>
          <w:left w:val="none"/>
          <w:bottom w:val="none"/>
          <w:right w:val="none"/>
          <w:insideH w:val="none"/>
          <w:insideV w:val="none"/>
        </w:tblBorders>
        <w:tblCellMar>
          <w:top w:w="40" w:type="dxa"/>
          <w:bottom w:w="40" w:type="dxa"/>
          <w:left w:w="0" w:type="dxa"/>
          <w:right w:w="120" w:type="dxa"/>
        </w:tblCellMar>
      </w:tblPr>
      <w:tblGrid>
        <w:gridCol w:w="1800"/>
        <w:gridCol w:w="250"/>
        <w:gridCol w:w="6976"/>
      </w:tblGrid>
''');

    void addMetaRow(String label, String value) {
      docBuffer.write('''
      <w:tr>
        <w:tc>
          <w:tcPr><w:tcW w:w="1800" w:type="dxa"/></w:tcPr>
          <w:p><w:pPr><w:spacing w:after="40"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="20"/><w:color w:val="4B5563"/></w:rPr><w:t>${_esc(label)}</w:t></w:r></w:p>
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="250" w:type="dxa"/></w:tcPr>
          <w:p><w:pPr><w:spacing w:after="40"/></w:pPr><w:r><w:rPr><w:sz w:val="20"/><w:color w:val="4B5563"/></w:rPr><w:t>:</w:t></w:r></w:p>
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="6976" w:type="dxa"/></w:tcPr>
          <w:p><w:pPr><w:spacing w:after="40"/></w:pPr><w:r><w:rPr><w:sz w:val="20"/><w:color w:val="111827"/></w:rPr><w:t>${_esc(value)}</w:t></w:r></w:p>
        </w:tc>
      </w:tr>
''');
    }

    addMetaRow('Hari, Tanggal', dateStr);
    addMetaRow('Waktu / Durasi', note.formattedDuration);
    if (note.location.trim().isNotEmpty) addMetaRow('Tempat / Media', note.location.trim());
    if (note.leader.trim().isNotEmpty) addMetaRow('Pimpinan Rapat', note.leader.trim());
    if (note.notetaker.trim().isNotEmpty) addMetaRow('Notulis', note.notetaker.trim());
    if (note.participants.trim().isNotEmpty) addMetaRow('Peserta Hadir', note.participants.trim());

    docBuffer.write('    </w:tbl>\n');

    // GARIS PEMISAH
    docBuffer.write('''
    <w:p>
      <w:pPr>
        <w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="E2E8F0"/></w:pBdr>
        <w:spacing w:before="60" w:after="220"/>
      </w:pPr>
    </w:p>
''');

    // 1. AGENDA RAPAT (Jika ada)
    if (note.agenda.isNotEmpty) {
      docBuffer.write('''
    <w:p>
      <w:pPr><w:spacing w:before="160" w:after="100"/></w:pPr>
      <w:r>
        <w:rPr><w:b/><w:sz w:val="24"/><w:szCs w:val="24"/><w:color w:val="111827"/></w:rPr>
        <w:t>AGENDA RAPAT</w:t>
      </w:r>
    </w:p>
''');
      for (int i = 0; i < note.agenda.length; i++) {
        final item = note.agenda[i].trim();
        if (item.isEmpty) continue;
        docBuffer.write('''
    <w:p>
      <w:pPr><w:ind w:left="360" w:hanging="360"/><w:spacing w:after="80"/></w:pPr>
      <w:r><w:rPr><w:b/><w:color w:val="10B981"/></w:rPr><w:t>${i + 1}.  </w:t></w:r>
      <w:r><w:t>${_esc(item)}</w:t></w:r>
    </w:p>
''');
      }
    }

    // 2. RINGKASAN PEMBAHASAN (Justified)
    if (note.summary.trim().isNotEmpty) {
      docBuffer.write('''
    <w:p>
      <w:pPr><w:spacing w:before="200" w:after="100"/></w:pPr>
      <w:r>
        <w:rPr><w:b/><w:sz w:val="24"/><w:szCs w:val="24"/><w:color w:val="111827"/></w:rPr>
        <w:t>RINGKASAN PEMBAHASAN</w:t>
      </w:r>
    </w:p>
''');
      final paragraphs = note.summary
          .trim()
          .split(RegExp(r'\n+'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty);
      for (final pText in paragraphs) {
        docBuffer.write('''
    <w:p>
      <w:pPr><w:jc w:val="both"/><w:spacing w:after="140" w:line="276" w:lineRule="auto"/></w:pPr>
      <w:r><w:t>${_esc(pText)}</w:t></w:r>
    </w:p>
''');
      }
    }

    // 3. KEPUTUSAN RAPAT
    if (note.decisions.isNotEmpty) {
      docBuffer.write('''
    <w:p>
      <w:pPr><w:spacing w:before="200" w:after="100"/></w:pPr>
      <w:r>
        <w:rPr><w:b/><w:sz w:val="24"/><w:szCs w:val="24"/><w:color w:val="111827"/></w:rPr>
        <w:t>KEPUTUSAN RAPAT</w:t>
      </w:r>
    </w:p>
''');
      for (int i = 0; i < note.decisions.length; i++) {
        final dec = note.decisions[i].trim();
        if (dec.isEmpty) continue;
        docBuffer.write('''
    <w:p>
      <w:pPr><w:ind w:left="360" w:hanging="360"/><w:spacing w:after="90"/></w:pPr>
      <w:r><w:rPr><w:b/><w:color w:val="10B981"/></w:rPr><w:t>${i + 1}.  </w:t></w:r>
      <w:r><w:t>${_esc(dec)}</w:t></w:r>
    </w:p>
''');
      }
    }

    // 4. ACTION ITEMS & PENANGGUNG JAWAB (Tabel OpenXML Asli dengan Header Emerald)
    if (note.actionItems.isNotEmpty) {
      docBuffer.write('''
    <w:p>
      <w:pPr><w:spacing w:before="220" w:after="120"/></w:pPr>
      <w:r>
        <w:rPr><w:b/><w:sz w:val="24"/><w:szCs w:val="24"/><w:color w:val="111827"/></w:rPr>
        <w:t>ACTION ITEMS &amp; PENANGGUNG JAWAB</w:t>
      </w:r>
    </w:p>
    <w:tbl>
      <w:tblPr>
        <w:tblW w:w="9026" w:type="dxa"/>
        <w:tblBorders>
          <w:top w:val="single" w:sz="4" w:space="0" w:color="D1D5DB"/>
          <w:left w:val="single" w:sz="4" w:space="0" w:color="D1D5DB"/>
          <w:bottom w:val="single" w:sz="4" w:space="0" w:color="D1D5DB"/>
          <w:right w:val="single" w:sz="4" w:space="0" w:color="D1D5DB"/>
          <w:insideH w:val="single" w:sz="4" w:space="0" w:color="E5E7EB"/>
          <w:insideV w:val="single" w:sz="4" w:space="0" w:color="E5E7EB"/>
        </w:tblBorders>
        <w:tblCellMar>
          <w:top w:w="120" w:type="dxa"/>
          <w:bottom w:w="120" w:type="dxa"/>
          <w:left w:w="160" w:type="dxa"/>
          <w:right w:w="160" w:type="dxa"/>
        </w:tblCellMar>
      </w:tblPr>
      <w:tblGrid>
        <w:gridCol w:w="600"/>
        <w:gridCol w:w="4226"/>
        <w:gridCol w:w="1800"/>
        <w:gridCol w:w="1400"/>
        <w:gridCol w:w="1000"/>
      </w:tblGrid>
      <!-- Header Row -->
      <w:tr>
        <w:trPr><w:tblHeader/></w:trPr>
        <w:tc>
          <w:tcPr><w:tcW w:w="600" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="10B981"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:spacing w:after="0"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr><w:t>No</w:t></w:r></w:p>
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="4226" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="10B981"/></w:tcPr>
          <w:p><w:pPr><w:spacing w:after="0"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr><w:t>Tugas / Pekerjaan</w:t></w:r></w:p>
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="1800" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="10B981"/></w:tcPr>
          <w:p><w:pPr><w:spacing w:after="0"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr><w:t>PIC</w:t></w:r></w:p>
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="1400" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="10B981"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:spacing w:after="0"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr><w:t>Deadline</w:t></w:r></w:p>
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="1000" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="10B981"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:spacing w:after="0"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="FFFFFF"/></w:rPr><w:t>Status</w:t></w:r></w:p>
        </w:tc>
      </w:tr>
''');

      for (int i = 0; i < note.actionItems.length; i++) {
        final item = note.actionItems[i];
        final isEven = i % 2 == 1;
        final rowBg = isEven ? 'F8FAFC' : 'FFFFFF';
        final statusColor = item.isCompleted ? '10B981' : '6B7280';
        final statusText = item.isCompleted ? 'Selesai' : '-';

        docBuffer.write('''
      <w:tr>
        <w:tc>
          <w:tcPr><w:tcW w:w="600" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="$rowBg"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:spacing w:after="0"/></w:pPr><w:r><w:t>${i + 1}</w:t></w:r></w:p>
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="4226" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="$rowBg"/></w:tcPr>
          <w:p><w:pPr><w:spacing w:after="0"/></w:pPr><w:r><w:t>${_esc(item.task)}</w:t></w:r></w:p>
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="1800" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="$rowBg"/></w:tcPr>
          <w:p><w:pPr><w:spacing w:after="0"/></w:pPr><w:r><w:t>${_esc(item.pic)}</w:t></w:r></w:p>
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="1400" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="$rowBg"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:spacing w:after="0"/></w:pPr><w:r><w:t>${_esc(item.deadline)}</w:t></w:r></w:p>
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="1000" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="$rowBg"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:spacing w:after="0"/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="$statusColor"/></w:rPr><w:t>$statusText</w:t></w:r></w:p>
        </w:tc>
      </w:tr>
''');
      }
      docBuffer.write('    </w:tbl>\n');
    }

    // 5. ALUR PEMBAHASAN LENGKAP
    final transcript = note.transcript.trim();
    if (transcript.isNotEmpty) {
      docBuffer.write('''
    <w:p>
      <w:pPr><w:spacing w:before="220" w:after="100"/></w:pPr>
      <w:r>
        <w:rPr><w:b/><w:sz w:val="24"/><w:szCs w:val="24"/><w:color w:val="111827"/></w:rPr>
        <w:t>ALUR PEMBAHASAN</w:t>
      </w:r>
    </w:p>
''');
      final paragraphs = transcript
          .split(RegExp(r'\n+'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty);
      for (final pText in paragraphs) {
        // Cek pola sub-bab seperti "1. Pembukaan:"
        final sectionMatch = RegExp(r'^(\d+\.\s+[^:\n]{2,50}:)\s*(.*)$').firstMatch(pText);
        if (sectionMatch != null) {
          final headingPart = sectionMatch.group(1)!;
          final bodyPart = sectionMatch.group(2) ?? '';
          docBuffer.write('''
    <w:p>
      <w:pPr><w:jc w:val="both"/><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr>
      <w:r><w:rPr><w:b/></w:rPr><w:t>${_esc(headingPart)} </w:t></w:r>
      <w:r><w:t>${_esc(bodyPart)}</w:t></w:r>
    </w:p>
''');
        } else {
          docBuffer.write('''
    <w:p>
      <w:pPr><w:jc w:val="both"/><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr>
      <w:r><w:t>${_esc(pText)}</w:t></w:r>
    </w:p>
''');
        }
      }
    }

    // 6. KOLOM TANDA TANGAN FORMAL (2 KOLOM - SEVIMA STANDARD)
    final leaderSign = note.leader.trim().isNotEmpty
        ? '( ${_esc(note.leader.trim())} )'
        : '( ........................................ )';
    final notetakerSign = note.notetaker.trim().isNotEmpty
        ? '( ${_esc(note.notetaker.trim())} )'
        : '( ........................................ )';

    docBuffer.write('''
    <w:p><w:pPr><w:spacing w:before="450" w:after="120"/></w:pPr></w:p>
    <w:tbl>
      <w:tblPr>
        <w:tblW w:w="9026" w:type="dxa"/>
        <w:tblBorders>
          <w:top w:val="none"/>
          <w:left w:val="none"/>
          <w:bottom w:val="none"/>
          <w:right w:val="none"/>
          <w:insideH w:val="none"/>
          <w:insideV w:val="none"/>
        </w:tblBorders>
      </w:tblPr>
      <w:tblGrid>
        <w:gridCol w:w="4513"/>
        <w:gridCol w:w="4513"/>
      </w:tblGrid>
      <w:tr>
        <w:tc>
          <w:tcPr><w:tcW w:w="4513" w:type="dxa"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:spacing w:after="40"/></w:pPr><w:r><w:t>Disetujui oleh,</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/><w:spacing w:after="40"/></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t>Pimpinan Rapat</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/><w:spacing w:before="900" w:after="40"/></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t>$leaderSign</w:t></w:r></w:p>
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="4513" w:type="dxa"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:spacing w:after="40"/></w:pPr><w:r><w:t>Dibuat oleh,</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/><w:spacing w:after="40"/></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t>Notulis</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/><w:spacing w:before="900" w:after="40"/></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t>$notetakerSign</w:t></w:r></w:p>
        </w:tc>
      </w:tr>
    </w:tbl>
''');

    // PAGE SETUP (A4 twips)
    docBuffer.write('''
    <w:sectPr>
      <w:pgSz w:w="11906" w:h="16838"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>
    </w:sectPr>
  </w:body>
</w:document>
''');

    // 6. Zip into .docx file
    final archive = Archive();
    void addStringToZip(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    addStringToZip('[Content_Types].xml', contentTypesXml);
    addStringToZip('_rels/.rels', relsXml);
    addStringToZip('word/_rels/document.xml.rels', docRelsXml);
    addStringToZip('word/styles.xml', stylesXml);
    addStringToZip('word/document.xml', docBuffer.toString());

    final zipEncoder = ZipEncoder();
    final docxBytes = zipEncoder.encode(archive);
    if (docxBytes == null) {
      throw Exception('Gagal mengompresi struktur dokumen Word');
    }

    final dir = await getTemporaryDirectory();
    final rawClean = note.title
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s_-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final shortName = rawClean.length > 42
        ? rawClean.substring(0, 42)
        : (rawClean.isEmpty ? 'Rapat' : rawClean);
    final fileName = 'Notulensi_$shortName.docx';
    final filePath = p.join(dir.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(docxBytes);

    return {'filePath': filePath, 'fileName': fileName};
  }

  /// Ekspor dokumen Word dengan Bottom Sheet elegan 2 opsi: Simpan ke Download & Bagikan
  static Future<void> exportDocx(MeetingNote note, BuildContext context) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bottomSheetCtx) {
        return Container(
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
                'Ekspor Dokumen Word (.docx)',
                style: TextStyle(
                  color: Color(0xFFF1F5F9),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Format standar rapi siap cetak dan mudah diedit di Microsoft Word & WPS.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 20),

              // Opsi 1: Simpan ke Folder Download
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  Navigator.pop(bottomSheetCtx);
                  await _saveDocxToDownloads(note, context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1115),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF262A34)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF132238),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.download_rounded, color: Color(0xFF38BDF8), size: 22),
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
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Tersimpan di memori HP agar mudah dibuka',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Opsi 2: Bagikan Dokumen Word
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  Navigator.pop(bottomSheetCtx);
                  await _shareDocx(note, context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1115),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF262A34)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F291E),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.share_rounded, color: Color(0xFF10B981), size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Bagikan Dokumen (.docx)',
                              style: TextStyle(
                                color: Color(0xFFF1F5F9),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Kirim via WhatsApp, Email, Telegram, dll.',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<void> _saveDocxToDownloads(MeetingNote note, BuildContext context) async {
    try {
      final info = await _buildDocxTempFile(note);
      final filePath = info['filePath']!;
      final fileName = info['fileName']!;

      final savedUri = await _filesChannel.invokeMethod<String>('saveDocxToDownloads', {
        'filePath': filePath,
        'fileName': fileName,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 4),
            content: Text('Disimpan ke Download: $fileName'),
            action: (savedUri != null && savedUri.isNotEmpty)
                ? SnackBarAction(
                    label: 'Buka',
                    textColor: Colors.white,
                    onPressed: () async {
                      try {
                        await _filesChannel.invokeMethod('openDocxUri', {'uri': savedUri});
                      } catch (_) {}
                    },
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Gagal menyimpan Word: ${e.toString()}'),
          ),
        );
      }
    }
  }

  static Future<void> _shareDocx(MeetingNote note, BuildContext context) async {
    try {
      final info = await _buildDocxTempFile(note);
      final filePath = info['filePath']!;
      final fileName = info['fileName']!;

      await Share.shareXFiles(
        [XFile(filePath, mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')],
        subject: note.title,
        text: 'Dokumen Notulensi Rapat: ${note.title}',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Gagal membagikan Word: ${e.toString()}'),
          ),
        );
      }
    }
  }
}
