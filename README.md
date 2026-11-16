# UBER MAIDS WATCH

Offline-first management platform for a domestic-worker placement agency:
verify -> train -> match -> place -> track -> support -> replace when eligible.

The repository contains four parts:

| Part | Location | Technology |
|---|---|---|
| Flutter client (Windows desktop + Android) | `flutter_app/` | Flutter 3.44 / Dart 3.12 |
| REST API + sync engine | `backend/` | Django 5.2, DRF, SimpleJWT, PostgreSQL |
| Client / maid web portal | `backend/portal/` | Django templates, session auth, responsive CSS |
| Deployment | `backend/Dockerfile`, `backend/docker-compose.yml`, `render.yaml` | Docker Compose, Render |

## What works today

- Role-based sign-in for administrators, operations, verification, customer
  care, finance, read-only, domestic workers and family accounts.
- Self-service registration from the public website: a family account creates a
  linked household record, and a worker account creates an applicant record that
  still needs office verification.
- Worker registration, private verification documents, verification decisions,
  status history and availability. Maids can upload documents from the portal or
  the Flutter client; office staff can also upload from the desktop system.
- Client records, service catalogue, bookings, placements, guarantee tracking,
  follow-ups, incidents, replacement cases and payments.
- Offline-first Flutter client: every record the role may see is cached on the
  device; edits are queued in an outbox and synchronised when a connection
  returns.
- Server-rendered public website where families and domestic workers sign in to
  see only their own bookings, placements, follow-ups, payments and replacement
  cases. Staff accounts are deliberately kept out of the portal.
- Server-enforced permissions, per-record optimistic concurrency, idempotent
  mutations, soft-delete tombstones and an audit trail for sensitive actions.
- Branded interface using the supplied shield/house logo and the teal, deep
  teal, gold and charcoal palette.
- No invented policy: guarantee length, prices, refunds and replacement
  eligibility are configurable or explicitly marked as pending owner
  confirmation.

## Quick start (local, SQLite)

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env
$env:DB_ENGINE = "sqlite"
python manage.py migrate
python manage.py seed_demo
python manage.py runserver 127.0.0.1:8000
```

| URL | Purpose |
|---|---|
| <http://127.0.0.1:8000/> | Public landing page |
| <http://127.0.0.1:8000/login/> | Family / domestic-worker / administrator sign-in |
| <http://127.0.0.1:8000/register/> | Self-service family / worker registration |
| <http://127.0.0.1:8000/portal/> | Role-scoped portal dashboard |
| <http://127.0.0.1:8000/portal/office/> | Administrator office console |
| <http://127.0.0.1:8000/portal/documents/> | Maid document upload and download |
| <http://127.0.0.1:8000/api/> | REST API |
| <http://127.0.0.1:8000/api/docs/> | Swagger UI |
| <http://127.0.0.1:8000/api/health/> | Health probe |
| <http://127.0.0.1:8000/admin/> | Django admin (administrator) |

Demo accounts created by `seed_demo` (change or disable before real use):

| Username | Password | Role | Portal access |
|---|---|---|---|
| `admin` | `Admin1234!` | Administrator | Yes — office console |
| `ops` | `Ops1234!` | Operations | No |
| `verify` | `Verify1234!` | Verification | No |
| `care` | `Care1234!` | Customer care | No |
| `finance` | `Finance1234!` | Finance | No |
| `readonly` | `Read1234!` | Read-only | No |
| `family` | `Family1234!` | Client / family | Yes |
| `maid` | `Maid1234!` | Domestic worker | Yes |

The demo family account (Daniel Ssemakula) has bookings, an active placement,
follow-ups, a paid payment and a replacement case. The demo maid account
(Nabirye Aisha) is placed with that family. The demo administrator
(`admin` / `Admin1234!`) signs in to the website and lands in the office console;
operations, verification, customer care, finance and read-only accounts receive a
clear "use the desktop app" notice on portal pages.

## Web portal

The portal is a server-rendered Django site, not Flutter web. It uses Django
session authentication and CSRF protection while the JWT API continues to serve
the desktop and Android clients.

- Only `FAMILY`, `MAID` and `ADMIN` roles may sign in on the website. The
  administrator lands in the office console at `/portal/office/`, with links to
  the Django administration site and the API docs.
- Families and maids can create their own account at `/register/`. A family
  account creates an active `Client`; a maid account creates a `Worker` with
  status `APPLICANT` and verification `PENDING`. Registration never marks a
  worker verified.
- Every query is scoped to the signed-in account's own client or worker record.
- Families can request a booking and open a replacement case; maids can see
  their placement, follow-ups and private document list.
- Maids upload documents at `/portal/documents/` and can download their own
  files. Files use private storage, are limited to PDF/JPG/PNG and 5 MB, and
  every upload/download writes an audit event.
- No staff lists, audit logs or other families' data are exposed. Office staff
  can edit or verify documents, but a maid cannot verify her own upload.
- Static assets are served by WhiteNoise with cache-busting query strings.

## PostgreSQL (supported production database)

Set these in `backend/.env` (see `.env.example`) and run
`python manage.py migrate`:

```
DB_ENGINE=postgresql
DB_NAME=ubermaids
DB_USER=ubermaids
DB_PASSWORD=...
DB_HOST=127.0.0.1
DB_PORT=5432
```

Alternatively set a single `DATABASE_URL=postgres://user:password@host:5432/db`
(Render/Heroku style); it takes precedence over the individual `DB_*` values
and honours `?sslmode=require`.

SQLite is only a development/demo fallback and the database used by the test
suite.

## Live demo (Render)

| Item | Value |
|---|---|
| Public site | <https://uber-maids-watch.onrender.com/> |
| Family / maid sign-in | <https://uber-maids-watch.onrender.com/login/> |
| Create an account | <https://uber-maids-watch.onrender.com/register/> |
| Maid documents | <https://uber-maids-watch.onrender.com/portal/documents/> |
| Android app download | <https://uber-maids-watch.onrender.com/download/android/> |
| Health probe | <https://uber-maids-watch.onrender.com/api/health/> |
| API docs | <https://uber-maids-watch.onrender.com/api/docs/> |
| Django admin | <https://uber-maids-watch.onrender.com/admin/> |

Sign in to the portal with `family` / `Family1234!` or `maid` / `Maid1234!`, or
create a new family/worker account at `/register/`. The administrator
`admin` / `Admin1234!` signs in on the same page and lands in the office console,
which links to the administration site. The Flutter client defaults to this
hosted API, so every role can sign in from the mobile app.

The Android build (`app-release.apk`) is served from `/download/android/` and is
also linked from the landing page and footer. It is built from this repository
with the hosted API as its default, so family, maid, administrator and office
accounts can all sign in immediately. The login screen is pre-filled with the
demo administrator (`admin` / `Admin1234!`) for evaluation; clear those defaults
in `lib/ui/login_screen.dart` before using a build with real accounts. Android
asks the user to allow installs from the browser the first time.

The client is offline-first: after one online sign-in it restores the saved
session without a connection, shows the SQLite cache on the device, queues edits
in an outbox and pushes them when connectivity returns. A brand-new account
still needs one online sign-in before it can be used offline.

The service is on Render's free plan: it sleeps after inactivity, so the first
request can take up to a minute. The free plan has no persistent disk, so private
documents are lost when the service redeploys or restarts; attach a paid disk
before using real identity documents. The free PostgreSQL instance expires on
15 December 2026; move to a paid database and disable `SEED_DEMO` before storing
real records.

## Deploy to Render

The repository includes a Render Blueprint (`render.yaml`) that creates a
PostgreSQL 16 database and a Python web service.

1. Push this repository to GitHub (or GitLab/Bitbucket). Render must be able to
   fetch it: either make it public or install the Render GitHub App for the
   private repository.
2. In Render: **New -> Blueprint**, connect the repository and apply
   `render.yaml`.
3. Render installs dependencies, runs `collectstatic`, applies migrations and
   starts Gunicorn. The first build also seeds the synthetic demo dataset
   because `SEED_DEMO=true` in the Blueprint.
4. Open the generated `https://<service>.onrender.com/` URL and sign in at
   `/login/` with `family` / `Family1234!` or `maid` / `Maid1234!`.
5. For real use, set `SEED_DEMO=false`, remove or change the demo passwords and
   create your own administrator:
   ```bash
   python manage.py shell -c "from core.models import User, Role; u=User.objects.create_superuser('owner', 'owner@example.com', 'a-strong-password'); u.role=Role.ADMIN; u.save()"
   ```
   (Run this in the Render Shell; the Blueprint's `DJANGO_SECRET_KEY` is
   generated automatically.)

Deployment environment variables set by the Blueprint:

| Variable | Value |
|---|---|
| `DATABASE_URL` | Injected from the Render PostgreSQL instance |
| `DJANGO_SECRET_KEY` | Generated by Render |
| `DJANGO_DEBUG` | `False` |
| `DJANGO_ALLOWED_HOSTS` | `.onrender.com` (plus `RENDER_EXTERNAL_HOSTNAME` added automatically) |
| `SECURE_SSL_REDIRECT` | `True` |
| `SEED_DEMO` | `true` for the demo deployment |

Production settings automatically enable HTTPS redirect, secure session and
CSRF cookies, HSTS, `X-Content-Type-Options` and a same-origin referrer policy.
`CSRF_TRUSTED_ORIGINS` is derived from `RENDER_EXTERNAL_HOSTNAME`; add custom
domains there (comma-separated) when you attach one.

### Free-plan caveat

The Render free plan does not support persistent disks. Private verification
documents are stored on the instance filesystem and are lost on redeploy or
restart. For production, upgrade the web service to a paid instance, attach a
disk mounted at `/var/data`, and set:

```
PRIVATE_MEDIA_ROOT=/var/data/private_media
```

Free PostgreSQL instances also expire after the Render free-tier window; move to
a paid database before storing real records.

### Render API key

The Render key is **not** committed. To automate deployments from this machine,
store it in a local environment file outside the repository (for example the
workspace `.env` as `RENDER_API`, or `backend/.env` as `RENDER_API_KEY`). Django
ignores both names; they are only used by deployment tooling.

## Docker Compose

```bash
cd backend
cp .env.example .env      # change every secret
docker compose up --build
```

The API waits for PostgreSQL, runs migrations and collects static files, then
starts Gunicorn on port 8000. Set `SEED_DEMO=true` for a demo database. Private
documents live in the `private_media` volume.

> Docker runtime verification was not possible in the delivery environment
> because no Docker daemon was available. The backend itself was verified on
> SQLite and its PostgreSQL settings were validated statically.

## Flutter client

```bash
cd flutter_app
flutter pub get
flutter run -d windows          # desktop
flutter run                     # Android device / emulator
flutter build apk --release     # installable Android build
```

Build the APK and publish it from the website:

```powershell
flutter build apk --release
Copy-Item build\app\outputs\flutter-apk\app-release.apk `
  ..\backend\portal\downloads\uber-maids-watch.apk
```

The portal serves that file at `/download/android/` with the Android package
content type, and the landing page, footer and call-to-action band link to it.
The release APK uses the default Flutter signing configuration; configure a
private keystore before publishing to Google Play.

The app defaults to the hosted Render API,
`https://uber-maids-watch.onrender.com/api`, so a phone can sign in with no extra
setup. The server address is still editable on the login screen and remembered
per device. For local development, override it at build time:

```bash
flutter run --dart-define=UMW_API_URL=http://127.0.0.1:8000/api
```

Use `http://10.0.2.2:8000/api` on the Android emulator or the computer's LAN
address for a physical phone pointing at a local server. The timeout is 75
seconds so Render's free-plan cold start has time to finish.

Every role can sign in: family, domestic worker, administrator, operations,
verification, customer care, finance and read-only. The client mirrors the
server role matrix when deciding which screens and buttons to show, while the
API re-checks every permission.

The worker detail dialog lists private documents and includes **Choose file &
upload** for office staff. A maid signed in on Android sees only her own worker
record and can upload her own documents; the server rejects uploads for another
worker and blocks a maid from changing the `verified` flag.

The login screen, splash screen, navigation rail and status colours use the
brand palette; the shield/house logo is bundled from `assets/images/`.

### Windows build notes

The project now lives at a short path (`C:\Users\dieve\OneDrive\Desktop\umw`),
so the release build runs directly:

```powershell
cd C:\Users\dieve\OneDrive\Desktop\umw\flutter_app
flutter build windows --release
```

The verified output is `build\windows\x64\runner\Release\uber_maids_watch.exe`.
The executable and window icon use the branded `app_icon.ico`.

MSBuild still has a 260-character limit on intermediate paths. If you move the
project somewhere deeper, the plugin build can fail with
`MSB3491 ... Could not find a part of the path`. In that case either enable
Windows long paths, keep the project short, or map a drive:

```powershell
subst U: "<full path to flutter_app>"
cd U:\
flutter build windows --release
subst U: /D
```

## Tests

Backend (72 tests, including self-registration, administrator web sign-in,
API document permissions and audit checks):

```powershell
cd backend
$env:DJANGO_SETTINGS_MODULE = "config.settings_test"
$env:DB_ENGINE = "sqlite"
.\.venv\Scripts\python.exe manage.py test tests -v 2
```

Flutter (27 tests, including the hosted default URL and multipart upload):

```bash
cd flutter_app
flutter analyze
flutter test
```

Production settings sanity check:

```powershell
cd backend
$env:DJANGO_DEBUG = "False"
$env:DJANGO_SECRET_KEY = "<long random value>"
$env:DB_ENGINE = "sqlite"
.\.venv\Scripts\python.exe manage.py check --deploy
```

## Offline behaviour

| Capability | Offline |
|---|---|
| Sign in with a previously used account | Yes |
| Read every cached record the role may see | Yes |
| Create/edit workers, clients, services, bookings, placements, follow-ups, replacement cases, payments | Yes, queued |
| Verify a worker, confirm a booking, complete a follow-up, review/assign a replacement | No - needs the server |
| Manage users or read the audit trail | No - fetched live, never cached |
| Receive other users' changes | When connected |

Documents and administration data (users, audit log) are never cached. See
[`docs/OFFLINE_SYNC.md`](docs/OFFLINE_SYNC.md) for the protocol.

## Security notes

- Identity documents are stored outside the public media tree and served only
  through authenticated endpoints; every download is audited.
- The Flutter cache contains business and personal data. Secure the device and
  use **Forget this device** on shared hardware.
- Sessions use a 12-hour access token and a 30-day refresh token so a device can
  keep working through a disconnected shift.
- Set a long random `DJANGO_SECRET_KEY`, disable `DJANGO_DEBUG` and use HTTPS
  before any real deployment. Production settings enforce secure cookies,
  HSTS and HTTPS redirects.
- `.env` files are ignored by Git; never commit real credentials.

## Policy still awaiting owner confirmation

The system deliberately does not calculate disputed amounts or decide
replacement eligibility automatically. Guarantee length defaults to 14 days and
every replacement decision is made and recorded by a manager with a reason. The
full list is in [`docs/BUSINESS_RULES.md`](docs/BUSINESS_RULES.md).

## More documentation

- [`docs/IMPLEMENTATION_STATUS.md`](docs/IMPLEMENTATION_STATUS.md) - what is
  built, tested and still blocked.
- [`docs/OFFLINE_SYNC.md`](docs/OFFLINE_SYNC.md) - caching, outbox, conflict
  handling and role scoping.
- [`docs/BUSINESS_RULES.md`](docs/BUSINESS_RULES.md) - values pending owner
  confirmation.
- [`docs/API_OVERVIEW.md`](docs/API_OVERVIEW.md) - endpoint groups and examples.
