# TaxBridge — Flutter app (PoC)

App demo cho hộ kinh doanh: ghi giao dịch bằng text / giọng nói / ảnh chứng từ / ảnh chuyển
khoản → AI tạo bản nháp → ghép tiền vào với đơn bán → đóng ngày. Chỉ gọi REST theo
`../taxbridge-prompt/contract/`. Plan: `../taxbridge-prompt/implement-plan-flutter-poc.md`.

## Chạy

```bash
flutter pub get
tool/sync_fixtures.sh                                  # copy contract/fixtures → assets/fixtures

# Mock (không cần backend), có nút "Dùng file demo"
flutter run --dart-define=USE_MOCK=true --dart-define=DEMO=true

# Backend local (Simulator)
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8787 --dart-define=DEMO=true

# ngrok / prod: xem .vscode/launch.json
```

`--dart-define`: `API_BASE_URL` (origin, app tự nối `/api/...`), `USE_MOCK`, `DEMO`.

## Cấu trúc

```text
lib/core        config · api_client (Dio + X-Session-Token) · taxbridge_api (interface)
                dio_taxbridge_api · fake_taxbridge_api (fixtures + state in-memory)
                providers (Riverpod 3) · router (go_router) · evidence_block · widgets · format
lib/models      fromJson viết tay (session, event, movement, dashboard, daily_record…)
lib/features    auth · home · capture · events · movements · close_day
assets/fixtures copy từ contract (không sửa tay) · assets/demo  file demo cho nút "Dùng file demo"
```
