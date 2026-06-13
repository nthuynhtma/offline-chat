// ═══════════════════════════════════════════════════════════════════════════════
// DYNAMIC BUDGET ALLOCATION (VERSION=dynamic_budget_v1)
// ═══════════════════════════════════════════════════════════════════════════════
//
// Phân bổ context budget động dựa trên loại câu hỏi.
// Thay vì dùng ratio cố định cho mọi query, phân loại query và điều chỉnh
// phân bổ cho phù hợp:
//   - conversational (chào hỏi): nhiều history, ít RAG
//   - factual (thông tin cụ thể): ít history, nhiều RAG
//   - complex (phân tích sâu): cân bằng
//
// Dùng kèm: kGemmaMaxTokens (=2048) từ model_constants.dart

/// Loại câu hỏi để phân bổ budget động
enum QueryType {
  /// Câu hỏi giao tiếp: "chào", "bạn là ai", câu ngắn < 15 ký tự
  /// → Cần nhiều history (45%), ít RAG (15%)
  conversational,

  /// Câu hỏi thông tin: "khi nào", "cách", "là gì"
  /// → Cần nhiều RAG (58%), ít history (10%)
  factual,

  /// Câu hỏi phức tạp: "phân tích", "tại sao", "như thế nào"
  /// → Cân bằng history (20%) và RAG (45%)
  complex,
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
          'Budget ratios must sum to 1.0',
        );

  /// Factory: Tạo budget động dựa trên nội dung câu hỏi.
  factory ContextBudget.forQuery(String query) {
    final type = _classifyQuery(query);

    switch (type) {
      case QueryType.conversational:
        // Cần nhiều history (45%), ít RAG (15%)
        return ContextBudget(
          queryType: QueryType.conversational,
          systemRatio: 0.10,  // 10% = 205 tokens
          memoryRatio: 0.05,  // 5%  = 102 tokens
          historyRatio: 0.45, // 45% = 922 tokens ← TĂNG
          ragRatio: 0.15,     // 15% = 307 tokens ← GIẢM
          responseRatio: 0.25, // 25% = 512 tokens
        );

      case QueryType.factual:
        // Cần nhiều RAG (58%), ít history (10%)
        return ContextBudget(
          queryType: QueryType.factual,
          systemRatio: 0.05,  // 5%  = 102 tokens
          memoryRatio: 0.02,  // 2%  = 41 tokens
          historyRatio: 0.10, // 10% = 205 tokens ← GIẢM
          ragRatio: 0.58,     // 58% = 1188 tokens ← TĂNG
          responseRatio: 0.25, // 25% = 512 tokens
        );

      case QueryType.complex:
        // Cân bằng history (20%) và RAG (45%)
        return ContextBudget(
          queryType: QueryType.complex,
          systemRatio: 0.05,  // 5%  = 102 tokens
          memoryRatio: 0.05,  // 5%  = 102 tokens
          historyRatio: 0.20, // 20% = 410 tokens
          ragRatio: 0.45,     // 45% = 922 tokens
          responseRatio: 0.25, // 25% = 512 tokens
        );
    }
  }

  /// Phân loại câu hỏi dựa trên nội dung (heuristics, không dùng model).
  static QueryType _classifyQuery(String query) {
    final q = query.toLowerCase().trim();

    // Conversational: câu ngắn, greeting, capability questions
    if (q.length < 15) return QueryType.conversational;
    if (RegExp(r'^(hi|hello|hey|chào|xin chào|chào bạn)(\s|!|\.|)$')
        .hasMatch(q)) {
      return QueryType.conversational;
    }
    if (q.contains('bạn là ai') ||
        q.contains('giúp gì') ||
        q.contains('what can you do') ||
        q.contains('giới thiệu về bạn')) {
      return QueryType.conversational;
    }

    // Complex: phân tích, giải thích sâu
    if (q.contains('phân tích') ||
        q.contains('tại sao') ||
        q.contains('như thế nào') ||
        q.contains('explain') ||
        q.contains('analyze') ||
        q.contains('chi tiết') ||
        q.contains('sâu về')) {
      return QueryType.complex;
    }

    // Factual: hỏi thông tin cụ thể (default)
    return QueryType.factual;
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