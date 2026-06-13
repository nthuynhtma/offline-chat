// ═══════════════════════════════════════════════════════════════════════════════
// DYNAMIC BUDGET ALLOCATION (VERSION=dynamic_budget_v3)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Phân bổ context budget động dựa trên loại câu hỏi.
// Thay vì dùng ratio cố định cho mọi query, phân loại query và điều chỉnh
// phân bổ cho phù hợp:
//   - conversational (chào hỏi): nhiều history, ít RAG
//   - factual (thông tin cụ thể): ít history, nhiều RAG
//   - complex (phân tích sâu): cân bằng
//   - creative (viết văn, sáng tạo): ít RAG, nhiều history, nhiều response
//   - summarization (tóm tắt): ít system, nhiều RAG
//   - translation (dịch thuật): ít RAG, nhiều history, nhiều response
//   - math_coding (toán/lập trình): nhiều RAG, nhiều response
//   - multi_hop (nhiều bước suy luận): nhiều RAG, nhiều history
//
// HỖ TRỢ PHÂN LOẠI CẢ TIẾNG VIỆT VÀ TIẾNG ANH.
//
// Dùng kèm: kGemmaMaxTokens (=2048) từ model_constants.dart
//
// Thứ tự ưu tiên classification:
//   1. translation       (từ khoá rất specific)
//   2. summarization     (từ khoá specific)
//   3. conversational    (greeting, capability)
//   4. creative          (cụm từ specific, check trước complex)
//   5. math_coding       (từ khoá specific)
//   6. complex           (phân tích, tại sao...)
//   7. multi_hop         (so sánh, quan hệ...)
//   8. conversational    (short < 15 ký tự)
//   9. factual           (default)

/// Loại câu hỏi để phân bổ budget động
enum QueryType {
  /// Câu hỏi giao tiếp: "chào", "bạn là ai", "hello", "who are you"
  /// → Nhiều history (45%), ít RAG (15%)
  conversational,

  /// Câu hỏi thông tin: "khi nào", "cách", "là gì", "when", "how", "what"
  /// → Nhiều RAG (58%), ít history (10%)
  factual,

  /// Câu hỏi phức tạp: "phân tích", "tại sao", "explain", "why"
  /// → Cân bằng history (20%) và RAG (45%)
  complex,

  /// Câu hỏi sáng tạo: "viết", "soạn", "write a story", "compose"
  /// → Ít RAG (10%), nhiều history (25%), response lớn (50%)
  creative,

  /// Câu hỏi tóm tắt: "tóm tắt", "summary", "summarize"
  /// → Ít system (2%), nhiều RAG (70%), ít các phần còn lại
  summarization,

  /// Câu hỏi dịch thuật: "dịch", "translate", "chuyển sang tiếng"
  /// → Ít RAG (10%), nhiều history (30%), response lớn (50%)
  translation,

  /// Câu hỏi toán/lập trình: "giải phương trình", "code", "implement"
  /// → Nhiều RAG (50%), ít history (10%), response lớn (30%)
  mathCoding,

  /// Câu hỏi yêu cầu nhiều bước suy luận: "so sánh A và B"
  /// → Nhiều RAG (40%), nhiều history (25%)
  multiHop,
}

/// Cấu hình budget động theo loại câu hỏi.
///
/// Mỗi `ContextBudget` chứa các ratio (tỉ lệ phần trăm dạng double)
/// cho từng thành phần của context window. Tổng các ratio phải = 1.0.
class ContextBudget {
  final QueryType queryType;
  final double systemRatio;
  final double memoryRatio;
  final double historyRatio;
  final double ragRatio;
  final double responseRatio;

  ContextBudget({
    required this.queryType,
    required this.systemRatio,
    required this.memoryRatio,
    required this.historyRatio,
    required this.ragRatio,
    required this.responseRatio,
  }) : assert(
          (systemRatio + memoryRatio + historyRatio + ragRatio + responseRatio - 1.0)
                  .abs() <
              0.01,
          'Budget ratios must sum to 1.0, '
          'got ${systemRatio + memoryRatio + historyRatio + ragRatio + responseRatio}',
        );

  /// Factory: Tạo budget động dựa trên nội dung câu hỏi.
  factory ContextBudget.forQuery(String query) {
    final type = _classifyQuery(query);

    switch (type) {
      case QueryType.conversational:
        return ContextBudget(
          queryType: QueryType.conversational,
          systemRatio: 0.10,  // 10% = 205 tokens
          memoryRatio: 0.05,  // 5%  = 102 tokens
          historyRatio: 0.45, // 45% = 922 tokens
          ragRatio: 0.15,     // 15% = 307 tokens
          responseRatio: 0.25, // 25% = 512 tokens
        );

      case QueryType.factual:
        return ContextBudget(
          queryType: QueryType.factual,
          systemRatio: 0.05,  // 5%  = 102 tokens
          memoryRatio: 0.02,  // 2%  = 41 tokens
          historyRatio: 0.10, // 10% = 205 tokens
          ragRatio: 0.58,     // 58% = 1188 tokens
          responseRatio: 0.25, // 25% = 512 tokens
        );

      case QueryType.complex:
        return ContextBudget(
          queryType: QueryType.complex,
          systemRatio: 0.05,  // 5%  = 102 tokens
          memoryRatio: 0.05,  // 5%  = 102 tokens
          historyRatio: 0.20, // 20% = 410 tokens
          ragRatio: 0.45,     // 45% = 922 tokens
          responseRatio: 0.25, // 25% = 512 tokens
        );

      case QueryType.creative:
        // Sáng tạo: ít RAG, nhiều response
        return ContextBudget(
          queryType: QueryType.creative,
          systemRatio: 0.10,  // 10% = 205 tokens
          memoryRatio: 0.05,  // 5%  = 102 tokens
          historyRatio: 0.25, // 25% = 512 tokens
          ragRatio: 0.10,     // 10% = 205 tokens
          responseRatio: 0.50, // 50% = 1024 tokens
        );

      case QueryType.summarization:
        // Tóm tắt: nhiều RAG để xử lý nội dung đầu vào
        return ContextBudget(
          queryType: QueryType.summarization,
          systemRatio: 0.02,  // 2%  = 41 tokens
          memoryRatio: 0.03,  // 3%  = 61 tokens
          historyRatio: 0.05, // 5%  = 102 tokens
          ragRatio: 0.70,     // 70% = 1434 tokens
          responseRatio: 0.20, // 20% = 410 tokens
        );

      case QueryType.translation:
        // Dịch thuật: cần nhiều history và response, ít RAG
        return ContextBudget(
          queryType: QueryType.translation,
          systemRatio: 0.05,  // 5%  = 102 tokens
          memoryRatio: 0.05,  // 5%  = 102 tokens
          historyRatio: 0.30, // 30% = 614 tokens
          ragRatio: 0.10,     // 10% = 205 tokens
          responseRatio: 0.50, // 50% = 1024 tokens
        );

      case QueryType.mathCoding:
        // Toán/Lập trình: nhiều RAG và response
        return ContextBudget(
          queryType: QueryType.mathCoding,
          systemRatio: 0.05,  // 5%  = 102 tokens
          memoryRatio: 0.05,  // 5%  = 102 tokens
          historyRatio: 0.10, // 10% = 205 tokens
          ragRatio: 0.50,     // 50% = 1024 tokens
          responseRatio: 0.30, // 30% = 614 tokens
        );

      case QueryType.multiHop:
        // Nhiều bước: cần cả RAG và history
        return ContextBudget(
          queryType: QueryType.multiHop,
          systemRatio: 0.05,  // 5%  = 102 tokens
          memoryRatio: 0.05,  // 5%  = 102 tokens
          historyRatio: 0.25, // 25% = 512 tokens
          ragRatio: 0.40,     // 40% = 820 tokens
          responseRatio: 0.25, // 25% = 512 tokens
        );
    }
  }

  /// Phân loại câu hỏi dựa trên nội dung (heuristics, không dùng model).
  /// Hỗ trợ cả tiếng Việt và tiếng Anh.
  ///
  /// Thứ tự ưu tiên:
  ///   1. translation → 2. summarization → 3. conversational (greeting)
  ///   → 4. creative → 5. math_coding → 6. complex (cụm từ trước, từ đơn sau)
  ///   → 7. multi_hop → 8. conversational (short) → 9. factual (default)
  static QueryType _classifyQuery(String query) {
    final q = query.toLowerCase().trim();
    final words = q.split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^\w]'), ''))
        .where((w) => w.isNotEmpty)
        .toList();

    // ─── 1. Translation ───────────────────────────────────────────────
    // Từ khoá rất specific: "dịch sang", "translate to", "chuyển sang tiếng"
    if ((_containsAnyPhrase(q, ['dịch', 'translate']) && 
         _containsAnyPhrase(q, ['sang', 'to', 'into', 'from'])) ||
        q.contains('chuyển sang tiếng')) {
      return QueryType.translation;
    }

    // ─── 2. Summarization ─────────────────────────────────────────────
    // Từ khoá specific: "tóm tắt", "rút gọn", "summary", "summarize"
    if (_containsAnyPhrase(q, [
      'tóm tắt', 'rút gọn', 'summary', 'summarize', 'key points', 'brief',
    ])) {
      return QueryType.summarization;
    }

    // ─── 3. Conversational (greeting / capability) ────────────────────
    if (_isGreeting(q)) {
      return QueryType.conversational;
    }
    if (_containsAnyPhrase(q, [
      'bạn là ai', 'giúp gì', 'what can you do', 'giới thiệu về bạn',
      'who are you', 'tell me about yourself', 'introduce yourself',
    ])) {
      return QueryType.conversational;
    }

    // ─── 4. Creative ──────────────────────────────────────────────────
    // Dùng cụm từ dài, không match từ đơn "hãy" (quá rộng)
    if (_containsAnyPhrase(q, [
      'viết một', 'viết bài', 'soạn thảo', 'hãy kể', 'hãy tưởng tượng',
      'sáng tác', 'write a story', 'write a poem', 'compose a',
      'create a story', 'tell me a story', 'draft a',
    ])) {
      return QueryType.creative;
    }

    // ─── 5. Math / Coding ─────────────────────────────────────────────
    if (_containsAnyPhrase(q, [
      'giải phương trình', 'viết code', 'implement', 'debug this',
      'solve for', 'algorithm', 'calculus', 'equation solver',
    ])) {
      return QueryType.mathCoding;
    }

    // ─── 6. Complex (phân tích sâu) ───────────────────────────────────
    // Bước 1: Kiểm tra cụm từ trước (ưu tiên cao)
    if (_containsAnyPhrase(q, [
      'phân tích', 'tại sao', 'như thế nào', 'explain in detail',
      'analyze the', 'what causes', 'what leads to', 'what is the reason',
      'chi tiết về', 'sâu về', 'ý nghĩa của', 'tác động của',
    ])) {
      return QueryType.complex;
    }
    // Bước 2: Kiểm tra từ đơn (chỉ những từ không gây false positive)
    // Lưu ý: KHÔNG dùng "phân" vì nó xuất hiện trong mọi câu về phân bón
    if (_containsAnyWordOrPhrase(q, words, [
      'tại', 'sao',   // "tại sao"
      'explain', 'analyze', 'why',
      'effect', 'impact', 'implication', 'significance',
    ])) {
      // Kiểm tra thêm để tránh false positive
      if (!_containsAnyPhrase(q, ['tại vườn', 'tại nhà', 'tại sao']) ||
          _containsAnyPhrase(q, ['tại sao'])) {
        // Chỉ "tại sao" mới thực sự là complex, "tại vườn" là factual
        if (q.contains('tại sao') || q.contains('explain') || 
            q.contains('analyze') || q.contains('why')) {
          return QueryType.complex;
        }
      }
    }

    // ─── 7. Multi-Hop / Comparative ───────────────────────────────────
    // Phát hiện câu hỏi so sánh hoặc yêu cầu quan hệ giữa nhiều đối tượng
    final hasCompareKeyword = _containsAnyPhrase(q, [
      'so sánh', 'liên quan', 'mối quan hệ', 'khác nhau giữa',
      'compare', 'relationship between', 'difference between',
      'similarities between',
    ]);
    // Dùng word boundary chặt: \s+(and|và|or|hoặc)\s+
    final hasMultipleSubjects = q.split(RegExp(r',|\s+(and|và|or|hoặc)\s+')).length > 1;
    if (hasCompareKeyword || hasMultipleSubjects) {
      return QueryType.multiHop;
    }

    // ─── 8. Conversational (short < 15 ký tự) ─────────────────────────
    // Check cuối cùng để bắt các câu ngắn không match greeting regex
    if (q.length < 15) return QueryType.conversational;

    // ─── 9. Default: Factual ──────────────────────────────────────────
    return QueryType.factual;
  }

  /// Kiểm tra xem query có phải greeting không (regex nhanh).
  static bool _isGreeting(String q) {
    return RegExp(
      r'^(hi|hello|hey|chào|xin chào|chào bạn|'
      r'good morning|good afternoon|good evening|good night|'
      r'bye|tạm biệt|cảm ơn|thank you|thanks)'
      r'(\s|!|\.|,|)$',
    ).hasMatch(q);
  }

  /// Kiểm tra xem chuỗi [text] có chứa bất kỳ cụm từ nào trong [phrases] không.
  static bool _containsAnyPhrase(String text, List<String> phrases) {
    return phrases.any((phrase) => text.contains(phrase.toLowerCase()));
  }

  /// Kiểm tra xem chuỗi [text] hoặc danh sách [words] có chứa bất kỳ
  /// từ/cụm từ nào trong [items] không.
  ///
  /// - words: danh sách từ đã tách (dùng cho match từ đơn)
  /// - items: có thể là từ đơn hoặc cụm từ nhiều từ
  static bool _containsAnyWordOrPhrase(
    String text,
    List<String> words,
    List<String> items,
  ) {
    // Kiểm tra trên danh sách từ (tốt cho các từ riêng lẻ)
    final wordExists = words.any((word) => items.contains(word));
    // Kiểm tra trên chuỗi đầy đủ (tốt cho cụm từ nhiều từ)
    final phraseExists = _containsAnyPhrase(text, items);
    return wordExists || phraseExists;
  }

  /// Tính budget thực tế dựa trên context window.
  BudgetAllocation calculate(int contextWindow) {
    return BudgetAllocation(
      systemTokens: (contextWindow * systemRatio).round(),
      memoryTokens: (contextWindow * memoryRatio).round(),
      historyTokens: (contextWindow * historyRatio).round(),
      ragTokens: (contextWindow * ragRatio).round(),
      responseTokens: (contextWindow * responseRatio).round(),
    );
  }
}

/// Kết quả phân bổ budget thực tế (theo tokens).
///
/// Được tạo từ `ContextBudget.calculate(contextWindow)`.
/// Tổng các tokens có thể lệch ±1 do làm tròn, nhưng đảm bảo <= contextWindow.
class BudgetAllocation {
  final int systemTokens;
  final int memoryTokens;
  final int historyTokens;
  final int ragTokens;
  final int responseTokens;

  const BudgetAllocation({
    required this.systemTokens,
    required this.memoryTokens,
    required this.historyTokens,
    required this.ragTokens,
    required this.responseTokens,
  });

  /// Tổng số tokens đã phân bổ.
  int get total =>
      systemTokens + memoryTokens + historyTokens + ragTokens + responseTokens;

  @override
  String toString() {
    return 'BudgetAllocation('
        'system=$systemTokens, '
        'memory=$memoryTokens, '
        'history=$historyTokens, '
        'rag=$ragTokens, '
        'response=$responseTokens, '
        'total=$total)';
  }
}