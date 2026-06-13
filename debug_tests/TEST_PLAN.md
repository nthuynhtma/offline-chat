# Test Plan: Bug "Laptop Response"

## Mục tiêu
Xác định nguyên nhân gốc của bug: model trả về 1 token vô nghĩa (`-` hoặc `Laptop`) khi prompt có RAG chunks.

## Cách ghi log

Trước khi test, đảm bảo terminal hoặc `adb logcat` / Xcode console đang capture.

### Android:
```bash
# Filter log của app
adb logcat -s flutter:I "*:S" > test_log.txt
# Hoặc capture tất cả:
adb logcat > test_log_full.txt
```

### iOS:
Xcode → Run → Console sẽ hiển thị log tự động.

---

## Test 1: Fresh Session + RAG (Kiểm tra Prompt/Session interaction)

**Mục đích:** Loại trừ session corruption. Nếu lỗi xuất hiện ngay từ turn đầu có RAG → nghi ngờ PromptBuilder hoặc Session API misuse.

**Steps:**
1. Force stop app (swipe khỏi recent apps)
2. Mở lại app
3. Nếu có onboarding/download model → chờ hoàn tất
4. Upload document (ví dụ file sầu riêng đã dùng trước đó)
5. **Chờ** document indexing hoàn tất (log `Completed: ... (N chunks, N vectors)`)
6. Vào session chat
7. Gửi ngay: `khi nào thu hoạch sầu riêng`

**Log cần ghi lại (copy-paste ra file):**
- Dòng `[RAG] VERSION=try_fit_v2` và các dòng candidate score xung quanh
- Dòng `[RAG] packing matched=N packed=N`
- Dòng `🔍 [RAG] Tìm thấy N chunks liên quan`
- Dòng `[Gemma] generateWithSession: sessionActive=... promptLength=...`
- Dòng `[Gemma] prompt tail:` (500 chars cuối)
- Dòng `[Gemma] token[1]=...` đến `token[20]=...`
- Dòng `[Gemma] generateWithSession hoàn tất: N tokens`
- Dòng `[Gemma] response preview: ...`
- Dòng `[FfiInferenceModelSession/perf]` (TTFT + total time)

---

## Test 2: Long History + No RAG (Kiểm tra context accumulation)

**Mục đích:** Nếu lỗi xuất hiện với history dài không RAG → RAG vô tội, nguyên nhân là context accumulation.

**Steps:**
1. Force stop app
2. Mở lại app
3. Vào session chat
4. Gửi tuần tự **10-12 câu**, đợi mỗi câu trả lời xong mới gửi câu tiếp:

```
Q1: chào
Q2: bạn là ai
Q3: sầu riêng là gì
Q4: kể tên các giống sầu riêng phổ biến
Q5: monthong khác ri6 thế nào
Q6: đất trồng sầu riêng cần loại đất gì
Q7: cách chăm sóc sầu riêng con
Q8: tưới nước cho sầu riêng thế nào
Q9: sầu riêng bị vàng lá là bệnh gì
Q10: cách phòng trừ nấm trên sầu riêng
Q11: bón phân gì cho sầu riêng ra hoa
Q12: phân biệt monthong và ri6
```

**Lưu ý:** Không upload document nào trước khi test.

**Log cần ghi lại:**
- Các dòng `📊 Context Budget: history=N response=512 system=205 question=M rag=P`
- Dòng `🔍 [RAG] Tìm thấy 0 chunks liên quan` (phải xuất hiện vì không có doc)
- Dòng `[Gemma] generateWithSession hoàn tất: N tokens` cho mỗi turn
- Dòng `[FfiInferenceModelSession/perf]` cho turn cuối cùng (Q11-Q12)
- Nếu có turn nào ra `-` hoặc `Laptop` → ghi lại toàn bộ log turn đó

**Expected:** Tất cả các turn phải trả lời bình thường (>50 tokens). Nếu turn cuối vẫn OK → context accumulation đến ~12 turns không gây lỗi.

---

## Test 3: Fresh Session + 3 RAG Queries Liên Tiếp (Phân biệt Prompt vs Session accumulation)

**Mục đích:** Quan trọng nhất. Nếu Q1 chết → Prompt/Session interaction. Nếu Q1 OK, Q2-Q3 chết dần → Session accumulation.

**Steps:**
1. Force stop app
2. Mở lại app
3. Upload document (cùng file sầu riêng)
4. Chờ indexing hoàn tất
5. Vào session chat
6. Gửi tuần tự, đợi mỗi câu trả lời xong:

```
Q1: khi nào thu hoạch sầu riêng       (RAG: thu hoạch)
Q2: cách thu hoạch sầu riêng           (RAG: thu hoạch)
Q3: bón phân sau thu hoạch thế nào     (RAG: bón phân + thu hoạch)
```

**Log cần ghi lại CHO MỖI TURN:**
- `📊 Context Budget: history=N ...`
- `[RAG] VERSION=try_fit_v2`
- `[RAG] packing matched=N packed=N tokens=N`
- `🔍 [RAG] Tìm thấy N chunks liên quan`
- `[Gemma] generateWithSession: sessionActive=...`
- `[Gemma] sessionHash=...` (quan sát hash có thay đổi không)
- `[Gemma] token[1]=...` đến `token[20]=...`
- `[Gemma] generateWithSession hoàn tất: N tokens`
- `[FfiInferenceModelSession/perf]`

**Kết quả dự kiến:**
| Kịch bản | Q1 | Q2 | Q3 | Kết luận |
|---------|-----|-----|-----|---------|
| A | OK (193 tok) | OK (174 tok) | OK | Không tái hiện bug |
| B | - | - | - | Prompt/Session API là root cause |
| C | OK | - | - | Session accumulation sau 1 RAG turn |
| D | OK | OK | - | Session accumulation sau 2 RAG turns |

---

## Hướng dẫn gửi kết quả

Sau khi chạy xong, gửi cho em:
1. File log (.txt) — ưu tiên đã filter chỉ giữ các dòng `I/flutter` hoặc `💡` / `🐛`
2. Hoặc copy-paste các dòng log quan trọng (em đã đánh dấu ở từng test)
3. Ghi chú: có kết quả nào bất thường không (ví dụ app crash, freeze, ...)