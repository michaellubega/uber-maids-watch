# Business rules

Two kinds of rule live here:

1. **Awaiting Evelyn's confirmation** — spoken requirements we must not turn
   into automated policy. Staff record agreed values manually.
2. **Implemented as configurable defaults** — technical placeholders the system
   uses so it can run, each explicitly labelled as unconfirmed in the UI.

## 1. Awaiting owner confirmation

| Item | Current understanding | Must be confirmed |
|---|---|---|
| UGX 150,000 | Mentioned as booking/service fee and monthly charge | One-time or recurring? |
| UGX 120,000 / UGX 30,000 | Maid and business shares were mentioned | Exact payment split and timing? |
| UGX 20,000 commitment savings | Mentioned separately | Additional or deducted from maid's share? Who holds it and when is it released? |
| Larger households | Price may increase with family size | Pricing factors and thresholds? |
| Two-week replacement | Free replacement guarantee described | Eligibility and exclusions? |
| Leave notice | Planned leave at least one week ahead | Calendar or working days? Emergency process? |
| Existing-maid supervision | UGX 150,000 monthly was mentioned | Included services and whether fee is per maid? |
| Multiple maids | System counts maids per household | Is each maid charged separately? |

Until confirmed, staff should record agreed quotes manually. Do not automate
disputed calculations.

## 2. Implemented defaults (all marked pending in the app)

| Setting | Default | Where it comes from | Status |
|---|---|---|---|
| Guarantee length | 14 days from the placement start date | `GUARANTEE_DAYS_DEFAULT` environment setting; stored per placement in `guarantee_days` | **Pending confirmation** — 14 days is an assumption based on "two-week replacement"; it is editable per placement |
| Follow-up window | 7 days | `FOLLOW_UP_WINDOW_DAYS_DEFAULT` | **Pending confirmation** — used as a suggested cadence only, never enforced |
| Replacement eligibility | Human decision | Manager records `ELIGIBLE` / `NOT_ELIGIBLE` with a reason; the server stores it and audits it | Implemented; the *criteria* remain pending confirmation |
| Service pricing | Free-text range (`price_min_ugx`, `price_max_ugx`), optional | Entered by staff in the catalogue | Implemented as data capture only; the app never calculates a price |
| Payment amounts | Entered manually by finance | `Payment.amount_ugx` | Implemented; no gateway, no automatic split, no automatic savings deduction |
| Maximum document size | 5 MB | `MAX_DOCUMENT_BYTES` | Operational default; change if the owner prefers |
| Leave notice | Recorded as a date and note | Worker status history / notes | Capture only; one-week rule not enforced |

### What the system deliberately does not do

- It does not compute the UGX 150,000 fee, the UGX 120,000/30,000 split or the
  UGX 20,000 savings.
- It does not decide that a replacement is free; it records a manager's decision
  and the reason.
- It does not automatically approve refunds, waivers or discounts.
- It does not send SMS, WhatsApp or e-mail.

When the owner confirms a rule, update the table above, set the environment
value or edit the code path, and remove the "pending" label from the relevant
screen (`Administration → Pending policies`, placement detail and replacement
detail).
