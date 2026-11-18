import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/meeting_note.dart';

class StorageService {
  static const String _keyApiKey = 'gemini_api_key';
  static const String _keyModel = 'gemini_model';
  static const String _keySampleRate = 'audio_sample_rate';
  static const String _keyNotes = 'meeting_notes_v1';

  static const String defaultModel = 'gemini-3.5-flash-lite';

  // API Key
  static Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyApiKey) ?? '';
  }

  static Future<void> setApiKey(String key) async {
    final clean = key.replaceAll(RegExp(r'\s+'), '').trim();
    if (clean.contains('•')) return; // Never overwrite valid key with masked bullets
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, clean);
  }

  // Model
  static Future<String> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyModel) ?? defaultModel;
  }

  static Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyModel, model);
  }

  // Sample Rate
  static Future<int> getSampleRate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keySampleRate) ?? 16000;
  }

  static Future<void> setSampleRate(int rate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySampleRate, rate);
  }

  // Meeting Notes
  static Future<List<MeetingNote>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_keyNotes);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    try {
      final List<dynamic> list = jsonDecode(jsonString);
      return list.map((item) => MeetingNote.fromJson(Map<String, dynamic>.from(item))).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveNote(MeetingNote note) async {
    final notes = await loadNotes();
    final index = notes.indexWhere((n) => n.id == note.id);
    if (index >= 0) {
      notes[index] = note;
    } else {
      notes.insert(0, note);
    }
    await _saveAllNotes(notes);
  }

  static Future<void> deleteNote(String id) async {
    final notes = await loadNotes();
    final index = notes.indexWhere((n) => n.id == id);
    if (index >= 0) {
      final note = notes[index];
      // Hapus berkas fisik rekaman audio .wav dari storage HP agar bersih tuntas
      if (note.audioPath != null && note.audioPath!.isNotEmpty) {
        try {
          final file = File(note.audioPath!);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
      notes.removeAt(index);
      await _saveAllNotes(notes);
    }
  }

  static Future<void> _saveAllNotes(List<MeetingNote> notes) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = notes.map((n) => n.toJson()).toList();
    await prefs.setString(_keyNotes, jsonEncode(jsonList));
  }
}
