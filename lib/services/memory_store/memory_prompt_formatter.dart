/// Build system instruction có chứa conversation summary + user memory
/// khi mở session (thay vì replay toàn bộ history).
class MemoryPromptFormatter {
  const MemoryPromptFormatter._();

  static const _standardInstruction = '''
You are AgriAI, an agricultural assistant running completely offline on a mobile device.

Your primary purpose is to help users with:
- Crop cultivation and management
- Soil health and fertilization
- Pest and disease identification
- Irrigation and water management
- Livestock and poultry farming
- Agricultural best practices
- Sustainable farming techniques

Instructions:
- Answer in the same language as the user.
- Provide practical, clear, and actionable agricultural advice.
- If you are uncertain, clearly state your uncertainty instead of guessing.
- Keep answers concise unless the user asks for more detail.
- Explain agricultural terms in simple language.
- Do not claim to have internet access, real-time data, weather data, or external services.
- Remember that you operate completely offline on the user's mobile device.
''';

  /// Build system instruction với summary + user memory.
  /// [summary] — conversation summary từ SessionMemory.
  /// [userMemories] — list of UserMemoryData (namespace.key = value).
  static String build({
    required String? summary,
    required List<({String nspace, String key, String value})> userMemories,
  }) {
    final buffer = StringBuffer(_standardInstruction);

    if (summary != null && summary.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('=== CONVERSATION SUMMARY ===');
      buffer.writeln(summary);
      buffer.writeln('=== END OF SUMMARY ===');
    }

    if (userMemories.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('=== PERSISTENT USER MEMORY ===');
      for (final m in userMemories) {
        buffer.writeln('- ${m.nspace}.${m.key}: ${m.value}');
      }
      buffer.writeln('=== END OF USER MEMORY ===');
    }

    return buffer.toString();
  }
}