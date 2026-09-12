"""Trích xuất giao dịch bằng OpenAI (Responses API + Structured Outputs).

Schema Pydantic: mọi field bắt buộc, nullable dùng `Optional` (yêu cầu của Structured
Outputs). Model chính lỗi → thử lại một lần với model fallback rồi mới ném lỗi.
Rule trong `SYSTEM_PROMPT` bám các case eval trong `test-data/` (plan BE §4.1).
"""

import base64
import logging
import os
from typing import Literal, Optional

from openai import OpenAI
from pydantic import BaseModel

from .config import (REASONING_EFFORT, TRANSCRIBE_FALLBACK_MODEL, TRANSCRIBE_MODEL,
                     VISION_FALLBACK_MODEL, VISION_MODEL)
from .firestore import today

_client: OpenAI | None = None


def client() -> OpenAI:
    global _client
    if _client is None:
        _client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))
    return _client


# --- Schema ---------------------------------------------------------------

class EventExtraction(BaseModel):
    type: Literal["SALE", "PURCHASE", "DEPOSIT", "OWNER_MONEY", "UNKNOWN"]
    amount: int                       # VND
    description: str
    counterparty: Optional[str]
    paymentMethod: Literal["CASH", "BANK", "UNKNOWN"]
    paymentStatus: Literal["UNPAID", "PAID", "UNKNOWN"]
    occurredDate: Optional[str]       # ngày in trên chứng từ, "YYYY-MM-DD[THH:MM]" (§12)
    confidence: float


class TransferExtraction(BaseModel):
    direction: Literal["IN", "OUT"]
    amount: int
    counterparty: Optional[str]
    memo: Optional[str]
    occurredDate: Optional[str]       # ngày in trên biên lai (§12)


class BankHistoryExtraction(BaseModel):
    """Ảnh danh sách giao dịch ngân hàng: mỗi dòng là một transfer (§15)."""

    transfers: list[TransferExtraction]


class ImageExtraction(BaseModel):     # IMAGE_UNKNOWN (ảnh Zalo)
    kind: Literal["RECEIPT", "TRANSFER", "OTHER"]
    event: Optional[EventExtraction]
    transfer: Optional[TransferExtraction]


# --- Prompt ---------------------------------------------------------------

SYSTEM_PROMPT = """\
Bạn trích xuất giao dịch cho hộ kinh doanh Việt Nam. Người nói / người chụp luôn là CHỦ HỘ.

Phân loại:
- "bán / khách lấy / khách mua" → SALE.
- "mua / nhập hàng", hoặc phiếu thu, hóa đơn do CỬA HÀNG KHÁC phát hành → PURCHASE.
- "cọc / đặt cọc / tiền cọc" → DEPOSIT. Nhưng "khách ĐẶT hàng / đặt 2 cân" là đơn bán
  bình thường → SALE, không phải DEPOSIT (eval T5).
- "rút tiền / góp vốn / tiền nhà / bỏ vào quỹ / tiền cá nhân" → OWNER_MONEY.
- Không rõ là giao dịch gì → UNKNOWN, amount = 0, confidence thấp.

Số tiền (int VND, không dấu chấm):
- "450 nghìn" = 450000, "300k" = 300000, "1 triệu 2" = 1200000, "1 triệu 250" = 1250000,
  "1tr5" = 1500000, "2 triệu 920" = 2920000.
- Người nói tự sửa giữa chừng ("300 nghìn à không, 320") → lấy số CHỐT CUỐI CÙNG.
- Không bịa số. Không biến số lượng, mã vạch, số điện thoại, giờ, mã đơn thành số tiền.

Thanh toán:
- SALE + "chuyển khoản / ck / banking" → paymentMethod=BANK, paymentStatus=UNPAID.
- Chỉ PAID khi nói rõ "đã nhận / đã thanh toán / đã chuyển rồi", hoặc trả tiền mặt.
- KHÔNG nói hình thức thanh toán → paymentMethod=UNKNOWN và paymentStatus=UNKNOWN. Không đoán.
- PURCHASE có phiếu / hóa đơn trên tay → PAID.

Hóa đơn, phiếu thu (ảnh) — xác định ai PHÁT HÀNH phiếu trước khi chọn loại:
- BÊN PHÁT HÀNH = tên in to ở ĐẦU phiếu, kèm địa chỉ / điện thoại / MST. Dòng
  "Khách hàng / Người mua" là bên MUA.
- Chủ hộ đang cầm phiếu do CỬA HÀNG KHÁC phát hành → chủ hộ chính là bên MUA → **PURCHASE**,
  counterparty = BÊN PHÁT HÀNH ở đầu phiếu. Tên ở dòng "Khách hàng / Người mua" là chủ hộ,
  TUYỆT ĐỐI KHÔNG lấy làm counterparty.
- Tiêu đề "HÓA ĐƠN BÁN LẺ / HÓA ĐƠN BÁN HÀNG / PHIẾU BÁN HÀNG" chỉ nói phiếu do bên BÁN lập —
  KHÔNG có nghĩa hộ kinh doanh đang bán. Đừng vì chữ "bán" mà trả SALE.
- Chỉ trả SALE khi tên ở ĐẦU phiếu đúng là cửa hàng của chính chủ hộ (hoặc trùng tên chủ hộ).
- amount = dòng "Tổng cộng / Thành tiền / Tổng tiền". KHÔNG lấy "Tiền khách đưa", "Tiền thối lại".

Ảnh chuyển khoản / biên lai — chiều tiền đọc theo góc nhìn CHỦ HỘ, theo đúng thứ tự sau:

1. DẤU và NHÃN của số tiền là bằng chứng mạnh nhất, xét trước hết:
   - "−100.000đ", "Chuyển đến …", "Chuyển tiền tới", "Thanh toán", "Trừ tiền" → tiền RỜI khỏi
     chủ hộ → direction=OUT, counterparty = NGƯỜI NHẬN.
   - "+100.000đ", "Nhận tiền …", "Báo có", "Tiền vào", "Nhận từ" → direction=IN,
     counterparty = NGƯỜI GỬI.
2. Ảnh KHÔNG có dấu +/− và không có nhãn chiều tiền (màn "Chuyển khoản thành công" do KHÁCH
   chụp rồi gửi cho shop, dòng "Người nhận" chính là chủ hộ) → direction=IN,
   counterparty = người GỬI.
3. Nếu đề bài cho TÊN CHỦ HỘ: bên nào mang tên đó là chủ hộ, TUYỆT ĐỐI không lấy làm
   counterparty; bên còn lại mới là counterparty. Tiền đi VỀ phía chủ hộ → IN, RỜI khỏi chủ
   hộ → OUT. Quy tắc này thắng mọi suy đoán khác.
4. Nội dung chuyển khoản (memo) KHÔNG quyết định chiều tiền và KHÔNG ghi đè tên hai bên đã in
   rõ trên ảnh. Memo có thể rỗng, có thể là lời nhắn vu vơ ("hôm qua em tuyệt vời lắm"), có thể
   ghi NGƯỢC ("A chuyển tiền cho B" trong khi giao dịch là B trả cho A) — gặp mâu thuẫn thì
   tin dấu / nhãn / tên hai bên, bỏ qua memo.
   Chỉ dùng memo để lấy tên khi ảnh không hiện tên bên kia ("LAN 3HOP" → "LAN"); không có tên
   người → null.
- memo = nội dung chuyển khoản giữ nguyên như in trên ảnh; không có nội dung → null.

Ngày giao dịch (occurredDate):
- Ảnh: lấy ngày (và giờ nếu có) IN TRÊN chứng từ, đổi "11/09/2026 11:02" → "2026-09-11T11:02".
- Câu nói / text: chỉ khi nêu rõ ("hôm qua", "sáng 10/9", "tuần trước thứ hai"); quy đổi theo
  "Hôm nay là {today}". Không nêu → null. Không đoán.

description: một câu ngắn tiếng Việt mô tả giao dịch. Không chắc thì confidence thấp.\
"""

TRANSCRIBE_PROMPT = ("Chủ hộ kinh doanh Việt Nam đọc một giao dịch bán/mua hàng: "
                     "tên khách, số lượng, số tiền (nghìn/triệu/k), cách thanh toán.")
TRANSCRIBE_KEYWORDS = ["chuyển khoản", "tiền mặt", "đặt cọc", "nghìn", "triệu", "hộp", "collagen"]


# --- Gọi model ------------------------------------------------------------

def _data_url(image: bytes) -> str:
    mime = "image/png" if image[:8] == b"\x89PNG\r\n\x1a\n" else "image/jpeg"
    return f"data:{mime};base64,{base64.b64encode(image).decode()}"


def _content(instruction: str, image: bytes | None):
    parts = [{"type": "input_text", "text": instruction}]
    if image is not None:
        parts.append({"type": "input_image", "image_url": _data_url(image)})
    return parts


def _owner_line(owner_name: str | None) -> str:
    """Tên chủ hộ để model biết bên nào là chủ, bên nào là counterparty (rule 3)."""
    if not owner_name:
        return ""
    return (f'\nTên chủ hộ (chủ tài khoản đang dùng app này): "{owner_name}". '
            "Bên mang tên này là CHỦ HỘ, không bao giờ là counterparty.")


# Lỗi của lần gọi model gần nhất; `capture_service` ghi vào capture doc để đọc được trên prod
# (firebase functions:log không in nổi text). Rơi xuống fallback là im lặng nên rất khó lần.
LAST_ERRORS: list[str] = []


def _parse(text_format, instruction: str, image: bytes | None):
    LAST_ERRORS.clear()
    last = None
    for model in (VISION_MODEL, VISION_FALLBACK_MODEL):
        try:
            resp = client().responses.parse(
                model=model,
                reasoning={"effort": REASONING_EFFORT},
                input=[{"role": "system", "content": SYSTEM_PROMPT},
                       {"role": "user", "content": _content(instruction, image)}],
                text_format=text_format)
            return resp.output_parsed
        except Exception as e:
            logging.warning("model %s lỗi: %s", model, e)
            LAST_ERRORS.append(f"{model}: {type(e).__name__}: {e}"[:500])
            last = e
    raise last


def extract_event(text: str | None = None, image: bytes | None = None,
                  owner_name: str | None = None) -> EventExtraction:
    if image is not None:
        instruction = ("Đây là ảnh chứng từ của hộ kinh doanh. Trích xuất giao dịch.\n"
                       "Nếu là hóa đơn / phiếu thu: xem tên ở ĐẦU phiếu (bên phát hành). Khác "
                       "cửa hàng của chủ hộ → PURCHASE, counterparty = tên đầu phiếu, kể cả khi "
                       "tiêu đề ghi 'HÓA ĐƠN BÁN LẺ'."
                       + _owner_line(owner_name))
    else:
        instruction = f"Hôm nay là {today()}.\nCâu chủ hộ vừa ghi lại:\n{text}"
    return _parse(EventExtraction, instruction, image)


def extract_transfer(image: bytes, owner_name: str | None = None) -> TransferExtraction:
    return _parse(TransferExtraction,
                  "Ảnh biên lai / màn hình chi tiết giao dịch ngân hàng hoặc ví điện tử. "
                  "Trích xuất số tiền, CHIỀU TIỀN, tên bên kia và nội dung chuyển khoản.\n"
                  "Ba lỗi hay gặp, kiểm lại trước khi trả lời:\n"
                  "1. Số tiền có dấu '−' hoặc nhãn 'Chuyển đến / Chuyển tiền / Thanh toán' là "
                  "tiền RA (direction='OUT'), counterparty là NGƯỜI NHẬN — đừng mặc định 'IN'.\n"
                  "2. Khách chụp màn hình 'Chuyển khoản thành công' (không có dấu +/−) gửi cho "
                  "shop → tiền VÀO shop, direction='IN', counterparty là người GỬI.\n"
                  "3. Nội dung chuyển khoản có thể rỗng, vu vơ, hoặc ghi ngược chiều — không "
                  "được dùng memo để quyết định chiều tiền hay đổi tên hai bên."
                  + _owner_line(owner_name), image)


def extract_image(image: bytes, owner_name: str | None = None) -> ImageExtraction:
    return _parse(ImageExtraction,
                  "Ảnh chủ hộ gửi qua Zalo. Xác định kind: RECEIPT (hóa đơn, phiếu thu, "
                  "chứng từ mua bán), TRANSFER (biên lai / màn hình chuyển khoản), OTHER "
                  "(mọi ảnh khác). RECEIPT → điền event; TRANSFER → điền transfer; "
                  "OTHER → cả hai null." + _owner_line(owner_name), image)


def extract_bank_history(image: bytes, owner_name: str | None = None) -> BankHistoryExtraction:
    return _parse(BankHistoryExtraction,
                  "Ảnh danh sách giao dịch trong app ngân hàng / sao kê của CHỦ SHOP. "
                  "Mỗi dòng = một transfer: amount (int), direction ('+' / 'nhận' / 'báo có' "
                  "→ IN; '-' / 'chuyển đi' / 'thanh toán' → OUT), memo nguyên văn, "
                  "counterparty nếu có, occurredDate lấy từ cột ngày. "
                  "Bỏ dòng số dư, dòng tiêu đề, dòng không có số tiền. "
                  "Không gộp dòng, không bịa dòng.\n"
                  "CHỈ đọc ảnh là DANH SÁCH nhiều giao dịch. Hóa đơn, phiếu thu, biên lai của "
                  "một giao dịch, màn hình 'chuyển khoản thành công', hay ảnh bất kỳ khác → "
                  "trả transfers RỖNG, không suy diễn thành một dòng."
                  + _owner_line(owner_name), image)


def transcribe(m4a: bytes) -> str:
    """`gpt-transcribe` chỉ nhận `languages` (số nhiều) + `keywords`, gửi qua extra_body."""
    last = None
    for model in (TRANSCRIBE_MODEL, TRANSCRIBE_FALLBACK_MODEL):
        kw = dict(model=model, file=("voice.m4a", m4a), prompt=TRANSCRIBE_PROMPT)
        if model == "gpt-transcribe":
            kw["extra_body"] = {"languages": ["vi"], "keywords": TRANSCRIBE_KEYWORDS}
        else:
            kw["language"] = "vi"
        try:
            return client().audio.transcriptions.create(**kw).text
        except Exception as e:
            logging.warning("transcribe %s lỗi: %s", model, e)
            last = e
    raise last
