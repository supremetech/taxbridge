import 'package:dio/dio.dart';

import 'config.dart';
import 'session_store.dart';

/// Dio + interceptor gắn `X-Session-Token`; 401 → clear session → về Login.
class ApiClient {
  ApiClient({required this.sessionStore, required this.onUnauthorized})
    : dio = Dio(
        BaseOptions(
          baseUrl: apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(
            seconds: 90,
          ), // capture sync có thể 20 s
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) async {
          final s = await sessionStore.load();
          if (s != null) o.headers['X-Session-Token'] = s.token; // không Bearer
          h.next(o);
        },
        onError: (e, h) async {
          if (e.response?.statusCode == 401 &&
              !e.requestOptions.path.endsWith('/login')) {
            await sessionStore.clear();
            onUnauthorized();
          }
          h.next(e);
        },
      ),
    );
  }

  final Dio dio;
  final SessionStore sessionStore;
  final void Function() onUnauthorized;
}

/// Lỗi API có `code` từ contract (`{code, message}`).
class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message);
  final int? statusCode;
  final String? code;
  final String message;

  static ApiException from(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      return ApiException(
        e.response?.statusCode,
        data['code'] as String?,
        (data['message'] as String?) ?? e.message ?? 'Lỗi mạng',
      );
    }
    return ApiException(e.response?.statusCode, null, e.message ?? 'Lỗi mạng');
  }

  @override
  String toString() => 'ApiException($statusCode, $code, $message)';
}
