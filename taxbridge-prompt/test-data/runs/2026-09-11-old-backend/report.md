# Kết quả eval — 2026-09-11 08:17

_Baseline chạy trên **backend cũ** (trước commit `remove all` ở `taxbridge-server`, chưa theo plan hiện tại).
Không có `actual.json` đi kèm — chỉ giữ để so trước/sau. Các lỗi lặp ở đây đã thành rule prompt
ở `implement-plan-backend-poc.md` §4.1 (đánh dấu *eval*)._

**Case pass: 11/21** (52%)

## Theo case

| Case | Tình huống | KQ | Sai ở đâu |
|---|---|---|---|
| A1 | CLEAN_SALE_VOICE | ✅ |  |
| A2 | DIALECT_PLUS_NOISE | ✅ |  |
| A3 | CORRECTION_IN_SPEECH | ❌ | amount: expected 600000 / actual 400000 |
| A4 | NO_BUSINESS_INTENT | ❌ | đã bịa ra event type=SALE amount=11500 |
| D1 | DAILY_ROLLUP | ❌ | revenue: expected 4,940,000 / actual 5190000; expense: expected 1,720,000 / actual 1920000; receivable: expected 2,320,000 / actual 2570000; warningCount: expected 2 / actual 1 |
| M1 | CLEAN_MATCH | ❌ | DÍNH BẪY TÊN: counterparty = 'DINH QUOC BAO' (là chủ shop) |
| M2 | MATCH_BY_AMOUNT_ONLY | ✅ |  |
| M3 | AMBIGUOUS_CANDIDATES | ❌ | candidates: expected ⊇ ['A3', 'T5'] / actual ['T5']; TỰ GHÉP SAI: đã ghép T5 dù không được phép auto-match |
| M4 | UNMATCHED_TO_DEPOSIT | ✅ |  |
| M5 | UNMATCHED_NO_HINT | ✅ |  |
| M6 | UNMATCHED_TO_OWNER | ❌ | DÍNH BẪY TÊN: counterparty = 'DINH QUOC BAO' (là chủ shop) |
| M7 | AMOUNT_MISMATCH_FEE | ✅ |  |
| R1 | CLEAN_RECEIPT | ✅ |  |
| R2 | LOW_QUALITY_RECEIPT | ❌ | amount: expected 185000 / actual 200000 |
| R3 | IMAGE_UNCLASSIFIED | ✅ |  |
| T1 | CLEAN_SALE | ✅ |  |
| T2 | MISSING_PAYMENT_METHOD | ❌ | paymentMethod: expected UNKNOWN / actual CASH; paymentStatus: expected UNKNOWN / actual PAID |
| T3 | CLEAN_PURCHASE | ✅ |  |
| T4 | OWNER_MONEY_TEXT | ❌ | type: expected OWNER_MONEY / actual SALE |
| T5 | AMBIGUOUS_PAIR_A | ✅ |  |
| T6 | COLLOQUIAL_AMOUNT | ❌ | amount: expected 1250000 / actual 250000 |

## Độ chính xác theo field (critical, tự động)

| Field | Đúng/Tổng | % |
|---|---|---|
| amount | 15/18 | 83% |
| classificationType | 7/7 | 100% |
| collected | 1/1 | 100% |
| direction | 7/7 | 100% |
| expense | 0/1 | 0% |
| paymentMethod | 10/11 | 91% |
| paymentStatus | 10/11 | 91% |
| receivable | 0/1 | 0% |
| revenue | 0/1 | 0% |
| status | 7/7 | 100% |
| type | 10/11 | 91% |
| warningCount | 0/1 | 0% |

## Ghép tiền vào (hero use case)

- Top-1 đúng: 2/2
- Trả đủ candidate kỳ vọng: 2/3
- Tự ghép khi KHÔNG được phép: 1 lần (CẦN SỬA)
- Dính bẫy lấy tên chủ shop làm counterparty: 2/6 (CẦN SỬA)

## Confusion — BusinessEvent.type

| Expected | Actual | Số ca |
|---|---|---|
| SALE | SALE | 7 |
| PURCHASE | PURCHASE | 3 |
| OWNER_MONEY | SALE | 1 |

## Bước tiếp theo

Gom các case FAIL theo NGUYÊN NHÂN CHUNG (không sửa lẻ từng case), sửa prompt/logic theo nguyên nhân đó, rồi chạy lại đúng bộ này để so trước/sau.
