# UI/UX Guidelines & Widget Catalog

## Design Tokens

### Colors (`core/constants/app_colors.dart`)
```dart
class AppColors {
  // Light mode
  static const primaryLight    = Color(0xFF1A73E8);
  static const surfaceLight    = Color(0xFFFFFFFF);
  static const backgroundLight = Color(0xFFF8F9FA);
  static const onSurfaceLight  = Color(0xFF202124);
  static const subtleLight     = Color(0xFF5F6368);

  // User bubble
  static const userBubble      = Color(0xFF1A73E8);
  static const userBubbleText  = Color(0xFFFFFFFF);

  // Assistant bubble
  static const assistantBubble = Color(0xFFF1F3F4);
  static const assistantBubbleText = Color(0xFF202124);

  // Status
  static const success = Color(0xFF34A853);
  static const warning = Color(0xFFFBBC04);
  static const error   = Color(0xFFEA4335);
}
```

### Spacing (`core/constants/app_spacing.dart`)
```dart
class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}
```

---

## Widget Catalog (Refactored 11/06/2026)

### ChatPage Structure
```
ChatPage (167 dòng, lib/features/chat/views/chat_page.dart)
  └── ChatView (StatefulWidget)
       ├── AppBar
       │    ├── ScopeSelector (PopupMenuButton, KnowledgeScope)
       │    └── ClearButton (BlocBuilder riêng, buildWhen: streaming/thinking state change)
       └── Column
            ├── ModelNotInstalledBanner (lib/features/chat/widgets/)
            ├── ChatBody (BlocBuilder, buildWhen: trừ ChatThinking→ChatThinking)
            │    └── MessageList (StatefulWidget, ScrollController + ListViewObserver)
            │         ├── MessageBubble (user: right-aligned blue, assistant: left-aligned gray)
            │         └── LastBubble (BlocBuilder riêng, buildWhen: streamingText change)
            │              ├── ChatThinking → ThinkingBubble (3 chấm animation)
            │              └── ChatStreaming → MessageBubble(isStreaming: true)
            ├── AttachedFilesBar (StatefulWidget, BlocBuilder<SessionFilesCubit>)
            │    └── FileChip (icon trạng thái + tên + progress % + popup menu)
            └── ChatInputBar (BlocListener → setState local _isStreaming)
```

### MessageBubble
```dart
// lib/features/chat/views/message_bubble.dart
// User: right-aligned, blue background (#1A73E8), white text
// Assistant: left-aligned, gray background (#F1F3F4), dark text (#202124)
// AI messages rendered with MarkdownBody (flutter_markdown_plus)
// Streaming messages show cursor-like animation

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isLast;      // true nếu là message mới nhất
  final bool isStreaming; // true khi đang stream
  // MarkdownBody cho assistant, plain Text cho user
}
```

### ThinkingBubble (3 chấm animation)
```dart
// lib/features/chat/widgets/thinking_bubble.dart
// Hiển thị 3 dots animation khi model đang xử lý
// Chỉ emit trước khi token đầu tiên xuất hiện
```

### ChatInputBar
```dart
// lib/features/chat/widgets/chat_input_bar.dart
// Text field + send button
// Disabled khi: model chưa load, đang streaming, Gecko chưa ready
// 📎 button: disabled khi Gecko chưa ready (tooltip: "Preparing AI models...")
// Multiline support, max 5 dòng
// Auto-focus khi vào chat page
```

### AttachedFilesBar
```dart
// lib/features/chat/widgets/attached_files_bar.dart
// StatefulWidget, BlocBuilder<SessionFilesCubit>
// Hiển thị file chips đã upload trong session
// FileChip: icon + tên + progress bar (nếu đang indexing) + popup menu (Retry/Remove)
```

### ClearButton
```dart
// lib/features/chat/widgets/clear_button.dart
// BlocBuilder riêng, buildWhen: chỉ rebuild khi streaming/thinking state thay đổi
// Tránh rebuild toàn bộ AppBar khi streaming
```

### ScopeSelector
```dart
// lib/features/chat/widgets/scope_selector.dart
// PopupMenuButton, chọn KnowledgeScope
// attachedOnly / globalOnly / attachedAndGlobal
// ScopeOption: icon + tên cho mỗi option
```

### ScrollToBottomButton
```dart
// lib/features/chat/widgets/scroll_to_bottom_button.dart
// AnimatedOpacity + AnimatedSlide
// "Mới nhất" button, xuất hiện khi người dùng scroll lên
// Auto-scroll khi _isNearBottom (phát hiện qua ListViewObserver)
```

---

## Screen Layouts

### SessionListPage (`/`)
```
AppBar: "Offline Chat"  [Settings icon]
Body:
  FloatingActionButton: "+ New Chat"
  ListView: SessionCard(session)
  Empty state: icon + "Chưa có cuộc trò chuyện" + "Bắt đầu chat" button
```

### ChatPage (`/chat/:sessionId`)
```
AppBar: [Back] [Session title] [ScopeSelector]
Body:
  [ModelNotInstalledBanner - nếu model chưa tải]
  Column
    Expanded: MessageList
      - MessageBubble(user)
      - MessageBubble(assistant)
      - LastBubble (streaming/thinking)
    [AttachedFilesBar - nếu có file đang upload]
    ChatInputBar
```

### KnowledgePage (`/knowledge`)
```
AppBar: [Back] "Knowledge Base"
Body:
  "Import tài liệu" button
  [IndexingProgressBar - nếu đang index]
  ListView: DocumentCard
  Empty state: icon + "Chưa có tài liệu" + "Import PDF/DOCX/TXT" button
```

### SessionFilesPanel (Bottom Sheet)
```
// lib/features/knowledge/views/session_files_panel.dart
// Bottom sheet từ ChatPage 📎
// List file đã upload trong session
// FileChip: icon + tên + progress bar + status label
// [Pending] [Processing 45%] [Completed ✅] [Failed ❌]
// Retry button nếu failed
```

### ModelManagerPage (`/settings/models`)
```
AppBar: [Back] "Quản lý Model"
Body:
  Section "Language Model":
    ModelStatusCard(Gemma 4-E2B IT) — 2.6 GB
    [Download / Progress / ✅ Ready]
  Section "Embedding Model":
    ModelStatusCard(Gecko 256 quant) — 111 MB
    [Download / Progress / ✅ Ready]
  Note: "Models được lưu trên thiết bị"
```

---

## Navigation

### Routes (go_router)
```dart
/              → SessionListPage
/chat/:id      → ChatPage(sessionId)
/knowledge     → KnowledgePage
/settings      → SettingsPage
/settings/models → ModelManagerPage
```

### Architecture
```dart
// app.dart - StatefulWidget
// GoRouter(navigatorKey: _navigatorKey)
// MaterialApp.router(builder: (context, child) => ModelOnboardingCoordinator(...))
// MultiBlocProvider app level: ModelBloc, SessionBloc, KnowledgeBloc, SessionFilesCubit
```

---

## UX Rules

1. **Loading states**: Mọi async action đều có loading indicator
2. **Error feedback**: Mọi error đều show snackbar/banner, không silent fail
3. **Empty states**: Mọi list đều có empty state + hướng dẫn hành động
4. **Streaming feel**: ThinkingBubble (3 chấm) → streaming text (từng token)
5. **Rebuild optimization**: Tách LastBubble + ChatBody riêng (buildWhen), tránh rebuild toàn bộ
6. **Keyboard**: `resizeToAvoidBottomInset: true` trên ChatPage
7. **Model onboarding**: Dialog lần đầu → progress bars (Gemma + Gecko song song) → SnackBar