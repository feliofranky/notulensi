import 'dart:convert';
import 'package:intl/intl.dart';

class ActionItem {
  String task;
  String pic;
  String deadline;
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
  List<String> agenda;
  String location;
  String leader;
  String notetaker;
  String participants;
  String summary;
  List<String> decisions;
  List<ActionItem> actionItems;
  String transcript;
  final String rawResponse;
  bool isDraft;

  MeetingNote({
    required this.id,
    required this.title,
    required this.date,
    required this.durationSeconds,
    this.audioPath,
    this.agenda = const [],
    this.location = '',
    this.leader = '',
    this.notetaker = '',
    this.participants = '',
    required this.summary,
    required this.decisions,
    required this.actionItems,
    required this.transcript,
    this.rawResponse = '',
    this.isDraft = false,
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

  /// Format rapi, visual, dan keren siap dibagikan ke WhatsApp dengan ikon elegan
  String toWhatsAppFormat() {
    final buffer = StringBuffer();
    final dateStr = DateFormat('EEEE, dd MMM yyyy - HH:mm', 'id').format(date);

    buffer.writeln('📋 *NOTULENSI RAPAT: ${title.toUpperCase()}*');
    buffer.writeln('🗓️ $dateStr');
    buffer.writeln('⏱️ Durasi Rekaman: $formattedDuration');
    if (location.trim().isNotEmpty) {
      buffer.writeln('📍 Tempat/Media: ${location.trim()}');
    }
    if (leader.trim().isNotEmpty) {
      buffer.writeln('👤 Pimpinan Rapat: ${leader.trim()}');
    }
    if (notetaker.trim().isNotEmpty) {
      buffer.writeln('✍️ Notulis: ${notetaker.trim()}');
    }
    if (participants.trim().isNotEmpty) {
      buffer.writeln('👥 Peserta Hadir: ${participants.trim()}');
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('');

    if (agenda.isNotEmpty) {
      buffer.writeln('📌 *AGENDA RAPAT:*');
      for (int i = 0; i < agenda.length; i++) {
        buffer.writeln('${i + 1}. ${agenda[i]}');
      }
      buffer.writeln('');
    }

    if (summary.trim().isNotEmpty) {
      buffer.writeln('📝 *RINGKASAN EKSEKUTIF:*');
      buffer.writeln(summary.trim());
      buffer.writeln('');
    }

    if (decisions.isNotEmpty) {
      buffer.writeln('⚖️ *KEPUTUSAN RAPAT:*');
      for (int i = 0; i < decisions.length; i++) {
        buffer.writeln('${i + 1}. ${decisions[i]}');
      }
      buffer.writeln('');
    }

    if (actionItems.isNotEmpty) {
      buffer.writeln('✅ *ACTION ITEMS & PIC:*');
      for (int i = 0; i < actionItems.length; i++) {
        final item = actionItems[i];
        final dl = item.deadline != '-' ? ' (Deadline: ${item.deadline})' : '';
        final status = item.isCompleted ? ' ✅ [Selesai]' : '';
        buffer.writeln('${i + 1}. [${item.pic}] ${item.task}$dl$status');
      }
      buffer.writeln('');
    }

    buffer.writeln('════════════════════');
    buffer.writeln('════════════════════');
    buffer.writeln('_Disusun otomatis oleh HerzNote AI_');

    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date.toIso8601String(),
        'durationSeconds': durationSeconds,
        'audioPath': audioPath,
        'agenda': agenda,
        'location': location,
        'leader': leader,
        'notetaker': notetaker,
        'participants': participants,
        'summary': summary,
        'decisions': decisions,
        'actionItems': actionItems.map((e) => e.toJson()).toList(),
        'transcript': transcript,
        'rawResponse': rawResponse,
        'isDraft': isDraft,
      };

  factory MeetingNote.fromJson(Map<String, dynamic> json) => MeetingNote(
        id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: json['title'] ?? 'Rapat Tanpa Judul',
        date: json['date'] != null
            ? DateTime.parse(json['date'])
            : DateTime.now(),
        durationSeconds: json['durationSeconds'] ?? 0,
        audioPath: json['audioPath'],
        agenda: (json['agenda'] as List<dynamic>?)
                ?.map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList() ??
            [],
        location: (json['location'] ?? '').toString(),
        leader: (json['leader'] ?? '').toString(),
        notetaker: (json['notetaker'] ?? '').toString(),
        participants: (json['participants'] ?? '').toString(),
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
        isDraft: json['isDraft'] ?? false,
      );
}
