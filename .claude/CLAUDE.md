# OfflineChat - AI Agent Guide

## Mô tả dự án
Ứng dụng Flutter chat AI chạy **100% offline** trên Android & iOS, sử dụng Gemma 4B làm LLM và Gecko 110M làm embedding engine. Hỗ trợ RAG từ PDF/DOCX/TXT, session history, streaming response.

## Cách dùng tài liệu này
1. Đọc file này trước
2. Đọc `architecture.md` để hiểu toàn bộ hệ thống
3. Đọc `database_schema.md` để hiểu data model
4. Đọc `coding_conventions.md` trước khi viết bất kỳ code nào
5. Tham chiếu `api_contracts.md` khi implement service/bloc
6. Xem `tasks.md` để biết việc cần làm tiếp theo

## Tech Stack nhanh
| Layer | Technology |
|-------|-----------|
| Framework | Flutter 3.x |
| State Management | flutter_bloc ^8.x |
| LLM Runtime | flutter_gemma ^0.13.1 |
| Embedding | Gecko 110M (.tflite) via tflite_flutter |
| Database | drift (SQLite) |
| Vector Store | SQLite custom (cosine similarity) |
| File Parsing | syncfusion_flutter_pdf, docx_to_text |

## Nguyên tắc tuyệt đối
- ❌ KHÔNG dùng bất kỳ API cloud nào (OpenAI, Firebase, Supabase...)
- ❌ KHÔNG dùng http package để gọi AI endpoint
- ✅ Tất cả inference chạy on-device
- ✅ Offline-first: app phải hoạt động hoàn toàn khi tắt mạng
- ✅ Mọi state đều đi qua Bloc, không dùng setState ở business logic

## Cấu trúc thư mục bắt buộc
```
lib/
├── core/
│   ├── constants/
│   ├── errors/
│   ├── extensions/
│   └── utils/
├── features/
│   ├── chat/
│   │   ├── bloc/
│   │   ├── models/
│   │   ├── repositories/
│   │   └── views/
│   ├── session/
│   │   ├── bloc/
│   │   ├── models/
│   │   ├── repositories/
│   │   └── views/
│   ├── rag/
│   │   ├── bloc/
│   │   ├── models/
│   │   ├── repositories/
│   │   └── views/
│   ├── knowledge/
│   │   ├── bloc/
│   │   ├── models/
│   │   ├── repositories/
│   │   └── views/
│   └── model_manager/
│       ├── bloc/
│       ├── models/
│       ├── repositories/
│       └── views/
├── services/
│   ├── gemma/
│   ├── gecko/
│   ├── vectorstore/
│   └── parser/
├── database/
│   ├── app_database.dart
│   ├── daos/
│   └── tables/
├── injection/
│   └── service_locator.dart
└── app.dart
```
