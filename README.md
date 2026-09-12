# TaxBridge

> **Keep your books by speaking, snapping a photo, or sending a chat message — AI does the rest.**
> A transaction-capture assistant for **Vietnamese household businesses**, turning the moment a sale
> happens into structured, evidence-backed revenue data that is ready for tax filing.
>
> PoC built for the **“Agents, Everywhere”** hackathon — AI Tinkerers Đà Nẵng, 12 Sep 2026.
>
> *The app UI and all product docs are in Vietnamese; this README is the English overview.*

---

## 1. Why

From 1 Jan 2026, household businesses in Vietnam **no longer pay presumptive (lump-sum) tax**. They
must self-declare on **actual revenue**, reconcilable against invoices, bank accounts and e-commerce
platform data. Their day-to-day reality, however, is still notebooks, Zalo messages, screenshots of
bank transfers, and cash.

The gap isn't a lack of accounting software. It sits between **the moment a transaction happens** and
**the moment it becomes a structured record**. TaxBridge fills exactly that layer. Full legal and
business context: [`BACKGROUND.md`](BACKGROUND.md).

## 2. The hero moment (30 seconds)

Photograph an incoming transfer of **380,000₫** → the app asks *“what is this?”* → tap **Deposit** →

**Money in bank +380,000₫ · Revenue unchanged ✓**

Money landing in the account is **not** the same thing as revenue. This is where household businesses
misreport most often — and it is the thing TaxBridge gets right from the very first PoC.

## 3. What it does

**v1 — running end to end**

| | |
|---|---|
| 📝 **Text** | “sold 3 boxes of collagen, 450k, bank transfer” → SALE draft, BANK / UNPAID |
| 🎤 **Voice** | Vietnamese audio → transcribe → same pipeline as text |
| 📷 **Receipt photo** | purchase slip → PURCHASE draft, original image kept as evidence |
| 🏦 **Transfer photo** | → *money movement* → **match** to a sale, or **classify** (deposit / owner's money) |
| 💬 **Zalo bot** | messaging the bot records a transaction; shared pipeline, bot replies with the result |
| 📊 **7-number dashboard** | revenue · expense · collected · receivable · **money in bank** · drafts · unmatched money |
| 🔒 **Close the day** | lock the day's books with OPEN/RESOLVED warnings; later fixes re-sync automatically |

**Phase 2**

- `occurredAt` = **the date printed on the document**, not the date of capture — Home browses by day, and already-closed books update themselves.
- **Date-range reports** (totals, by day, by type).
- **Backlog across all days** + replay of Zalo messages sent before the account was linked.
- **Bank-history screenshots** → many movements at once, duplicate rows skipped, with a **Reconcile** screen.

All 14 demo use cases with their expected numbers: [`CLAUDE.md` §9](taxbridge-prompt/CLAUDE.md).

## 4. Architecture

```text
taxbridge/                     monorepo, a single .git
├── taxbridge-app/             Flutter · Material 3 · Riverpod 3 · go_router · Dio  (REST only)
├── taxbridge-server/          Python 3.12 · Flask · Firebase Functions gen2 · Firestore · Storage · OpenAI
└── taxbridge-prompt/          source of truth: contract, plans, feature map, test suites
```

```text
 text / voice / photo / Zalo ──▶ POST /api/captures ──▶ AI extraction (synchronous)
                                        │
                          ┌─────────────┴─────────────┐
                          ▼                           ▼
                   BusinessEvent DRAFT          MoneyMovement UNMATCHED
                          │ confirm                   │ match / classify
                          └─────────────┬─────────────┘
                                        ▼
                            Dashboard  →  Close day  →  Reports
```

- AI: `gpt-5.6-terra` (vision/text, Responses API + Pydantic) · `gpt-transcribe` (audio, `vi`).
- Every figure is **computed on read** from Firestore — no ledger, no background jobs.
- Evidence (`evidenceText` / `evidenceUrl`) travels with each record and is shown in the app.

## 5. Running it

**Backend**

```bash
cd taxbridge-server/functions
gcloud auth application-default login && export GCLOUD_PROJECT=hackathon-42790
flask --app app.flask_app:create_app run --port 8787
# API docs (Swagger UI): http://127.0.0.1:8787/api/docs
```

**App** — runs **without a backend**:

```bash
cd taxbridge-app && flutter pub get && tool/sync_fixtures.sh
flutter run --dart-define=USE_MOCK=true --dart-define=DEMO=true      # mock API + bundled demo files
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8787 --dart-define=DEMO=true
```

`DEMO=true` enables the **“Use demo file”** button — sample images and audio live in
[`taxbridge-prompt/demo-assets/`](taxbridge-prompt/demo-assets/).

## 6. Testing

| Suite | What it measures | Run |
|---|---|---|
| [`taxbridge-server/tests/smoke/`](taxbridge-server/tests/smoke/) | the 9 v1 use cases over `curl`; doubles as a Zalo simulator | `tests/smoke/smoke.sh` |
| [`taxbridge-prompt/backend-test/`](taxbridge-prompt/backend-test/) | deterministic logic: candidates, match/classify, dashboard, close day (black-box REST, stdlib only) | `python3 run.py --out runs/<name>` → `score.py` |
| [`taxbridge-prompt/test-data/`](taxbridge-prompt/test-data/) | AI extraction accuracy — 21 cases with ground truth, scored automatically | `python3 run_cases.py` → `score.py` |
| [`taxbridge-prompt/feature-map/`](taxbridge-prompt/feature-map/) | end-to-end scenarios per feature (UI handles + commands + observable evidence) | read and re-enact after coding |

Every image and audio file in the test suites is a **synthetic fixture** — names, banks and account
numbers are all fictional.

## 7. Documentation

| File | Contents |
|---|---|
| [`BACKGROUND.md`](BACKGROUND.md) | 2026 legal context, household-business problems, product positioning |
| [`taxbridge-prompt/contract/`](taxbridge-prompt/contract/) | **source of truth #1**: DTOs, enums, endpoints, error codes, fixtures, Zalo payloads |
| [`taxbridge-prompt/implement-plan-backend-poc.md`](taxbridge-prompt/implement-plan-backend-poc.md) | backend plan §1–11 (v1) · §12–17 (Phase 2) |
| [`taxbridge-prompt/implement-plan-flutter-poc.md`](taxbridge-prompt/implement-plan-flutter-poc.md) | app plan §1–9 (v1) · §10–14 (Phase 2) |
| [`taxbridge-prompt/requirements-phase2.md`](taxbridge-prompt/requirements-phase2.md) | **why** Phase 2 was designed this way |
| [`CLAUDE.md`](taxbridge-prompt/CLAUDE.md) | working conventions for this repo + the 14 demo use cases |

## 8. Scope

This is a **hackathon PoC**, optimised for a 2-minute demo on a real iPhone — not a production build.

Deliberately **out of scope**: Firebase Auth & Security Rules, roles/permissions, multi-business,
idempotency, audit trail, double-entry ledger, offline sync, retry/backoff, e-invoicing, report export.

Deliberately **done properly**: one capture pipeline shared by the app and Zalo, evidence bound to
every record, and the line between **money in ≠ revenue**.

## 9. License

Released under the [MIT License](LICENSE) — © 2026 SupremeTech Co., Ltd.

The same terms cover the documentation in `taxbridge-prompt/` and the synthetic fixtures in
`demo-assets/` and `test-data/`. Those fixtures are fabricated for testing: the names, banks,
account numbers, transaction codes and tax IDs in them are fictional and carry a synthetic marker —
please don't reuse them outside a test context.

`BACKGROUND.md` summarises Vietnamese tax regulation as of September 2026 for product context. It is
not legal or tax advice.
