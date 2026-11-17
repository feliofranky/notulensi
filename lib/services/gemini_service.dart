import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/meeting_note.dart';

class GeminiService {
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';

  /// Uji keabsahan API Key dengan request ringan
  static Future<bool> testApiKey(String apiKey, {String model = 'gemini-3.5-flash-lite'}) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      throw Exception('API Key Gemini tidak boleh kosong.');
    }

    final url = Uri.parse('$_baseUrl/$model:generateContent?key=$cleanKey');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': 'Halo, jawab hanya kata "OK"'}
            ]
          }
        ],
        'generationConfig': {
          'maxOutputTokens': 10,
        }
      }),
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw Exception('Koneksi timeout. Periksa sambungan internet.'),
    );

    if (response.statusCode == 200) {
      return true;
    } else {
      String errorMsg = 'Error ${response.statusCode}';
      try {
        final errJson = jsonDecode(response.body);
        if (errJson['error']?['message'] != null) {
          errorMsg = errJson['error']['message'];
        }
      } catch (_) {}
      throw Exception('Gagal terhubung ke Gemini: $errorMsg');
    }
  }

  /// Proses audio rapat langsung ke multimodal Gemini AI dengan auto-fallback jika model sibuk
  static Future<MeetingNote> processMeetingAudio({
    required String audioPath,
    required int durationSeconds,
    required String apiKey,
    String model = 'gemini-3.5-flash-lite',
    void Function(String status)? onProgress,
  }) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      throw Exception('API Key belum diisi. Silakan atur di menu Pengaturan.');
    }

    final file = File(audioPath);
    if (!await file.exists()) {
      throw Exception('File rekaman audio tidak ditemukan: $audioPath');
    }

    onProgress?.call('Membaca file audio rekaman...');
    final bytes = await file.readAsBytes();
    final base64Audio = base64Encode(bytes);

    // Daftar model untuk auto-fallback jika model utama sedang padat/503/429
    final modelsToTry = <String>[model];
    for (final candidate in ['gemini-3.5-flash', 'gemini-3.5-flash-lite', 'gemini-2.5-flash']) {
      if (!modelsToTry.contains(candidate)) {
        modelsToTry.add(candidate);
      }
    }

    String lastErrorMessage = '';

    for (int i = 0; i < modelsToTry.length; i++) {
      final currentModel = modelsToTry[i];
      if (i > 0) {
        onProgress?.call('Model sebelumnya padat. Beralih ke $currentModel...');
        await Future.delayed(const Duration(seconds: 2));
      } else {
        onProgress?.call('Mengirim audio ke Gemini ($currentModel)...');
      }

      try {
        final note = await _sendAudioToModel(
          audioPath: audioPath,
          durationSeconds: durationSeconds,
          apiKey: cleanKey,
          base64Audio: base64Audio,
          model: currentModel,
          onProgress: onProgress,
        );
        return note;
      } catch (e) {
        final errStr = e.toString().replaceAll('Exception: ', '');
        lastErrorMessage = errStr;

        final isRetryable = errStr.contains('high demand') ||
            errStr.contains('503') ||
            errStr.contains('429') ||
            errStr.contains('RESOURCE_EXHAUSTED') ||
            errStr.contains('temporarily unavailable') ||
            errStr.contains('timeout') ||
            errStr.contains('Deadline Exceeded');

        if (!isRetryable || i == modelsToTry.length - 1) {
          throw Exception(lastErrorMessage);
        }
      }
    }

    throw Exception(lastErrorMessage);
  }

  static Future<MeetingNote> _sendAudioToModel({
    required String audioPath,
    required int durationSeconds,
    required String apiKey,
    required String base64Audio,
    required String model,
    void Function(String status)? onProgress,
  }) async {
    final prompt = '''
Kamu adalah asisten sekretaris rapat eksekutif profesional untuk aplikasi HerzNote.
Tugasmu menganalisis rekaman audio percakapan rapat ini dengan sangat teliti:

1. TRANSKRIPSI & BAHASA:
   - Dengarkan seluruh percakapan. Percakapan mungkin bercampur bahasa Indonesia, bahasa daerah (Jawa, Sunda, dll), istilah teknis/bisnis, dan gaya santai.
   - Pahami maksud utama pembicara dan terjemahkan/rapikan ke dalam bahasa Indonesia yang baik tanpa mengubah esensi.

2. PENYARINGAN CERDAS (SMART FILTERING):
   - Abaikan dan buang semua candaan, gurauan santai, obrolan ngopi/makan, dan filler words ("anu", "nganu", "apa namanya", "hmmm", "eaaa") yang tidak relevan dengan pekerjaan.
   - Fokuskan analisis pada esensi rapat, kesepakatan, argumen kunci, dan tanggung jawab tugas.

3. KELUARAN WAJIB JSON:
   Keluarkan HANYA JSON valid sesuai format ini:
{
  "title": "Topik atau Judul Utama Rapat yang Ringkas dan Jelas",
  "summary": "Ringkasan eksekutif jalannya rapat dalam 1-3 paragraf padat tentang masalah yang dibahas dan kesimpulan.",
  "decisions": [
    "Poin keputusan 1 yang disepakati",
    "Poin keputusan 2..."
  ],
  "action_items": [
    {
      "task": "Tugas atau pekerjaan yang harus dieksekusi",
      "pic": "Nama orang atau tim penanggung jawab (atau 'Tim' jika tidak disebut nama)",
      "deadline": "Batas waktu tugas (contoh: 'Jumat ini', '25 Nov', atau '-' jika tidak ada)"
    }
  ],
  "transcript": "Transkrip intisari alur pembicaraan rapat yang bersih dari obrolan tidak penting."
}
''';

    final url = Uri.parse('$_baseUrl/$model:generateContent?key=$apiKey');

    final payload = {
      'contents': [
        {
          'parts': [
            {
              'inlineData': {
                'mimeType': audioPath.endsWith('.wav') ? 'audio/wav' : 'audio/aac',
                'data': base64Audio,
              }
            },
            {
              'text': prompt,
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.2,
        'responseMimeType': 'application/json',
      }
    };

    onProgress?.call('Gemini AI sedang mendengarkan & menganalisis...');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(
      const Duration(seconds: 120),
      onTimeout: () => throw Exception('Permintaan ke Gemini melebihi batas waktu (120 detik).'),
    );

    if (response.statusCode != 200) {
      String errorMessage = 'Kode HTTP ${response.statusCode}';
      try {
        final errJson = jsonDecode(response.body);
        if (errJson['error']?['message'] != null) {
          errorMessage = errJson['error']['message'];
        }
      } catch (_) {
        errorMessage = response.body;
      }
      throw Exception('Gemini API Error: $errorMessage');
    }

    onProgress?.call('Menyusun notulensi, keputusan, & action items...');

    final responseData = jsonDecode(response.body);
    final candidates = responseData['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini tidak memberikan jawaban untuk audio ini.');
    }

    final rawText = candidates[0]['content']?['parts']?[0]?['text'] as String? ?? '';
    return _parseResult(
      rawText: rawText,
      audioPath: audioPath,
      durationSeconds: durationSeconds,
    );
  }

  /// Parser tangguh yang bisa mengekstrak JSON maupun teks berformat markdown
  static MeetingNote _parseResult({
    required String rawText,
    required String audioPath,
    required int durationSeconds,
  }) {
    final noteId = DateTime.now().millisecondsSinceEpoch.toString();
    final now = DateTime.now();

    String cleaned = rawText.trim();
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    }
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    cleaned = cleaned.trim();

    try {
      final startIndex = cleaned.indexOf('{');
      final endIndex = cleaned.lastIndexOf('}');
      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        final jsonSub = cleaned.substring(startIndex, endIndex + 1);
        final map = jsonDecode(jsonSub);

        final title = (map['title'] ?? 'Rapat HerzNote').toString();
        final summary = (map['summary'] ?? '').toString();

        final decisions = <String>[];
        if (map['decisions'] is List) {
          for (var item in map['decisions']) {
            decisions.add(item.toString());
          }
        }

        final actionItems = <ActionItem>[];
        if (map['action_items'] is List) {
          for (var item in map['action_items']) {
            if (item is Map) {
              actionItems.add(ActionItem(
                task: (item['task'] ?? '').toString(),
                pic: (item['pic'] ?? 'Tim').toString(),
                deadline: (item['deadline'] ?? '-').toString(),
              ));
            } else {
              actionItems.add(ActionItem(
                task: item.toString(),
                pic: 'Tim',
                deadline: '-',
              ));
            }
          }
        }

        final transcript = (map['transcript'] ?? '').toString();

        return MeetingNote(
          id: noteId,
          title: title,
          date: now,
          durationSeconds: durationSeconds,
          audioPath: audioPath,
          summary: summary,
          decisions: decisions,
          actionItems: actionItems,
          transcript: transcript,
          rawResponse: rawText,
        );
      }
    } catch (_) {
      // Fallback below
    }

    // Fallback jika model menjawab dalam format teks biasa
    return MeetingNote(
      id: noteId,
      title: 'Notulensi Rapat',
      date: now,
      durationSeconds: durationSeconds,
      audioPath: audioPath,
      summary: rawText,
      decisions: ['Hasil analisis dapat dilihat pada ringkasan di bawah.'],
      actionItems: [],
      transcript: rawText,
      rawResponse: rawText,
    );
  }
}
