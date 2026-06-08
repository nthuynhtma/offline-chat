import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:offline_chat/database/tables/messages_table.dart';
import 'package:offline_chat/features/chat/models/message_model.dart';
import 'package:offline_chat/features/session/models/session_model.dart';

/// Service export session ra file text/PDF.
abstract interface class ExportSessionService {
  /// Export session thành file .txt
  Future<String> exportToText({
    required SessionModel session,
    required List<MessageModel> messages,
  });

  /// Export session thành file .md (Markdown)
  Future<String> exportToMarkdown({
    required SessionModel session,
    required List<MessageModel> messages,
  });
}

class ExportSessionServiceImpl implements ExportSessionService {
  static const String _exportDir = 'exports';

  @override
  Future<String> exportToText({
    required SessionModel session,
    required List<MessageModel> messages,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(dir.path, _exportDir));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final safeName = session.title
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final filename = '${safeName}_$timestamp.txt';
    final filePath = p.join(exportDir.path, filename);

    final buffer = StringBuffer();
    buffer.writeln('=== ${session.title} ===');
    buffer.writeln(
        'Exported: ${DateTime.now().toLocal().toString().split('.').first}');
    buffer.writeln('---');

    for (final msg in messages) {
      final role = msg.role == MessageRole.user ? 'You' : 'Assistant';
      buffer.writeln('');
      buffer.writeln('[$role]');
      buffer.writeln(msg.content);
    }

    buffer.writeln('');
    buffer.writeln('---');
    buffer.writeln(
        'Exported from Offline Chat - ${messages.length} messages');

    final file = File(filePath);
    await file.writeAsString(buffer.toString());

    return filePath;
  }

  @override
  Future<String> exportToMarkdown({
    required SessionModel session,
    required List<MessageModel> messages,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(dir.path, _exportDir));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final safeName = session.title
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final filename = '${safeName}_$timestamp.md';
    final filePath = p.join(exportDir.path, filename);

    final buffer = StringBuffer();
    buffer.writeln('# ${session.title}');
    buffer.writeln('');
    buffer.writeln(
        '> Exported: ${DateTime.now().toLocal().toString().split('.').first}');
    buffer.writeln('');

    for (final msg in messages) {
      final role = msg.role == MessageRole.user ? '👤 **You**' : '🤖 **Assistant**';
      buffer.writeln('---');
      buffer.writeln('$role  ');
      buffer.writeln('${msg.content}  ');
      buffer.writeln('');
    }

    buffer.writeln('---');
    buffer.writeln(
        '*Exported from Offline Chat — ${messages.length} messages*');

    final file = File(filePath);
    await file.writeAsString(buffer.toString());

    return filePath;
  }
}