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
- "cọc / đặt cọc" → DEPOSIT.
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

Hóa đơn, phiếu thu (ảnh):
- Chủ hộ chụp chứng từ do cửa hàng khác phát hành → chủ hộ là NGƯỜI MUA → PURCHASE.
- counterparty = tên cửa hàng phát hành phiếu, KHÔNG lấy tên khách in trên phiếu.
- amount = dòng "Tổng cộng / Thành tiền / Tổng tiền". KHÔNG lấy "Tiền khách đưa", "Tiền thối lại".

Ảnh chuyển khoản — đọc theo góc nhìn CHỦ SHOP, không phải góc nhìn người chụp màn hình:

- direction=IN là MẶC ĐỊNH. Ảnh chuyển khoản gần như luôn là KHÁCH trả tiền cho shop:
  màn hình "Chuyển khoản thành công" khách chụp gửi cho shop, biên lai "báo có", "nhận tiền",
  dấu "+". Màn hình ghi "Chuyển tiền thành công" KHÔNG có nghĩa là OUT — đó là khách chuyển
  ĐẾN shop, tiền vẫn VÀO shop → IN.
- direction=OUT chỉ khi có bằng chứng rõ chính chủ shop là người trả tiền đi. Nếu chỉ có ảnh,
  luôn trả IN.
- counterparty = NGƯỜI GỬI tiền (khách), lấy ở dòng "Từ / Nguồn tiền / Tài khoản nguồn".
  Tên ở dòng "Đến / Người nhận / Tài khoản nhận / Người thụ hưởng" là CHỦ SHOP —
  TUYỆT ĐỐI KHÔNG lấy tên đó làm counterparty.
  Ảnh chỉ hiện tên người nhận mà không hiện tên người gửi → lấy tên người từ nội dung
  chuyển khoản (ví dụ "LAN 3HOP" → "LAN"); nội dung không có tên người → null.
- memo = nội dung chuyển khoản, giữ nguyên như in trên ảnh.

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


def _parse(text_format, instruction: str, image: bytes | None):
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
            last = e
    raise last


def extract_event(text: str | None = None, image: bytes | None = None) -> EventExtraction:
    if image is not None:
        instruction = "Đây là ảnh chứng từ của hộ kinh doanh. Trích xuất giao dịch."
    else:
        instruction = f"Hôm nay là {today()}.\nCâu chủ hộ vừa ghi lại:\n{text}"
    return _parse(EventExtraction, instruction, image)


def extract_transfer(image: bytes) -> TransferExtraction:
    return _parse(TransferExtraction,
                  "Đây là ảnh biên lai / màn hình chuyển khoản ngân hàng mà CHỦ SHOP nhận được "
                  "từ khách. Trích xuất số tiền, chiều tiền và nội dung chuyển khoản.\n"
                  "Nhắc lại hai lỗi hay gặp:\n"
                  "1. Khách chụp màn hình 'Chuyển khoản thành công' của khách → tiền VÀO shop "
                  "→ direction='IN' (không phải OUT).\n"
                  "2. Tên ở dòng người NHẬN là chủ shop → không được dùng làm counterparty; "
                  "counterparty là người GỬI, hoặc lấy từ nội dung CK, hoặc null.", image)


def extract_image(image: bytes) -> ImageExtraction:
    return _parse(ImageExtraction,
                  "Ảnh chủ hộ gửi qua Zalo. Xác định kind: RECEIPT (hóa đơn, phiếu thu, "
                  "chứng từ mua bán), TRANSFER (biên lai / màn hình chuyển khoản), OTHER "
                  "(mọi ảnh khác). RECEIPT → điền event; TRANSFER → điền transfer; "
                  "OTHER → cả hai null.", image)


def extract_bank_history(image: bytes) -> BankHistoryExtraction:
    return _parse(BankHistoryExtraction,
                  "Ảnh danh sách giao dịch trong app ngân hàng / sao kê của CHỦ SHOP. "
                  "Mỗi dòng = một transfer: amount (int), direction ('+' / 'nhận' / 'báo có' "
                  "→ IN; '-' / 'chuyển đi' / 'thanh toán' → OUT), memo nguyên văn, "
                  "counterparty nếu có, occurredDate lấy từ cột ngày. "
                  "Bỏ dòng số dư, dòng tiêu đề, dòng không có số tiền. "
                  "Không gộp dòng, không bịa dòng.\n"
                  "CHỈ đọc ảnh là DANH SÁCH nhiều giao dịch. Hóa đơn, phiếu thu, biên lai của "
                  "một giao dịch, màn hình 'chuyển khoản thành công', hay ảnh bất kỳ khác → "
                  "trả transfers RỖNG, không suy diễn thành một dòng.", image)


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
