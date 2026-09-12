# Kết quả eval — 2026-09-12 11:30

**Case pass: 18/21** (86%)

## Theo case

| Case | Tình huống | KQ | Sai ở đâu |
|---|---|---|---|
| A1 | CLEAN_SALE_VOICE | ✅ |  |
| A2 | DIALECT_PLUS_NOISE | ✅ |  |
| A3 | CORRECTION_IN_SPEECH | ✅ |  |
| A4 | NO_BUSINESS_INTENT | ✅ |  |
| D1 | DAILY_ROLLUP | ❌ | revenue: expected 4,940,000 / actual 4340000; receivable: expected 2,320,000 / actual 1720000; warningCount: expected 2 / actual 3 |
| M1 | CLEAN_MATCH | ✅ |  |
| M2 | MATCH_BY_AMOUNT_ONLY | ✅ |  |
| M3 | AMBIGUOUS_CANDIDATES | ❌ | candidates: expected ⊇ ['A3', 'T5'] / actual ['A3'] |
| M4 | UNMATCHED_TO_DEPOSIT | ✅ |  |
| M5 | UNMATCHED_NO_HINT | ✅ |  |
| M6 | UNMATCHED_TO_OWNER | ✅ |  |
| M7 | AMOUNT_MISMATCH_FEE | ✅ |  |
| R1 | CLEAN_RECEIPT | ✅ |  |
| R2 | LOW_QUALITY_RECEIPT | ✅ |  |
| R3 | IMAGE_UNCLASSIFIED | ✅ |  |
| T1 | CLEAN_SALE | ✅ |  |
| T2 | MISSING_PAYMENT_METHOD | ✅ |  |
| T3 | CLEAN_PURCHASE | ✅ |  |
| T4 | OWNER_MONEY_TEXT | ✅ |  |
| T5 | AMBIGUOUS_PAIR_A | ❌ | type: expected SALE / actual DEPOSIT |
| T6 | COLLOQUIAL_AMOUNT | ✅ |  |

## Độ chính xác theo field (critical, tự động)

| Field | Đúng/Tổng | % |
|---|---|---|
| amount | 18/18 | 100% |
| classificationType | 7/7 | 100% |
| collected | 1/1 | 100% |
| direction | 7/7 | 100% |
| expense | 1/1 | 100% |
| paymentMethod | 11/11 | 100% |
| paymentStatus | 11/11 | 100% |
| receivable | 0/1 | 0% |
| revenue | 0/1 | 0% |
| status | 7/7 | 100% |
| type | 10/11 | 91% |
| warningCount | 0/1 | 0% |

## Ghép tiền vào (hero use case)

- Top-1 đúng: 2/2
- Trả đủ candidate kỳ vọng: 2/3
- Tự ghép khi KHÔNG được phép: 0 lần (đạt)
- Dính bẫy lấy tên chủ shop làm counterparty: 0/6 (đạt)

## Confusion — BusinessEvent.type

| Expected | Actual | Số ca |
|---|---|---|
| SALE | SALE | 6 |
| PURCHASE | PURCHASE | 3 |
| OWNER_MONEY | OWNER_MONEY | 1 |
| SALE | DEPOSIT | 1 |

## Bước tiếp theo

Gom các case FAIL theo NGUYÊN NHÂN CHUNG (không sửa lẻ từng case), sửa prompt/logic theo nguyên nhân đó, rồi chạy lại đúng bộ này để so trước/sau.
