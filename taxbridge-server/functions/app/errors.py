"""Lỗi nghiệp vụ → response `{code, message}` (contract/README §3)."""


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


def validation(message="Dữ liệu không hợp lệ."):
    return ApiError(400, "VALIDATION_ERROR", message)


def unauthorized(message="Token không hợp lệ."):
    return ApiError(401, "UNAUTHORIZED", message)


def not_found(message="Không tìm thấy."):
    return ApiError(404, "NOT_FOUND", message)


def invalid_state(message="Trạng thái không cho phép thao tác này."):
    return ApiError(409, "INVALID_STATE", message)
