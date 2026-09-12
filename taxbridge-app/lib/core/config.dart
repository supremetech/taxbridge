/// Cấu hình từ `--dart-define`. `API_BASE_URL` là origin, app tự nối `/api/...`.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8787',
);
const useMock = bool.fromEnvironment('USE_MOCK', defaultValue: false);
const demoMode = bool.fromEnvironment('DEMO', defaultValue: false);
