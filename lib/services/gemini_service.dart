import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/meeting_note.dart';

class GeminiService {
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';

  /// Uji keabsahan API Key dengan endpoint ringan /models (cepat, 0 token, kebal 503 high demand)
  static Future<bool> testApiKey(String apiKey, {String model = 'gemini-3.5-flash-lite'}) async {
    final cleanKey = apiKey.replaceAll(RegExp(r'\s+'), '').trim();
    if (cleanKey.isEmpty) {
      throw Exception('API Key kosong.');
    }
    if (cleanKey.contains('•')) {
      throw Exception('API Key rusak. Klik Ganti Key & tempel ulang.');
    }

    final url = Uri.parse('$_baseUrl?key=$cleanKey');
    http.Response response;
    try {
      response = await http.get(url).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Koneksi timeout. Cek internet.'),
      );
    } on SocketException {
      throw Exception('Tidak ada koneksi internet.');
    }

    if (response.statusCode == 200) {
      return true;
    } else if (response.statusCode == 400 || response.statusCode == 401) {
      throw Exception('API Key tidak valid.');
    } else if (response.statusCode == 403) {
      throw Exception('Akses API Key ditolak (403).');
    } else if (response.statusCode == 429 || response.statusCode == 503) {
      throw Exception('Server Gemini sedang sibuk (${response.statusCode}).');
    } else {
      String errorMsg = 'Error ${response.statusCode}';
      try {
        final errJson = jsonDecode(response.body);
        if (errJson['error']?['message'] != null) {
          errorMsg = errJson['error']['message'];
        }
      } catch (_) {}
      throw Exception(errorMsg);
    }
  }

  /// Proses audio rapat langsung ke multimodal AI dengan auto-fallback jika server sibuk
  static Future<MeetingNote> processMeetingAudio({
    required String audioPath,
    required int durationSeconds,
    required String apiKey,
    String model = 'gemini-3.5-flash-lite',
    void Function(String status)? onProgress,
    String? existingId,
    DateTime? existingDate,
  }) async {
    final cleanKey = apiKey.replaceAll(RegExp(r'\s+'), '').trim();
    if (cleanKey.isEmpty) {
      throw Exception('API Key belum diisi. Silakan atur di menu Pengaturan.');
    }
    if (cleanKey.contains('•')) {
      throw Exception('API Key perlu diinput ulang di Pengaturan (klik Ganti Key).');
    }

    final file = File(audioPath);
    if (!await file.exists()) {
      throw Exception('File rekaman audio tidak ditemukan.');
    }

    onProgress?.call('Menyiapkan berkas audio...');
    final bytes = await file.readAsBytes();
    final base64Audio = base64Encode(bytes);

    // Daftar model untuk auto-fallback jika server utama sedang padat/503/429
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
        onProgress?.call('Server sedang sibuk, beralih ke jalur cadangan...');
        await Future.delayed(const Duration(seconds: 2));
      } else {
        onProgress?.call('Mengirim audio untuk diproses...');
      }

      try {
        final note = await _sendAudioToModel(
          audioPath: audioPath,
          durationSeconds: durationSeconds,
          apiKey: cleanKey,
          base64Audio: base64Audio,
          model: currentModel,
          onProgress: onProgress,
          existingId: existingId,
          existingDate: existingDate,
        );
        return note;
      } catch (e) {
        final rawErr = e.toString();
        final safeErr = _sanitizeError(rawErr);
        lastErrorMessage = safeErr;

        final isRetryable = rawErr.contains('high demand') ||
            rawErr.contains('503') ||
            rawErr.contains('429') ||
            rawErr.contains('RESOURCE_EXHAUSTED') ||
            rawErr.contains('temporarily unavailable') ||
            rawErr.contains('timeout') ||
            rawErr.contains('Deadline Exceeded');

        if (!isRetryable || i == modelsToTry.length - 1) {
          throw Exception(lastErrorMessage);
        }
      }
    }

    throw Exception(lastErrorMessage);
  }

  /// Pastikan API Key & URL mentah tidak akan pernah bocor ke layar error
  static String _sanitizeError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('connection abort') ||
        lower.contains('connection closed') ||
        lower.contains('connection reset') ||
        lower.contains('broken pipe') ||
        lower.contains('socketexception') ||
        lower.contains('failed host lookup')) {
      return 'Koneksi internet terputus saat memproses audio. Pastikan sinyal stabil lalu tekan Coba Lagi.';
    }
    if (lower.contains('high demand') || lower.contains('503')) {
      return 'Server AI sedang mengalami lonjakan trafik sementara. Silakan coba lagi sebentar lagi.';
    }
    if (lower.contains('429') || lower.contains('resource_exhausted')) {
      return 'Batas kuota permintaan sementara tercapai. Tunggu beberapa saat lalu coba lagi.';
    }
    if (lower.contains('401') || lower.contains('api key not valid')) {
      return 'API Key tidak valid. Silakan periksa kembali di menu Pengaturan.';
    }
    // Hapus semua potongan URL / query parameter yang berpotensi mengandung API key
    var cleaned = raw.replaceAll('Exception: ', '');
    cleaned = cleaned.replaceAll(RegExp(r'key=[^\s,&\)]+'), 'key=[SENSOR]');
    cleaned = cleaned.replaceAll(RegExp(r',?\s*uri=https?://[^\s\)]+'), '');
    return cleaned.trim();
  }

  static String _detectMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.mp3')) return 'audio/mp3';
    if (lower.endsWith('.m4a') || lower.endsWith('.mp4')) return 'audio/mp4';
    if (lower.endsWith('.ogg') || lower.endsWith('.opus')) return 'audio/ogg';
    if (lower.endsWith('.flac')) return 'audio/flac';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.amr') || lower.endsWith('.3gp')) return 'audio/amr';
    return 'audio/mp4';
  }

  static Future<MeetingNote> _sendAudioToModel({
    required String audioPath,
    required int durationSeconds,
    required String apiKey,
    required String base64Audio,
    required String model,
    void Function(String status)? onProgress,
    String? existingId,
    DateTime? existingDate,
  }) async {
    final prompt = '''
Kamu adalah asisten notulensi rapat eksekutif profesional.
Tugasmu menganalisis rekaman audio percakapan rapat ini secara akurat:

0. ATURAN ANTI-HALUSINASI (WAJIB):
   - Jika rekaman audio kosong, hening, hanya berisi suara latar/noise, atau tidak ada percakapan manusia yang dapat dipahami, DILARANG KERAS mengarang, menebak, atau membuat-buat isi rapat!
   - Untuk kondisi tersebut, kembalikan JSON dengan "is_empty_audio": true, serta string kosong untuk title/summary/transcript dan array kosong untuk decisions/action_items.

1. TRANSKRIPSI & BAHASA:
   - Dengarkan seluruh percakapan. Percakapan mungkin bercampur bahasa Indonesia, bahasa daerah, istilah teknis, dan gaya santai.
   - Pahami maksud utama pembicara dan rapikan ke dalam bahasa Indonesia formal yang baik tanpa mengubah esensi.

2. PENYARINGAN CERDAS:
   - Abaikan candaan, obrolan santai tidak relevan, dan filler words ("anu", "nganu", "apa namanya", "hmmm").
   - Fokuskan analisis pada esensi rapat, kesepakatan, argumen kunci, dan tanggung jawab tugas.
   - DILARANG menggunakan emoji apa pun pada semua teks output.

3. KELUARAN WAJIB JSON:
   Keluarkan HANYA JSON valid sesuai format ini:
{
  "is_empty_audio": false,
  "title": "Topik atau Judul Utama Rapat yang Ringkas dan Jelas (tanpa emoji)",
  "summary": "Ringkasan eksekutif jalannya rapat dalam 1-3 paragraf padat tentang latar belakang, pembahasan utama, dan kesimpulan.",
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
  "transcript": "Alur pembahasan rapat yang terstruktur rapi secara kronologis, dibagi menjadi bagian-bagian berurutan (misal: 1. Pembukaan & Agenda, 2. Paparan Utama, 3. Diskusi & Pertimbangan, 4. Arahan & Penutup) dengan narasi yang jelas dan mudah dibaca."
}
''';

    final url = Uri.parse('$_baseUrl/$model:generateContent?key=$apiKey');

    final payload = {
      'contents': [
        {
          'parts': [
            {
              'inlineData': {
                'mimeType': _detectMimeType(audioPath),
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
        'temperature': 0.1,
        'responseMimeType': 'application/json',
      }
    };

    onProgress?.call('Menganalisis percakapan & menyaring poin penting...');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(
      const Duration(seconds: 120),
      onTimeout: () => throw Exception('Permintaan melebihi batas waktu (120 detik). Silakan coba lagi.'),
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
      throw Exception('Error server: $errorMessage');
    }

    onProgress?.call('Menyusun notulensi, keputusan, & action items...');

    final responseData = jsonDecode(response.body);
    final candidates = responseData['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Sistem tidak menerima hasil analisis untuk audio ini.');
    }

    final rawText = candidates[0]['content']?['parts']?[0]?['text'] as String? ?? '';
    return _parseResult(
      rawText: rawText,
      audioPath: audioPath,
      durationSeconds: durationSeconds,
      existingId: existingId,
      existingDate: existingDate,
    );
  }

  /// Parser tangguh yang bisa mengekstrak JSON maupun teks berformat markdown
  static MeetingNote _parseResult({
    required String rawText,
    required String audioPath,
    required int durationSeconds,
    String? existingId,
    DateTime? existingDate,
  }) {
    final noteId = existingId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final now = existingDate ?? DateTime.now();

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

    Map<String, dynamic>? parsedMap;
    try {
      final startIndex = cleaned.indexOf('{');
      final endIndex = cleaned.lastIndexOf('}');
      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        final jsonSub = cleaned.substring(startIndex, endIndex + 1);
        parsedMap = Map<String, dynamic>.from(jsonDecode(jsonSub));
      }
    } catch (_) {
      parsedMap = null;
    }

    if (parsedMap != null) {
      final isEmptyAudio = parsedMap['is_empty_audio'] == true;
      final title = (parsedMap['title'] ?? '').toString().trim();
      final summary = (parsedMap['summary'] ?? '').toString().trim();

      if (isEmptyAudio || (title.isEmpty && summary.isEmpty)) {
        throw Exception('Tidak ada percakapan yang terdeteksi dalam rekaman audio ini.');
      }

      final decisions = <String>[];
      if (parsedMap['decisions'] is List) {
        for (var item in parsedMap['decisions']) {
          decisions.add(item.toString());
        }
      }

      final actionItems = <ActionItem>[];
      if (parsedMap['action_items'] is List) {
        for (var item in parsedMap['action_items']) {
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

      final transcript = (parsedMap['transcript'] ?? '').toString();

      return MeetingNote(
        id: noteId,
        title: title.isEmpty ? 'Notulensi Rapat' : title,
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
