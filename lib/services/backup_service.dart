import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/meeting_note.dart';
import 'storage_service.dart';

class BackupService {
  static const MethodChannel _filesChannel = MethodChannel('com.herz.notulensi/files');

  /// Ekspor seluruh riwayat notulensi menjadi berkas JSON terstruktur
  static Future<void> exportBackup(BuildContext context) async {
    final notes = await StorageService.loadNotes();
    if (notes.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF64748B),
            content: Text('Belum ada riwayat notulensi untuk dicadangkan.'),
          ),
        );
      }
      return;
    }

    final now = DateTime.now();
    final timeStamp = DateFormat('yyyyMMdd_HHmm').format(now);
    final backupFileName = 'HERZnote_Backup_$timeStamp.json';

    final backupPayload = {
      'app': 'HERZnote',
      'version': 1,
      'exportedAt': now.toIso8601String(),
      'notesCount': notes.length,
      'notes': notes.map((n) => n.toJson()).toList(),
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(backupPayload);
    final dir = await getTemporaryDirectory();
    final tempFilePath = p.join(dir.path, backupFileName);
    final tempFile = File(tempFilePath);
    await tempFile.writeAsString(jsonString, encoding: utf8);

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
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
                'Cadangkan Riwayat Notulensi',
                style: TextStyle(
                  color: Color(0xFFF1F5F9),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Mengemas ${notes.length} notulensi ke dalam berkas cadangan resmi (.json).',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 20),

              // Opsi 1: Simpan ke Folder Download
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  try {
                    await _filesChannel.invokeMethod<String>('saveBackupToDownloads', {
                      'filePath': tempFilePath,
                      'fileName': backupFileName,
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF10B981),
                          content: Text('Cadangan disimpan ke Download: $backupFileName'),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFFEF4444),
                          content: Text('Gagal menyimpan cadangan: $e'),
                        ),
                      );
                    }
                  }
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
                              'Aman disimpan di memori internal HP',
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

              // Opsi 2: Bagikan File Cadangan
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  try {
                    await Share.shareXFiles(
                      [XFile(tempFilePath, mimeType: 'application/json')],
                      subject: 'Cadangan Notulensi HERZnote',
                      text: 'Berkas cadangan riwayat notulensi HERZnote (${notes.length} rapat).',
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFFEF4444),
                          content: Text('Gagal membagikan cadangan: $e'),
                        ),
                      );
                    }
                  }
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
                              'Bagikan Berkas Cadangan (.json)',
                              style: TextStyle(
                                color: Color(0xFFF1F5F9),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Kirim ke HP lain via WA, Google Drive, Email, dll.',
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

  /// Memulihkan riwayat notulensi dari berkas JSON yang dipilih
  static Future<void> restoreBackup(BuildContext context, {required VoidCallback onRestored}) async {
    try {
      final jsonString = await _filesChannel.invokeMethod<String>('pickBackupFile');
      if (jsonString == null || jsonString.isEmpty) {
        return; // Pengguna membatalkan pemilihan
      }

      final dynamic parsed = jsonDecode(jsonString);
      if (parsed is! Map<String, dynamic> ||
          parsed['app'] != 'HERZnote' ||
          parsed['notes'] is! List) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFFEF4444),
              content: Text('Format tidak valid. Pilih berkas cadangan resmi HERZnote (.json).'),
            ),
          );
        }
        return;
      }

      final rawList = parsed['notes'] as List;
      final backupNotes = <MeetingNote>[];
      for (final item in rawList) {
        if (item is Map) {
          try {
            backupNotes.add(MeetingNote.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
      }

      if (backupNotes.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFFEF4444),
              content: Text('Berkas cadangan tidak memuat data notulensi yang dapat dipulihkan.'),
            ),
          );
        }
        return;
      }

      if (!context.mounted) return;

      // Tampilkan Dialog Pemulihan Cerdas: Gabungkan vs Ganti Semua
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: const Color(0xFF181B21),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Pulihkan Notulensi',
            style: TextStyle(color: Color(0xFFF1F5F9), fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ditemukan ${backupNotes.length} notulensi dalam berkas cadangan.',
                style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 14),
              ),
              const SizedBox(height: 12),
              const Text(
                'Pilih metode pemulihan data:',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 16),

              // Tombol Gabungkan (Merge)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.pop(dialogCtx, 'merge'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1115),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF10B981)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.merge_type_rounded, size: 18, color: Color(0xFF10B981)),
                          SizedBox(width: 8),
                          Text(
                            'Gabungkan (Disarankan)',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Menambahkan data cadangan tanpa menghapus riwayat notulensi yang ada di HP sekarang.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Tombol Ganti Semua (Replace)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.pop(dialogCtx, 'replace'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1115),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.swap_horiz_rounded, size: 18, color: Color(0xFFF87171)),
                          SizedBox(width: 8),
                          Text(
                            'Ganti Semua Data',
                            style: TextStyle(
                              color: Color(0xFFF87171),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Menghapus riwayat yang ada di HP saat ini dan menggantinya dengan data cadangan.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, 'cancel'),
              child: const Text('Batal', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
          ],
        ),
      );

      if (choice == null || choice == 'cancel') return;

      if (choice == 'replace') {
        await StorageService.saveAllNotes(backupNotes);
        onRestored();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Text('Berhasil memulihkan ${backupNotes.length} notulensi.'),
            ),
          );
        }
      } else if (choice == 'merge') {
        final currentNotes = await StorageService.loadNotes();
        final currentMap = {for (final n in currentNotes) n.id: n};

        int addedCount = 0;
        int updatedCount = 0;

        for (final backupNote in backupNotes) {
          if (currentMap.containsKey(backupNote.id)) {
            // Jika ID sudah ada, timpa hanya jika tanggal backupNote lebih baru
            currentMap[backupNote.id] = backupNote;
            updatedCount++;
          } else {
            currentMap[backupNote.id] = backupNote;
            addedCount++;
          }
        }

        final mergedList = currentMap.values.toList();
        // Urutkan berdasarkan tanggal terbaru di atas
        mergedList.sort((a, b) => b.date.compareTo(a.date));

        await StorageService.saveAllNotes(mergedList);
        onRestored();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Text(
                'Pemulihan selesai: $addedCount notulensi baru ditambahkan, $updatedCount diperbarui.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Gagal memulihkan cadangan: $e'),
          ),
        );
      }
    }
  }
}
