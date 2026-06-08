# UI/UX Guidelines & Widget Catalog

## Design System

### Colors
```dart
// core/constants/app_colors.dart
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

### Typography
```dart
// Dùng system font (San Francisco trên iOS, Roboto trên Android)
const TextStyle bodyText = TextStyle(fontSize: 16, height: 1.5);
const TextStyle caption  = TextStyle(fontSize: 13, color: AppColors.subtleLight);
const TextStyle heading  = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
```

### Spacing
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

## Widgets Catalog

### MessageBubble
```dart
// Hiển thị message của user hoặc assistant
// User: bubble bên phải, màu xanh
// Assistant: bubble bên trái, màu xám nhạt

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isStreaming; // true khi đang stream

  // Layout:
  // [Avatar] [BubbleContent] [Timestamp]  ← assistant
  //          [Timestamp] [BubbleContent]  ← user (right aligned)
}
```

### StreamingIndicator
```dart
// 3 chấm nhảy khi model đang xử lý
// Hiển thị trước khi token đầu tiên xuất hiện
class StreamingIndicator extends StatefulWidget {
  // Animated dots: ● ● ●
}
```

### ChatInputBar
```dart
// Text field + send button
// Disabled khi: model chưa load, đang streaming
// Multiline support
// Send on Enter (configurable)
class ChatInputBar extends StatefulWidget {
  final VoidCallback? onSend;
  final bool enabled;
  // Height: tự expand, max 5 dòng
}
```

### SessionCard
```dart
// Hiển thị 1 session trong list
// Title (hoặc "New Chat" nếu không có)
// Last message preview (1 dòng)
// Timestamp
// Swipe to delete
class SessionCard extends StatelessWidget {
  final SessionModel session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;
}
```

### DocumentCard
```dart
// Hiển thị 1 document trong knowledge base
// Icon theo loại file (PDF/DOCX/TXT)
// Name + size
// Chunk count + status (indexed/indexing/error)
// Delete button
class DocumentCard extends StatelessWidget {
  final DocumentModel document;
  final VoidCallback onDelete;
  final VoidCallback onReindex;
}
```

### ModelStatusCard
```dart
// Hiển thị trạng thái Gemma và Gecko
// Status: Not Downloaded | Downloading (%) | Ready
// Download button nếu chưa có
// Version info nếu đã có
class ModelStatusCard extends StatelessWidget {
  final String modelName;    // "Gemma 4B" hoặc "Gecko 110M"
  final ModelStatus status;
  final double? downloadProgress; // null nếu không download
  final VoidCallback? onDownload;
}
```

### IndexingProgressBar
```dart
// Linear progress bar khi indexing document
// Hiển thị: "Đang xử lý... 45/120 chunks"
class IndexingProgressBar extends StatelessWidget {
  final String documentName;
  final double progress; // 0.0 - 1.0
  final int currentChunk;
  final int totalChunks;
}
```

---

## Screen Layouts

### SessionListPage
```
AppBar: "Offline Chat"  [Settings icon]
Body:
  FAB hoặc Button: "+ New Chat"
  ListView:
    SessionCard(session1)  [active - highlighted]
    SessionCard(session2)
    ...
  Empty state nếu không có session:
    Icon (chat bubble)
    "Chưa có cuộc trò chuyện"
    Button: "Bắt đầu chat"
```

### ChatPage
```
AppBar: [Back] [Session title - editable] [Knowledge icon]
Body:
  [ModelNotReadyBanner - nếu model chưa load]
  Expanded: MessageList
    MessageBubble (user)
    MessageBubble (assistant)
    StreamingMessageBubble (khi đang stream)
  ChatInputBar
```

### KnowledgePage
```
AppBar: [Back] "Knowledge Base"
Body:
  Button: "Import tài liệu"
  [IndexingProgressBar - nếu đang index]
  ListView:
    DocumentCard(doc1)
    DocumentCard(doc2)
    ...
  Empty state nếu không có document:
    Icon (document)
    "Chưa có tài liệu nào"
    Button: "Import PDF/DOCX/TXT"
```

### ModelManagerPage
```
AppBar: [Back] "Quản lý Model"
Body:
  Section "Language Model":
    ModelStatusCard(Gemma 4B IT)
    Size: 2.8 GB
    [Download button / Progress / ✅ Ready]

  Section "Embedding Model":
    ModelStatusCard(Gecko 110M)
    Size: 440 MB
    [Download button / Progress / ✅ Ready]

  Note: "Models được lưu trên thiết bị và không bao giờ được gửi lên server"
```

---

## Navigation Structure

```
/ (SessionListPage)
├── /chat/:sessionId  (ChatPage)
│   └── /knowledge    (KnowledgePage - bottom sheet hoặc page)
└── /settings         (SettingsPage)
    └── /models        (ModelManagerPage)
```

Dùng `go_router`:
```yaml
dependencies:
  go_router: ^14.x
```

---

## UX Rules

1. **Loading states**: Mọi async action đều cần loading indicator
2. **Error feedback**: Mọi error đều show snackbar hoặc banner, không bao giờ silent fail
3. **Empty states**: Mọi list đều có empty state với hướng dẫn hành động
4. **Streaming feel**: Cursor nhấp nháy khi đang stream (như terminal)
5. **Haptic feedback**: Khi send message thành công
6. **Swipe actions**: Swipe left để delete session/document
7. **Pull to refresh**: Không cần (data local, realtime qua Streams)
8. **Keyboard behavior**: `resizeToAvoidBottomInset: true` trên ChatPage
