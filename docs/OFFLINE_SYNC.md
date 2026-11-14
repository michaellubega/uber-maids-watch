# Offline and sync design

The client is offline-first: it holds a local mirror of every record the signed-in
role is allowed to see, keeps working while disconnected, and reconciles with the
server when a connection returns.

## What is cached

Cached per device and per user account:

- services, workers, clients, bookings, placements, follow-ups, incidents,
  replacement cases and payments.

Role scoping happens on the server before anything is sent, so the cache never
contains records outside the role's visibility:

| Role | Sees |
|---|---|
| Administrator, operations, verification, customer care, finance, read-only | All staff-visible records for their permissions |
| Domestic worker (`MAID`) | Own worker record and own placements/follow-ups |
| Family (`FAMILY`) | Own client record, bookings, placements, follow-ups, replacement cases and payments; a minimal worker view |

Never cached:

- worker identity documents and verification files;
- user accounts and the audit trail;
- passwords and tokens in the cache payload (tokens live in secure storage).

## Cache location

`LocalDatabase` writes one JSON file per user:

```
<application support directory>/<sanitised user key>/cache.json
```

The file contains records, the pull cursor, the outbox, conflicts, rejected
mutations and tombstones. Writes go to a temporary file and are then renamed, so
an interrupted write cannot leave a truncated cache. The store is deliberately
behind a small API so it can be replaced by SQLite/Drift later without touching
the screens.

Signing out keeps the cache so a shift can start offline. **Clear cached
records** discards the cache and outbox and rebuilds from the server. **Forget
this device** deletes the cache and signs out.

## Pull

```
GET /api/sync/pull/?since=<seq>&limit=<n>
```

- `since` is the last global `change_seq` the device has stored (default `0`).
- `limit` defaults to 500 and is capped at 1000.
- Only entities readable by the role and rows inside that role's scope are
  considered.
- Response:

```json
{
  "server_time": "2026-11-14T19:25:22+00:00",
  "since": 0,
  "next_since": 5,
  "has_more": true,
  "changes": [
    {
      "entity": "worker",
      "id": "…",
      "deleted": false,
      "change_seq": 3,
      "data": { "id": "…", "server_version": 1, "…": "…" }
    }
  ]
}
```

Changes are ordered by `change_seq` across all entities. The client stores
`next_since` as its cursor and repeats the pull while `has_more` is true.

Deleted records are delivered as tombstones (`deleted: true`). The client keeps
the tombstone and hides the record, so a delete is not undone by a later pull.

## Push

```
POST /api/sync/push/
{ "mutations": [ { … }, … ] }   // at most 200 per request
```

Mutation fields:

| Field | Meaning |
|---|---|
| `mutation_id` | Client-generated UUID, the idempotency key |
| `entity` | `service`, `worker`, `client`, `booking`, `placement`, `follow_up`, `incident`, `replacement_case`, `payment` |
| `id` | Record UUID |
| `operation` | `upsert` or `delete` |
| `base_version` | Last `server_version` the device saw (`0` for a new record) |
| `data` | Fields to write; server-managed fields are ignored |

Each mutation is processed in its own savepoint, so one rejected record cannot
abort the rest of the batch. Each result carries the same `mutation_id` and one
status:

| Status | Meaning | Client action |
|---|---|---|
| `applied` | Written; the server record is returned | Replace the local copy, clear the outbox entry |
| `duplicate` | Same `mutation_id` already processed | Treat as applied using the stored result |
| `conflict` | `base_version` is stale | Keep the local edit as a conflict for the user to resolve |
| `rejected` | Validation or permission failure, with `errors` | Mark the outbox entry rejected and show the reason |

A conflict is returned with HTTP 200. The client must inspect each result's
`status`; it must not treat a 200 as blanket success.

The client pushes before it pulls, so its own writes come back with server
versions and sequences in the same cycle.

## Conflict resolution

A conflict means the record changed on the server after this device last pulled
it. The local edit is never silently discarded:

1. The local record keeps the user's values and stores the server copy in
   `server_data`.
2. The sync screen lists the conflicting record with the server version summary.
3. The user chooses:
   - **Keep this device** — the outbox mutation is re-based onto the current
     server version and retried on the next sync.
   - **Use the server copy** — the local edit and mutation are dropped and the
     cached record is replaced by the server copy.

Server-wins is the default for every unattended path; a human chooses whenever
two edits genuinely collide.

## Offline actions

| Action | Offline behaviour |
|---|---|
| Sign in with a previously used account | Allowed from the stored session |
| Browse and search every cached record | Allowed |
| Create/edit workers, clients, services, bookings, placements, follow-ups, incidents, replacement cases, payments | Saved locally and queued |
| Delete a record | Soft delete locally and queued as a tombstone |
| Verify a worker | Requires the server |
| Confirm a booking | Requires the server |
| Complete a follow-up | Requires the server |
| Review eligibility, assign a backup worker or resolve a replacement | Requires the server |
| Manage users or read the audit trail | Requires the server |

Administrator-approval actions are online-only because the outcome depends on
current server state (availability, verification, permissions) and must be
audited at the moment it happens. The UI explains this before disabling the
action instead of failing after the fact.

Client-created records (for example a family booking request) are permitted to
sync, but a family account cannot edit an existing record; the server rejects
such a mutation with `rejected`.

## Failure handling

- Network failure while pushing leaves the outbox intact; the sync screen shows
  the error and the pending count.
- Rejected mutations stay visible with the server error, and can be retried or
  discarded after the data is fixed.
- A 401 triggers one token refresh and retry. If refresh fails the session is
  ended and the sign-in screen appears; the cache is kept.
- Interrupted pulls resume from the stored cursor on the next attempt.

## Security caveats

- The cache is plain JSON containing business and personal data. It is protected
  by the operating-system account, not by encryption at rest. Use full-disk
  encryption and **Forget this device** on shared or lost hardware.
- Tokens are held in secure storage, not in the cache file.
- Documents never enter the cache; opening one requires a connection and an
  authorised request.
- The server is authoritative for permissions. Hiding a button in the client is
  a convenience, not a control.

## Sequence of a sync

```
outbox empty?  ── yes ──┐
      │ no              │
      ▼                 │
POST /sync/push/        │
      │                 │
      ▼                 ▼
apply results ───► GET /sync/pull/?since=cursor
                        │
                        ▼
                merge changes, store cursor
                        │
                        ▼
                  has_more? ── yes ──► repeat pull
                        │ no
                        ▼
                  flush cache, notify UI
```
