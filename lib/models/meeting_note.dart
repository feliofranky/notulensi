import 'dart:convert';
import 'package:intl/intl.dart';

class ActionItem {
  final String task;
  final String pic;
  final String deadline;
  bool isCompleted;

  ActionItem({
    required this.task,
    required this.pic,
    required this.deadline,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() => {
        'task': task,
        'pic': pic,
        'deadline': deadline,
        'isCompleted': isCompleted,
      };

  factory ActionItem.fromJson(Map<String, dynamic> json) => ActionItem(
        task: json['task'] ?? '',
        pic: json['pic'] ?? 'Tim',
        deadline: json['deadline'] ?? '-',
        isCompleted: json['isCompleted'] ?? false,
      );
}

class MeetingNote {
  final String id;
  String title;
  final DateTime date;
  final int durationSeconds;
  final String? audioPath;
  final String summary;
  final List<String> decisions;
  final List<ActionItem> actionItems;
  final String transcript;
  final String rawResponse;

  MeetingNote({
    required this.id,
    required this.title,
    required this.date,
    required this.durationSeconds,
    this.audioPath,
    required this.summary,
    required this.decisions,
    required this.actionItems,
    required this.transcript,
    this.rawResponse = '',
  });

  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}d';
    }
    return '${seconds} detik';
  }

  String get formattedDate {
    return DateFormat('dd MMMM yyyy, HH:mm', 'id').format(date);
  }

  /// Format bersih dan profesional siap dibagikan ke WhatsApp tanpa emoji
  String toWhatsAppFormat() {
    final buffer = StringBuffer();
    final dateStr = DateFormat('EEEE, dd MMM yyyy - HH:mm', 'id').format(date);

    buffer.writeln('*NOTULENSI RAPAT: ${title.toUpperCase()}*');
    buffer.writeln('Tanggal: $dateStr');
    buffer.writeln('Durasi Rekaman: $formattedDuration');
    buffer.writeln('─────────────────────────');
    buffer.writeln('');

    if (summary.trim().isNotEmpty) {
      buffer.writeln('*RINGKASAN EKSEKUTIF:*');
      buffer.writeln(summary.trim());
      buffer.writeln('');
    }

    if (decisions.isNotEmpty) {
      buffer.writeln('*KEPUTUSAN RAPAT:*');
      for (int i = 0; i < decisions.length; i++) {
        buffer.writeln('${i + 1}. ${decisions[i]}');
      }
      buffer.writeln('');
    }

    if (actionItems.isNotEmpty) {
      buffer.writeln('*ACTION ITEMS & PIC:*');
      for (int i = 0; i < actionItems.length; i++) {
        final item = actionItems[i];
        final dl = item.deadline != '-' ? ' (Deadline: ${item.deadline})' : '';
        buffer.writeln('${i + 1}. [${item.pic}] ${item.task}$dl');
      }
      buffer.writeln('');
    }

    buffer.writeln('─────────────────────────');
    buffer.writeln('_Disusun oleh HerzNote AI_');

    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date.toIso8601String(),
        'durationSeconds': durationSeconds,
        'audioPath': audioPath,
        'summary': summary,
        'decisions': decisions,
        'actionItems': actionItems.map((e) => e.toJson()).toList(),
        'transcript': transcript,
        'rawResponse': rawResponse,
      };

  factory MeetingNote.fromJson(Map<String, dynamic> json) => MeetingNote(
        id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: json['title'] ?? 'Rapat Tanpa Judul',
        date: json['date'] != null
            ? DateTime.parse(json['date'])
            : DateTime.now(),
        durationSeconds: json['durationSeconds'] ?? 0,
        audioPath: json['audioPath'],
        summary: json['summary'] ?? '',
        decisions: (json['decisions'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        actionItems: (json['actionItems'] as List<dynamic>?)
                ?.map((e) => ActionItem.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            [],
        transcript: json['transcript'] ?? '',
        rawResponse: json['rawResponse'] ?? '',
      );
}
