#!/usr/bin/env bash
# Render build script for UBER MAIDS WATCH.
# Runs from the repository root directory configured in render.yaml (backend/).
set -o errexit
set -o pipefail

echo "==> Installing Python dependencies"
pip install --upgrade pip
pip install -r requirements.txt

echo "==> Collecting static files (Django admin, API docs, portal)"
python manage.py collectstatic --noinput

echo "==> Applying database migrations"
python manage.py migrate --noinput

# The demo dataset is synthetic.  Enable SEED_DEMO only for evaluation
# deployments and disable it (and change the demo passwords) for real use.
# Accept "true"/"True" so Blueprint values written either way still work.
seed_demo=$(printf '%s' "${SEED_DEMO:-false}" | tr '[:upper:]' '[:lower:]')
if [ "$seed_demo" = "true" ]; then
  echo "==> Seeding synthetic demo dataset"
  python manage.py seed_demo
fi

echo "==> Build complete"
