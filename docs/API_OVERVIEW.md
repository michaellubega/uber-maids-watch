# API overview

Base URL: `/api/`. All routes except `/health/` and `/auth/token/` require a
Bearer JWT: `Authorization: Bearer <access>`. Full interactive documentation is
served at `/api/docs/` (Swagger UI) from the schema at `/api/schema/`.

## Auth and platform

| Method | Path | Roles | Notes |
|---|---|---|---|
| GET | `health/` | public | Liveness and database check |
| POST | `auth/token/` | public | Returns `access` (12 h) and `refresh` (30 d) |
| POST | `auth/token/refresh/` | public | New access token |
| GET | `auth/me/` | authenticated | User, role and capability map |
| GET | `dashboard/summary/` | staff, maid, family | Role-scoped counts |
| GET | `sync/pull/?since=&limit=` | authenticated | Changes in global sequence order |
| POST | `sync/push/` | authenticated | Up to 200 mutations per call |

## Records

Standard DRF list/create/retrieve/update/delete routes. Reads are role-scoped;
writes follow the role matrix.

| Path | Notes |
|---|---|
| `services/` | Catalogue with optional price range |
| `workers/` | Worker records |
| `worker-documents/` | Upload to private storage |
| `worker-references/` | Verification references |
| `verification-checks/` | Individual checks |
| `clients/` | Family records |
| `bookings/` | Requests |
| `placements/` | Placements and guarantee window |
| `follow-ups/` | Support calls |
| `incidents/` | Support incidents |
| `replacement-cases/` | Replacement workflow |
| `payments/` | Payment records |
| `users/` | Administrators only |
| `audit-logs/` | Administrators only, read-only |

## Workflow actions

These are online-only and write an audit entry.

| Method | Path | Effect |
|---|---|---|
| POST | `workers/{id}/verify/` | Record a verification decision |
| GET | `workers/{id}/history/` | Status history |
| GET | `workers/{id}/documents/` | List documents for a worker |
| GET | `worker-documents/{id}/download/` | Authorised, audited download |
| POST | `bookings/{id}/confirm/` | Confirm a booking |
| GET | `placements/{id}/guarantee/` | Guarantee status |
| POST | `follow-ups/{id}/complete/` | Record an outcome, optionally create the next follow-up |
| POST | `replacement-cases/{id}/review/` | Eligibility decision with reason |
| POST | `replacement-cases/{id}/assign/` | Assign a backup worker and create the replacement placement |
| POST | `replacement-cases/{id}/resolve/` | Close the case |

## Conventional endpoints

`GET`, `POST`, `PATCH` and `DELETE` on the record routes behave as standard DRF
endpoints with:

- UUID identifiers;
- paginated list responses (`results`, `count`, `next`, `previous`);
- soft deletes (records disappear from reads but remain for audit);
- server-managed `server_version` and `change_seq` fields.

For offline reconciliation always prefer `/sync/pull/` and `/sync/push/` over
per-record endpoints; the sync endpoints return tombstones and version metadata
the cache needs.
