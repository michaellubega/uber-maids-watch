# Implementation status

_Last verified: 15 November 2026._

## Summary

| Layer | Status |
|---|---|
| Django REST backend | Complete for the MVP scope, 67 automated tests passing |
| Client / maid web portal | Complete for the MVP scope, including self-registration and private document upload, covered by the 67 tests |
| Flutter client (Windows + Android) | Complete for the MVP scope, 27 automated tests passing, Windows release build verified |
| PostgreSQL runtime | Configured as the production default; not exercised because no PostgreSQL or Docker daemon was available in the delivery environment |
| Docker Compose stack | Files and static validation only; not started |
| Render deployment | Live at <https://uber-maids-watch.onrender.com> (free plan), verified end to end |

The workflow implemented end to end is:

```
register → verify → train → match → place → track → support → replace (when eligible)
```

Training is represented by worker skills, references and status history. There
is no separate training-session module yet; that is a deliberate scope
decision, not a hidden gap.

## Backend

### Applications

| App | Responsibility |
|---|---|
| `core` | Custom UUID user, roles, audit log, counters, sync sequence, health/login/me/dashboard, user and audit endpoints |
| `catalog` | Service catalogue with configurable price ranges |
| `workers` | Worker records, private documents, references, verification checks, status history |
| `clients` | Client (family) records |
| `operations` | Bookings, placements, guarantee tracking, follow-ups, incidents, replacement cases |
| `payments` | Payment records and receipts |
| `sync` | Pull/push protocol, role scoping, idempotency, conflict handling |
| `portal` | Public landing page, family/maid session login, role-scoped portal pages |

### Endpoints

| Method | Path | Notes |
|---|---|---|
| GET | `/api/health/` | Liveness plus database check |
| POST | `/api/auth/token/` | JWT login (access 12 h, refresh 30 d) |
| POST | `/api/auth/token/refresh/` | Refresh an access token |
| GET | `/api/auth/me/` | Current user, role and capabilities |
| GET | `/api/dashboard/summary/` | Role-scoped counts, no synthetic data |
| GET | `/api/sync/pull/?since=&limit=` | Changes in global sequence order |
| POST | `/api/sync/push/` | Batch of ≤200 mutations |
| GET | `/api/workers/` | Worker list/detail |
| POST | `/api/workers/{id}/verify/` | Verification decision (online, audited) |
| GET | `/api/workers/{id}/history/` | Status history |
| POST | `/api/worker-documents/` | Upload to private storage; office roles and the linked maid (own record only) |
| GET | `/api/worker-documents/{id}/download/` | Authenticated, audited download |
| GET | `/api/worker-references/`, `/api/verification-checks/` | Supporting verification data |
| GET/POST | `/api/clients/`, `/api/services/` | Family and catalogue records |
| GET/POST | `/api/bookings/` | Requests |
| POST | `/api/bookings/{id}/confirm/` | Online, audited |
| GET/POST | `/api/placements/` | Placements |
| GET | `/api/placements/{id}/guarantee/` | Guarantee window status |
| GET/POST | `/api/follow-ups/` | Scheduled support calls |
| POST | `/api/follow-ups/{id}/complete/` | Online, creates the next follow-up |
| GET/POST | `/api/replacement-cases/` | Replacement cases |
| POST | `/api/replacement-cases/{id}/review/` | Eligibility decision, online, audited |
| POST | `/api/replacement-cases/{id}/assign/` | Backup worker + placement, online |
| POST | `/api/replacement-cases/{id}/resolve/` | Close the case |
| GET/POST | `/api/incidents/` | Support incidents |
| GET/POST | `/api/payments/` | Payment records |
| GET | `/api/users/`, `/api/audit-logs/` | Administrators only |
| GET | `/api/schema/`, `/api/docs/` | OpenAPI schema and Swagger UI |

### Web portal routes

| Method | Path | Notes |
|---|---|---|
| GET | `/` | Public landing page and service overview |
| GET/POST | `/login/` | Session sign-in for `FAMILY` and `MAID` accounts |
| GET/POST | `/register/` | Self-service family or domestic-worker registration |
| POST | `/logout/` | CSRF-protected sign-out |
| GET | `/portal/` | Role-scoped dashboard |
| GET/POST | `/portal/bookings/`, `/portal/bookings/new/` | Own booking list and request form |
| GET | `/portal/placements/`, `/portal/placements/{id}/` | Own placements and guarantee status |
| GET | `/portal/follow-ups/` | Own scheduled support calls |
| GET | `/portal/payments/` | Own payment history |
| GET/POST | `/portal/replacements/`, `/portal/replacements/new/` | Own replacement cases |
| GET | `/portal/profile/` | Account and linked client/worker details |
| GET/POST | `/portal/documents/` | Maid document list and upload form |
| GET | `/portal/documents/{id}/download/` | Own document download, audited |

Staff roles receive a 403 notice directing them to the desktop client. The portal
uses Django sessions and CSRF tokens; the JWT API is unaffected.

### Security and correctness

- Server-side role checks on every viewset and on every sync mutation.
- UUID primary keys and a global `change_seq` on all syncable models.
- Soft deletes only; deleted records travel as tombstones.
- Per-mutation idempotency through `ProcessedMutation`.
- Optimistic concurrency through `base_version`; a stale write returns
  `conflict` together with the current server record.
- Documents stored outside the public media tree and served only through an
  authenticated endpoint; each download is audited.
- Sensitive actions (verification, confirmation, replacement decisions, payment
  changes, user administration) are written to the audit log with actor,
  entity, metadata and request context.

### Verification evidence

```powershell
cd backend
$env:DJANGO_SETTINGS_MODULE = "config.settings_test"
$env:DB_ENGINE = "sqlite"
.\.venv\Scripts\python.exe manage.py test tests -v 2
# Ran 67 tests ... OK
```

`manage.py check` reports no issues. The OpenAPI schema generates without
errors (two cosmetic enum-naming warnings). `manage.py check --deploy` reports
no security warnings when `DJANGO_DEBUG=False` and a real secret key is set.

A live end-to-end run against the SQLite development server confirmed:

| Check | Result |
|---|---|
| Health | `ok`, database `ok` |
| Admin login and `/auth/me/` | correct role |
| Pull with `limit=5` | `has_more=true`, advancing cursor |
| First push | `applied` with server version and change sequence |
| Replay of the same `mutation_id` | `duplicate` |
| Push with a stale `base_version` | `conflict` plus server record |
| Family account calling `/users/` | HTTP 403 |

The temporary test worker was deleted afterwards.

### Portal verification

The portal was also exercised against the live SQLite development server at an
800 px viewport:

| Check | Result |
|---|---|
| Landing page and brand assets | Rendered, logo and palette correct |
| Family sign-in | Dashboard, placements, payments and replacements scoped to the account |
| Booking request E2E | Created `B-000004`, flash confirmation shown; record and audit row removed afterwards |
| Maid sign-in | Placement and follow-up data scoped to the linked worker |
| Staff account visiting `/portal/` | 403 notice with desktop-app guidance |
| Responsive layout | No horizontal overflow at 800 px and mobile breakpoints |

## Web portal implementation

| Path | Responsibility |
|---|---|
| `portal/decorators.py` | `portal_required` / `role_required`; only `FAMILY` and `MAID` may enter |
| `portal/views.py` | Landing, registration, session login/logout, role-scoped dashboards, record pages and maid document upload/download |
| `portal/forms.py` | Registration, booking, replacement and document upload forms |
| `portal/templates/portal/` | Branded base layout and all portal pages |
| `portal/static/portal/` | `site.css`, `site.js`, logo, mark and favicons |
| `portal/templatetags/portal_extras.py` | UGX formatting, status tones, guarantee and follow-up helpers |
| `tests/test_portal.py` | Access, scoping, form, redirect-safety, self-registration and document tests |

### Self-registration and document upload

| Behaviour | Implementation |
|---|---|
| Public registration | `/register/` accepts only `FAMILY` or `MAID`; passwords are validated with Django's password validators and usernames are unique case-insensitively |
| Family account | Creates a `FAMILY` user linked to a new `Client` with an active status |
| Worker account | Creates a `MAID` user linked to a new `Worker` with `status=APPLICANT` and `verification_status=PENDING`; no verification timestamp or verifier is set |
| Registration audit | `PORTAL_REGISTERED` records the username, role and new client/worker number |
| Portal upload | `MAID` only, own worker record, `WorkerDocumentForm`, PDF/JPG/PNG up to `MAX_DOCUMENT_BYTES`, private storage |
| Portal download | Own document only, streamed as an attachment, `DOCUMENT_DOWNLOADED` audit event |
| Mobile upload | `POST /api/worker-documents/` with multipart data; a maid may upload only for her own worker record and cannot set `verified` |
| Desktop upload | The worker detail dialog in Flutter lists documents and uploads a selected file through the same API |
| Verification | Uploads never verify a document or a worker; only office roles may mark a document verified |

## Deployment files

| Path | Purpose |
|---|---|
| `render.yaml` | Render Blueprint: PostgreSQL 16 + Python web service + env vars |
| `backend/build.sh` | Installs dependencies, collects static files, migrates, optional seed |
| `backend/Dockerfile`, `backend/docker-compose.yml` | Container deployment alternative |
| `backend/config/settings.py` | `DATABASE_URL`, Render host detection, HTTPS/HSTS/cookie security |

## Flutter client

### Structure

| Path | Responsibility |
|---|---|
| `lib/core/api_client.dart` | JSON client, authenticated multipart upload, JWT refresh with one retry |
| `lib/core/api_config.dart` | Hosted Render default with `UMW_API_URL` / login-screen override |
| `lib/core/local_database.dart` | Per-user JSON cache, outbox, conflicts, tombstones, atomic writes |
| `lib/core/sync_service.dart` | Push-then-pull orchestration over a `SyncTransport` abstraction |
| `lib/core/models.dart` | Users, server rows, outbox mutations, sync outcome |
| `lib/core/permissions.dart` | Role matrix, navigation, capability overrides from the server |
| `lib/core/session_store.dart` | Local session persistence |
| `lib/core/connectivity.dart` | Connectivity abstraction (real and test doubles) |
| `lib/core/formatters.dart` | UGX money, dates, guarantee and follow-up calculations |
| `lib/state/app_state.dart` | Auth, cache, sync, CRUD, workflow actions |
| `lib/ui/` | Screens and forms, including the worker document upload dialog |

### Screens

Dashboard, workers + detail, clients, service catalogue, bookings, placements,
follow-ups, replacements + detail, payments, offline/sync centre and
administration (users, audit trail, pending policies). Every screen handles
empty, loading, offline and error states. Lists search and filter locally, so
they keep working with no connection.

### Verification evidence

```powershell
cd flutter_app
flutter analyze   # No issues found!
flutter test      # 27 tests passed
flutter build windows --release
```

Tests cover:

- cache persistence, outbox coalescing, tombstones and conflict resolution;
- push/pull ordering, idempotent replay, rejection messages and offline
  behaviour;
- the role matrix, capability overrides and navigation;
- money/date/guarantee/follow-up formatting;
- the hosted Render default URL and the 75-second cold-start timeout;
- authenticated multipart document upload, including server validation errors;
- a signed-out widget smoke test.

## Live Render verification (15 November 2026)

| Check | Result |
|---|---|
| `GET /api/health/` | 200, `status=ok`, database `ok` |
| `GET /` | 200, branded landing page |
| `GET /static/portal/css/site.css` | 200, 23,814 bytes, brand teal present |
| `GET /static/portal/img/logo.png` | 200, 638,654 bytes |
| `GET /admin/login/` | 200 |
| `GET /api/docs/`, `/api/schema/` | 200; schema generates without warnings |
| `POST /api/auth/token/` (family, admin, maid) | 200 |
| Family portal login | 200, redirected to `/portal/`, dashboard includes Daniel's data and UGX amounts |
| Maid portal login | 200, redirected to `/portal/`, dashboard includes Aisha's placement |
| Staff portal sign-in | Blocked with the "use the desktop application" message |
| HTTP to HTTPS | 301 to `https://uber-maids-watch.onrender.com/` |
| Database | Managed PostgreSQL 16, migrations and demo seed applied on build |

## Known limitations

| Item | Detail |
|---|---|
| PostgreSQL runtime | Verified through the live Render deployment (managed PostgreSQL 16); the local delivery environment had no PostgreSQL service. |
| Docker Compose | No Docker daemon was available. `docker compose config` was not run; the files were reviewed statically. |
| Render live deployment | Deployed and verified at <https://uber-maids-watch.onrender.com>. The web service is on the free plan (sleeps after inactivity) and the free PostgreSQL instance expires on 15 December 2026. The free plan has no persistent disk, so private documents are lost on redeploy; attach a paid disk and set `PRIVATE_MEDIA_ROOT` before storing real identity documents. |
| Android | SDK is present, licences are not accepted, so no Android build or emulator run was done. |
| Windows long path | The project is at a short path (`C:\Users\dieve\OneDrive\Desktop\umw`) and `flutter build windows --release` succeeds there. MSBuild's 260-character limit only matters if the project is moved to a deeper folder; see the README workaround. |
| Notifications | No SMS, WhatsApp or e-mail gateway is integrated. Follow-ups are records, not outgoing messages. |
| Payment gateway | Payments are recorded manually; no mobile-money integration. |
| Training module | Skills, references and status history only. No attendance or curriculum tracking. |
| Policies | Guarantee length, pricing, savings split and refunds remain pending owner confirmation (see `BUSINESS_RULES.md`). |

## Scope discipline

- No invented prices, refunds or replacement rules. Disputed values are stored
  as configurable data and labelled as pending.
- No fake dashboard figures: every count comes from records the signed-in role
  may actually see.
- Administrator-approval actions are never queued offline; they require a
  connection so the server can apply current state and the audit trail.
