# TaxBridge — Implementation Plan Flutter (PoC)

_Flutter · Material 3 · Riverpod 3 · go_router · Dio_

Mục tiêu: app demo chạy 9 UC ở `CLAUDE.md` §9 trên iPhone thật. App chỉ gọi REST;
contract ở `contract/` (không lặp ở đây); phạm vi làm / không làm ở `CLAUDE.md` §4.

## 1. Packages

```yaml
dependencies:
  flutter_riverpod: ^3.4.3
  go_router: ^18.0.1
  dio: ^5.11.1
  image_picker: ^1.2.3
  record: ^7.1.1
  shared_preferences: ^2.5.5
  intl: ^0.20.3
  audioplayers: ^6.8.1        # nút "Nghe lại" bằng chứng voice (pub.dev 6.8.1, kiểm tra 11/09/2026)
```

Sau `flutter create` chạy `flutter pub upgrade --major-versions`, commit `pubspec.lock`.
Không FlutterFire.

- **Riverpod 3**: chỉ `Provider`, `FutureProvider`, `Notifier`/`AsyncNotifier`; không
  `StateProvider` / `StateNotifierProvider` / `ChangeNotifierProvider` (đã sang `legacy.dart`).
- **record 7**: `AudioRecorder().start(RecordConfig(encoder: AudioEncoder.aacLc), path: ...m4a)`;
  `hasPermission()` trước khi record; auto-stop 60 s.
- **image_picker**: `imageQuality: 70, maxWidth: 1600`; cho phép gallery để dùng ảnh chuẩn bị sẵn.
- **audioplayers 6**: `AudioPlayer().play(UrlSource(url))`; `asset://demo/x.m4a` →
  `AssetSource('demo/x.m4a')`; `dispose()` khi rời màn. Không cần key `Info.plist` để phát.
- iOS: 3 key `Info.plist` (Camera, Microphone, PhotoLibrary); ngrok / Functions là HTTPS nên
  không cần ATS exception; Simulator gọi `http://localhost:8787` — nếu ATS chặn thì thêm
  `NSAllowsLocalNetworking` (chỉ debug). Signing / máy demo: checklist §2.

## 2. Structure

```text
lib/
├── main.dart                    # ProviderScope, load session, ping /api/health,
│                                # SemanticsBinding.instance.ensureSemantics() để tool Simulator đọc được nhãn (feature-map)
├── app.dart                     # MaterialApp.router
├── core/
│   ├── config.dart              # apiBaseUrl, useMock, demoMode từ --dart-define
│   ├── api_client.dart          # Dio + interceptor
│   ├── session_store.dart       # shared_preferences
│   ├── taxbridge_api.dart       # abstract + apiProvider
│   ├── dio_taxbridge_api.dart
│   ├── fake_taxbridge_api.dart  # đọc assets/fixtures, state in-memory
│   ├── router.dart
│   ├── format.dart              # vnd(), dateKey()
│   └── evidence_block.dart      # EvidenceBlock + evidenceImage() + dialog phóng to (§6 Bằng chứng)
├── models/                      # fromJson viết tay
│   session.dart  zalo_user.dart  capture_result.dart  business_event.dart
│   money_movement.dart  dashboard.dart  daily_record.dart
└── features/
    ├── auth/        login_screen.dart  register_screen.dart  session_notifier.dart
    ├── home/        home_screen.dart
    ├── capture/     capture_screen.dart  capture_controller.dart
    ├── events/      event_list_screen.dart  event_detail_screen.dart
    ├── movements/   movement_list_screen.dart  movement_detail_screen.dart
    └── close_day/   close_day_screen.dart  daily_history_screen.dart  daily_record_detail_screen.dart
assets/fixtures/   # copy từ contract/fixtures bằng tool/sync_fixtures.sh — không sửa tay
assets/demo/       # sale_voice.m4a, receipt.jpg, transfer_match.jpg, transfer_deposit.jpg
```

## 3. Config, session, API client

`--dart-define`: `API_BASE_URL` là origin, app tự nối `/api/...` phía sau. Local
`http://127.0.0.1:8787` (Simulator), ngrok `https://<static>.ngrok-free.app`; prod kết thúc
bằng **tên function** `/api`: `https://asia-southeast1-hackathon-42790.cloudfunctions.net/api`
(trên wire thành `/api/api/health`, xem `CLAUDE.md` §8). `USE_MOCK`, `DEMO`.
`.vscode/launch.json` 4 config `mock` / `local` / `ngrok` / `prod`, đều `DEMO=true`.

Session (`AppSession`) lưu `token, accountId, businessId, username` trong
`shared_preferences`; `accountId/businessId` chỉ để hiển thị, không gửi lên.

```dart
class ApiClient {
  ApiClient({required this.sessionStore, required this.onUnauthorized})
      : dio = Dio(BaseOptions(
          baseUrl: apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 90),   // capture sync có thể 20 s
        )) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) async {
        final s = await sessionStore.load();
        if (s != null) o.headers['X-Session-Token'] = s.token; // không Bearer: Cloud Run chặn
        h.next(o);
      },
      onError: (e, h) async {
        if (e.response?.statusCode == 401) {
          await sessionStore.clear();
          onUnauthorized();                              // SessionNotifier.signOut → redirect /login
        }
        h.next(e);
      },
    ));
  }
  final Dio dio;
  final SessionStore sessionStore;
  final void Function() onUnauthorized;
}
```

```dart
abstract class TaxBridgeApi {
  Future<List<ZaloUser>> unlinkedZaloUsers();
  Future<AppSession> register(String username, String password, String? zaloId);
  Future<AppSession> login(String username, String password);
  Future<void> logout();
  Future<CaptureResult> captureText(String text);
  Future<CaptureResult> captureFile(String type, String path);   // AUDIO | IMAGE_RECEIPT | IMAGE_TRANSFER
  Future<List<BusinessEvent>> events({String? status});
  Future<BusinessEvent> event(String id);
  Future<BusinessEvent> updateEvent(String id, Map<String, dynamic> patch);
  Future<BusinessEvent> confirmEvent(String id);
  Future<BusinessEvent> rejectEvent(String id);
  Future<List<MoneyMovement>> movements({String? status});
  Future<MoneyMovement> movement(String id);
  Future<MoneyMovement> matchMovement(String id, String eventId);
  Future<MoneyMovement> classifyMovement(String id, String type);
  Future<Dashboard> dashboard(String date);
  Future<DailyRecord> closeDay(String date);
  Future<List<DailyRecord>> dailyRecords();
  Future<DailyRecord> dailyRecord(String date);
}

final apiProvider = Provider<TaxBridgeApi>((ref) =>
    useMock ? FakeTaxBridgeApi() : DioTaxBridgeApi(ref.watch(apiClientProvider)));
```

`FakeTaxBridgeApi`: đọc `assets/fixtures/*.json`, delay 800 ms, state in-memory tối
thiểu (confirm đổi status + cộng dashboard, classify giảm `unmatchedMoneyCount`, mỗi capture
tạo event/movement mới id `*_mock_N`; transfer chọn fixture theo tên file demo chứa `deposit`;
xử lý warning → `RESOLVED` + recompute `summary` của record hôm nay).

Thực tế khi code (11/09): interface thêm `health()`; thêm `eventProvider` (family theo id) và
helper `invalidateAll(ref)` trong `core/providers.dart` (invalidate dashboard/events/movements/
dailyHistory/dailyRecord một lần); temp file dùng `Directory.systemTemp` (không thêm
`path_provider`); `SemanticsBinding` import từ `package:flutter/semantics.dart`;
`RadioListTile` bọc trong `RadioGroup` (Flutter 3.47 deprecate `groupValue`).

Multipart:

```dart
final form = FormData.fromMap({'type': type, 'file': await MultipartFile.fromFile(path)});
final r = await dio.post('/api/captures', data: form);
```

`CaptureResult.status == FAILED` (HTTP 200) → SnackBar "Không xử lý được. Thử lại.", ở lại
màn. `DONE` → `EVENT` → `/events/{resultId}`; `MONEY_MOVEMENT` → `/movements/{resultId}`.

## 4. Models

Field = key trong fixture cùng tên; `fromJson` viết tay. Kiểu: tiền `int`;
`confidence` / `score` `double`; `*At` `DateTime?` (parse ISO); enum giữ `String`;
optional `String?`.

| Model | Field |
|---|---|
| `AppSession` | `token, accountId, businessId, username, zaloId?` |
| `ZaloUser` | `zaloId, displayName?, lastSeenAt?` |
| `CaptureResult` | `captureId, status, resultType?, resultId?, error?` |
| `BusinessEvent` | `eventId, type, status, amount, description?, counterparty?, paymentMethod?, paymentStatus?, occurredAt?, source, captureType, evidenceText?, evidenceUrl?, confidence?` |
| `MoneyMovement` | `movementId, direction, amount, memo?, counterparty?, occurredAt?, source, captureType, evidenceText?, evidenceUrl?, status, matchedEventId?, classificationType?, candidates: List<MatchCandidate>` |
| `MatchCandidate` | `eventId, description, amount, score` |
| `Dashboard` | `date, revenue, expense, collected, receivable, bankIn, draftCount, unmatchedMoneyCount` |
| `DailyRecord` | `date, summary: DailySummary(revenue, expense, collected, receivable), warningCount, warnings: List<DailyWarning>, closedAt, updatedAt` |
| `DailyWarning` | `warningId, type, status, resourceType, resourceId, amount?, message, resolvedAt?` |

## 5. Routes

```text
/login  /register  /home  /capture?mode=text|voice|receipt|transfer
/events  /events/:id  /movements  /movements/:id
/close-day  /daily-history  /daily-history/:date
```

`redirect`: `sessionProvider == null` → `/login`; có session mà đang ở `/login` |
`/register` → `/home`. App start: load session từ store → set provider; ping
`/api/health` (bỏ qua lỗi).

## 6. Màn hình

Nhãn nút / ô nhập / chip trong mục này là **handle ổn định** — bảng `Handles` trong
`feature-map/<feature>.md` là nơi sở hữu; đổi nhãn = sửa feature-map trước rồi sửa đây.
Widget dùng đúng text đó (Flutter tự đưa text của `TextButton`/`TextField.decoration.labelText`
vào semantics), không thêm `Semantics` riêng.

### Login / Register

- Login: username, password, nút **Đăng nhập**, link **Tạo tài khoản**. Thành công → lưu
  session → `/home`.
- Register: username, password, confirm password, dropdown **Zalo account (optional)** từ
  `GET /api/zalo-users/unlinked` (item đầu "Không liên kết Zalo"; hiển thị `displayName - zaloId`).
  `POST /api/register` kèm `zaloId?` → `201` → lưu session → `/home`.
- Logout (Home): `POST /api/logout` bỏ qua lỗi → clear → `/login`.

### Home — hero hiện ở đây

```text
┌──────────────────────────────────────────────┐
│ TaxBridge                           [Logout] │
│ Xin chào, tuan                               │
├──────────────────────────────────────────────┤
│ Doanh thu           Tiền đã thu              │
│ 4.820.000đ          4.570.000đ               │
│ Còn phải thu        Chi phí                  │
│   250.000đ          1.230.000đ               │
├──────────────────────────────────────────────┤
│ 🏦 Tiền vào ngân hàng            4.950.000đ  │
│ Thuế khoán ước tính (1,5% DT)       72.300đ  │
├──────────────────────────────────────────────┤
│ [ ✍️ Nhập giao dịch ]  [ 🎤 Nói giao dịch ]   │
│ [ 📷 Chụp chứng từ ]   [ 💸 Chụp chuyển khoản ] │
├──────────────────────────────────────────────┤
│ [ Giao dịch ① ] [ Tiền vào ② ]               │
│ [ Đóng ngày   ] [ Lịch sử ngày ]             │
└──────────────────────────────────────────────┘
```

- `GET /api/dashboard?date=hôm nay`. 4 card = `revenue, collected, receivable, expense`;
  dòng riêng **Tiền vào ngân hàng** = `bankIn` để mắt so được với Doanh thu.
- Badge: Giao dịch = `draftCount`, Tiền vào = `unmatchedMoneyCount`; ẩn khi 0.
- Refresh khi vào màn, sau mọi mutation (`ref.invalidate(dashboardProvider)`), pull-to-refresh.

Wow (Phase 6b, thứ tự 1→2→3; cắt nếu trễ):

1. **Thuế khoán ước tính** — dòng nhỏ dưới `Tiền vào ngân hàng`: `estTax(revenue)` =
   `round(revenue × 0.015)` (GTGT 1% + TNCN 0,5%, hộ bán lẻ; PoC bỏ qua ngưỡng miễn thuế).
   Tính ở client, không thêm field API. Ý nghĩa hero: cọc 380k vào ngân hàng nhưng thuế không đổi.
2. **Delta banner + số nhảy** — về Home sau mutation, so `Dashboard` mới với
   `prevDashboardProvider` (§7): `Card` đầu ListView, tự ẩn sau 4 s, text là các field đổi
   nối bằng ` · `, ví dụ `Tiền vào +380.000đ · Doanh thu không đổi ✓` (sau classify
   DEPOSIT/OWNER_MONEY luôn kèm "Doanh thu không đổi ✓"; sau confirm SALE:
   `Doanh thu +450.000đ · Còn phải thu +450.000đ`). Số trên card chạy
   `TweenAnimationBuilder<int>` 600 ms từ giá trị cũ → mới.
3. **Auto-refresh** — `Timer.periodic(8 s)` trong `HomeScreen` (ConsumerStatefulWidget) →
   `ref.invalidate(dashboardProvider)`; hủy ở `dispose`. Riverpod 3 `when` mặc định
   `skipLoadingOnRefresh` nên không nháy spinner. Mục đích: UC9 nhắn Zalo từ máy 2 → badge
   tự nhảy, không cần kéo refresh.

### Capture — một màn, 4 mode

| Mode | Input | `type` gửi | Sau `DONE` |
|---|---|---|---|
| text | TextField + Gửi | `TEXT` (JSON) | Event Detail |
| voice | Tap bắt đầu / tap dừng (`record`, ≤ 60 s) → tự upload | `AUDIO` | Event Detail |
| receipt | `image_picker` camera/gallery → preview → Gửi | `IMAGE_RECEIPT` | Event Detail |
| transfer | như receipt | `IMAGE_TRANSFER` | Movement Detail |

Trong lúc chờ: overlay "Đang đọc…" (capture sync, 5–20 s). `DEMO=true` → nút **Dùng file
demo** chọn file trong `assets/demo/` thay camera/mic (copy sang temp rồi upload).

### Event Detail

```text
│ Trạng thái: DRAFT · AI 93% · 💬 Zalo │   chip, giá trị DRAFT | CONFIRMED | REJECTED; chip nguồn (4)
│ Bằng chứng  “Bán 3 hộp collagen 450 nghìn chuyển khoản” │   EvidenceBlock (5): text / transcript + Nghe lại / ảnh
│ Loại        [SALE             ▼] │   SALE | PURCHASE | DEPOSIT | OWNER_MONEY | UNKNOWN
│ Số tiền     [450000            ] │
│ Nội dung    [Bán 3 hộp collagen] │
│ Khách       [chị Lan           ] │
│ Thanh toán  [BANK             ▼] │   CASH | BANK | UNKNOWN
│ Thu tiền    [UNPAID           ▼] │   UNPAID | PAID | UNKNOWN  (paymentStatus; nhãn không trùng chip Trạng thái)
│ [Từ chối]            [Xác nhận]  │
```

- Chỉ sửa được khi `DRAFT`; có thay đổi → `PUT` (partial) rồi `confirm`.
- Sau confirm/reject: invalidate `dashboardProvider`, `eventsProvider`, `dailyHistoryProvider`;
  `context.go('/home')` để thấy số đổi ngay (đến từ capture hay từ Events list đều về Home).

### Events list

`GET /api/events[?status]`; tab Tất cả / Nháp / Đã xác nhận (optional). Card: loại, số
tiền, khách, thanh toán, status, chip nguồn.

4. **Chip nguồn** (Phase 6b, cần BE trả `source` + `captureType`): `sourceChip(source,
   captureType)` → `source == ZALO` → `💬 Zalo`; else `AUDIO` → `🎤 Voice`, `IMAGE_*` → `📷 Ảnh`,
   `TEXT` → không hiện. Dùng ở card Events / Movements list và hàng chip của Event /
   Movement Detail. Fixture `events.json[ev_005]` là `ZALO` để mock có 1 thẻ.

### Movement Detail — hero

```text
│ 450.000đ · NGUYEN THI LAN · LAN 3HOP  📷 Ảnh  │   chip nguồn (4)
│ Bằng chứng  [ảnh CK thu nhỏ, cao 160]  chạm → phóng to │   EvidenceBlock (5) — hero: thấy app đọc từ ảnh nào
├───────────────────────────────────────────────┤
│ Có thể là thanh toán cho:                     │   ẩn khối khi candidates = []
│ ○ Bán 3 hộp collagen - 450.000đ · chị Lan     │
│ [ Ghép với giao dịch ]                        │
├───────────────────────────────────────────────┤
│ Hoặc phân loại:                               │   không candidate: "380.000đ từ Minh chưa rõ là khoản gì."
│ [Đặt cọc] [Tiền cá nhân] [Khác] [Không rõ]    │   DEPOSIT | OWNER_MONEY | OTHER | UNKNOWN
```

- `match {eventId}` / `classify {type}` → trả `MoneyMovement` mới.
- Sau thành công: invalidate `dashboardProvider`, `moneyMovementsProvider`,
  `dailyHistoryProvider` → **`context.go('/home')`** để người xem thấy số đổi ngay
  (`pop` từ luồng capture sẽ quay về màn Capture, không phải Home).
  SnackBar sau classify DEPOSIT: "Đã ghi nhận đặt cọc. Doanh thu hôm nay không đổi."

### Movements list

`GET /api/money-movements[?status]`; card: số tiền, counterparty, memo, status, chip nguồn.

### Bằng chứng — `EvidenceBlock` (Phase 6b-5)

Một widget `EvidenceBlock(captureType, evidenceText, evidenceUrl)` ở `core/evidence_block.dart`,
đặt **ngay dưới hàng chip** của Event Detail và Movement Detail, tiêu đề `Bằng chứng`:

| `captureType` | Hiển thị |
|---|---|
| `TEXT` | `evidenceText` in nghiêng trong khung mờ — câu gốc nằm cạnh `Nội dung` AI tóm tắt, thấy vì sao ra `450000` / `BANK` |
| `AUDIO` | transcript in nghiêng + nút **Nghe lại** (`audioplayers`; ẩn nút khi `evidenceUrl == null`) |
| `IMAGE_*` | thumbnail cao 160 (`BoxFit.cover`), chạm → `showDialog` bọc `InteractiveViewer` (pinch zoom), nút **Đóng** |
| cả hai `null` | dòng mờ `Không có bằng chứng đính kèm` |

`evidenceImage(url)`: `asset://demo/x` → `Image.asset('assets/demo/x')`, còn lại `Image.network`
với `errorBuilder` → `Không tải được bằng chứng`. Audio: `AssetSource('demo/x')` / `UrlSource(url)`.
Mock: `FakeTaxBridgeApi` gắn `asset://demo/<file demo vừa chọn>`; voice thêm transcript cố định
"Bán cho chị Lan 3 hộp collagen, tổng 450 nghìn, khách chuyển khoản."; text gắn nguyên câu gõ.

### Close day / History / Record detail

- Close day: `POST /api/close-day {date: hôm nay}` → `summary` 4 số + dòng 5 `Thuế khoán
  ước tính` (client tính từ `summary.revenue`, cùng `SummaryGrid` với Record detail) + list warning `OPEN`
  (`message`); nút **Xử lý** trên mỗi warning → `UNMATCHED_MONEY` → `/movements/{resourceId}`,
  `DRAFT_EVENT` → `/events/{resourceId}`; nút **Xem lịch sử ngày**.
- History: `GET /api/daily-records` → mỗi dòng `dd/MM/yyyy · Doanh thu X · ⚠ n` (n = OPEN;
  `✓` khi 0).
- Record detail: `GET /api/daily-records/{date}` → summary + warning (OPEN mặc định, toggle
  xem RESOLVED). Tap warning như trên; quay lại thấy summary mới, warning `RESOLVED`.

## 7. State (Riverpod 3)

```dart
final sessionProvider = NotifierProvider<SessionNotifier, AppSession?>(SessionNotifier.new);
final dashboardProvider = FutureProvider.autoDispose<Dashboard>(
    (ref) => ref.watch(apiProvider).dashboard(todayKey()));
final eventsProvider = FutureProvider.autoDispose.family<List<BusinessEvent>, String?>(
    (ref, status) => ref.watch(apiProvider).events(status: status));
final moneyMovementsProvider = FutureProvider.autoDispose.family<List<MoneyMovement>, String?>(...);
final movementProvider      = FutureProvider.autoDispose.family<MoneyMovement, String>(...);
final dailyHistoryProvider  = FutureProvider.autoDispose<List<DailyRecord>>(...);
final dailyRecordProvider   = FutureProvider.autoDispose.family<DailyRecord, String>(...);
final prevDashboardProvider = NotifierProvider<PrevDashboard, Dashboard?>(PrevDashboard.new); // wow 2
```

`PrevDashboard`: Home gọi `set(d)` sau khi render `Dashboard` d; lần render kế so `d` mới với
`state` để dựng delta banner và làm mốc cho số nhảy; `null` → không banner.

`SessionNotifier extends Notifier<AppSession?>`: `build()` trả session đã load ở app
start; `signIn(s)` lưu store + `state = s`; `signOut()` clear + `state = null`. Interceptor
401 gọi `signOut()` qua `onUnauthorized`. Mutation (confirm/match/classify/close-day) gọi
API trực tiếp từ widget rồi `ref.invalidate(...)`; chỉ capture có controller riêng
(`CaptureController`: idle / recording / uploading).

## 8. Lỗi, format, demo assets

- Một SnackBar chung "Có lỗi xảy ra. Vui lòng thử lại."; riêng: 401 login → "Đăng nhập
  không đúng", 409 register → "Username đã tồn tại", capture FAILED → "Không xử lý được. Thử lại.".
- `vnd(int)` → `4.820.000đ` (`NumberFormat('#,##0', 'vi_VN')`); ngày hiển thị `dd/MM/yyyy`,
  `dateKey` `yyyy-MM-dd`; `estTax(int revenue)` → `(revenue * 0.015).round()`.
- `assets/demo/`: `sale_voice.m4a`, `receipt.jpg`, `transfer_match.jpg`, `transfer_deposit.jpg`
  — tất cả đã có ở `taxbridge-prompt/demo-assets/` (ảnh render bằng AppKit 11/09, 1800×3200 / 1800×2600).
  Mode transfer có 2 ảnh nên nút **Dùng file demo** mở bottom sheet chọn match / deposit.

## 9. Phases (theo time-box build day, `hackathon-prep-checklist.md` §4)

### Phase 0 — Tối 11/09: skeleton

- [x] `flutter create` (org `vn.supremetech`, iOS + Android), packages, `pubspec.lock`.
- [x] `config.dart`, `router.dart`, `SessionStore`, `ApiClient`, `TaxBridgeApi` +
      `DioTaxBridgeApi` + `FakeTaxBridgeApi`, `tool/sync_fixtures.sh`, 7 model.
- [x] Login trống, Home khung 7 số đọc fixture (`USE_MOCK=true`).
- [x] `Info.plist` 3 key, `.vscode/launch.json` 4 config. [ ] signing, build lên **2 iPhone**.

### Phase 1 — 09:30 Tracer bullet

- [x] Capture text → `POST /api/captures` → Event Detail → confirm → Home refresh.
      Chạy mock trước, đổi sang ngrok khi backend sẵn.

### Phase 2 — 10:15 Auth + Home + Events

- [x] Login / Register (Zalo dropdown) / Logout; redirect.
- [x] Home 4 card + `bankIn` + badge; Events list.

### Phase 3 — 11:30 Ảnh + tiền vào

- [x] Capture receipt / transfer (`image_picker`), multipart.
- [x] Movements list / detail, match, classify + `go('/home')`.

### Phase 4 — 12:30 Voice

- [x] Capture voice (`record`), upload `AUDIO`.

### Phase 5 — 13:00 Close day

- [x] Close day, History, Record detail, tap warning → detail, invalidate sau xử lý.

### Phase 6 — 14:00 Demo polish & freeze

- [x] `assets/demo/` + nút **Dùng file demo**; loading text; empty state cơ bản.
- [ ] `flutter build ios --release` lên iPhone demo + máy dự phòng; chạy đủ 9 UC.
      **14:30 feature freeze.**

### Phase 6b — 14:00 Wow (song song polish; đúng thứ tự, cắt phần chưa xong lúc freeze)

- [x] 1 Thuế khoán ước tính (Home + SummaryGrid) — §6 Home, §8 `estTax`.
- [x] 2 Delta banner + số nhảy — §6 Home, §7 `prevDashboardProvider`.
- [x] 3 Auto-refresh Home 8 s — §6 Home.
- [x] 4 Chip nguồn 💬/🎤/📷 — §4 model `source, captureType`, §6 list/detail; cần BE Phase 5
      trả field (mock đã có qua fixture).
- [ ] 5 Bằng chứng — §1 `audioplayers`, §2 `evidence_block.dart`, §4 `evidenceText/evidenceUrl`,
      §6 Event/Movement Detail; cần BE Phase 3 trả field (mock qua fixture + file demo).
