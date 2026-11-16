# Build status

This file is superseded. For the current, verified state of the delivery see
[`IMPLEMENTATION_STATUS.md`](IMPLEMENTATION_STATUS.md).

Short version:

- Django backend and client/maid web portal complete for the MVP scope;
  72 tests passing, including self-registration, private document upload, the
  hosted APK download and administrator web sign-in.
- Flutter client complete for the MVP scope; `flutter analyze` clean, 27 tests
  passing, Windows release and Android APK builds verified. The mobile app
  defaults to the hosted Render API, supports document upload for a worker, and
  keeps working offline after one online sign-in. The APK is downloaded from
  `/download/android/` on the public website.
- PostgreSQL is the supported production database but was not run in the
  delivery environment; SQLite was used for verification and tests.
- Docker Compose could not be started (no daemon available).
- Render Blueprint (`render.yaml`), `backend/build.sh` and production settings
  are ready and the service is live at <https://uber-maids-watch.onrender.com>
  (free plan; PostgreSQL expires on 15 December 2026).
- Business rules above are still pending owner confirmation - see
  [`BUSINESS_RULES.md`](BUSINESS_RULES.md).

Do not enter real identity documents or sensitive family data until the
deployment has HTTPS, a strong `DJANGO_SECRET_KEY`, a real PostgreSQL instance,
persistent private-document storage and an access-control review.
