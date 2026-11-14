#!/bin/sh
set -e

python manage.py migrate --noinput

# Django admin and the API documentation need their static assets collected.
python manage.py collectstatic --noinput

if [ "${SEED_DEMO:-false}" = "true" ]; then
  python manage.py seed_demo
fi

exec "$@"
