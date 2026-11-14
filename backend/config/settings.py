"""
UBER MAIDS WATCH — Django settings.

PostgreSQL is the supported production database.  SQLite is available only as a
development/demo fallback (DB_ENGINE=sqlite) and for the automated test suite.
"""

import os
from datetime import timedelta
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

from django.core.exceptions import ImproperlyConfigured
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")


def split_env(name, default=""):
    """Read a comma-separated environment variable into a clean list."""
    return [item.strip() for item in os.getenv(name, default).split(",") if item.strip()]


SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "unsafe-dev-key-change-me")
DEBUG = os.getenv("DJANGO_DEBUG", "True").lower() == "true"
if not DEBUG and SECRET_KEY == "unsafe-dev-key-change-me":
    raise ImproperlyConfigured(
        "DJANGO_SECRET_KEY must be set to a strong random value when DJANGO_DEBUG is False."
    )

ALLOWED_HOSTS = split_env("DJANGO_ALLOWED_HOSTS", "127.0.0.1,localhost,10.0.2.2")

# Render publishes the service hostname as RENDER_EXTERNAL_HOSTNAME.  Adding it
# automatically means a fresh deployment works before custom domains are set.
RENDER_EXTERNAL_HOSTNAME = os.getenv("RENDER_EXTERNAL_HOSTNAME", "").strip()
if RENDER_EXTERNAL_HOSTNAME and RENDER_EXTERNAL_HOSTNAME not in ALLOWED_HOSTS:
    ALLOWED_HOSTS.append(RENDER_EXTERNAL_HOSTNAME)
if ".onrender.com" not in ALLOWED_HOSTS:
    ALLOWED_HOSTS.append(".onrender.com")

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "django.contrib.humanize",
    # Third-party
    "rest_framework",
    "rest_framework_simplejwt",
    "corsheaders",
    "drf_spectacular",
    # Business apps
    "core",
    "catalog",
    "workers",
    "clients",
    "operations",
    "payments",
    "sync",
    "portal",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
                "portal.context_processors.branding",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
def database_from_url(url):
    """Translate a postgres:// DATABASE_URL (Render/Heroku style) to Django."""
    parsed = urlparse(url)
    if parsed.scheme not in {"postgres", "postgresql"}:
        raise ImproperlyConfigured("DATABASE_URL must use the postgres scheme.")
    query = parse_qs(parsed.query)
    options = {}
    if query.get("sslmode"):
        options["sslmode"] = query["sslmode"][0]
    return {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": unquote(parsed.path.lstrip("/")) or "ubermaids",
        "USER": unquote(parsed.username or ""),
        "PASSWORD": unquote(parsed.password or ""),
        "HOST": parsed.hostname or "",
        "PORT": str(parsed.port or 5432),
        "CONN_MAX_AGE": int(os.getenv("DB_CONN_MAX_AGE", "60")),
        "OPTIONS": options,
    }


DATABASE_URL = os.getenv("DATABASE_URL", "").strip()
if os.getenv("DB_ENGINE", "postgresql").lower() == "sqlite":
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": os.getenv("SQLITE_PATH", str(BASE_DIR / "db.sqlite3")),
        }
    }
elif DATABASE_URL:
    DATABASES = {"default": database_from_url(DATABASE_URL)}
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": os.getenv("DB_NAME", "ubermaids"),
            "USER": os.getenv("DB_USER", "postgres"),
            "PASSWORD": os.getenv("DB_PASSWORD", "postgres"),
            "HOST": os.getenv("DB_HOST", "127.0.0.1"),
            "PORT": os.getenv("DB_PORT", "5432"),
            "CONN_MAX_AGE": int(os.getenv("DB_CONN_MAX_AGE", "60")),
        }
    }

AUTH_USER_MODEL = "core.User"

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator", "OPTIONS": {"min_length": 8}},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "Africa/Kampala"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STORAGES = {
    "default": {
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    },
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedStaticFilesStorage",
    },
}
MEDIA_URL = "media/"
MEDIA_ROOT = BASE_DIR / "media"

# Private verification documents are stored outside the public media tree and
# are served only through an authorised API view.
PRIVATE_MEDIA_ROOT = Path(
    os.getenv("PRIVATE_MEDIA_ROOT") or (BASE_DIR / "private_media")
)
PRIVATE_MEDIA_ROOT.mkdir(parents=True, exist_ok=True)

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": ("rest_framework.permissions.IsAuthenticated",),
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": 100,
    "DEFAULT_RENDERER_CLASSES": ("rest_framework.renderers.JSONRenderer",),
}

SIMPLE_JWT = {
    # Staff work long shifts and may be offline for hours.  A long access token
    # keeps cached sessions usable while the device is disconnected; the app
    # refreshes it whenever connectivity returns.
    "ACCESS_TOKEN_LIFETIME": timedelta(hours=12),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=30),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": False,
    "UPDATE_LAST_LOGIN": True,
}

SPECTACULAR_SETTINGS = {
    "TITLE": "UBER MAIDS WATCH API",
    "DESCRIPTION": (
        "REST API for the UBER MAIDS WATCH management platform. "
        "The Flutter client mirrors data into an on-device database so staff can "
        "keep working while offline."
    ),
    "VERSION": "0.2.0",
    "SERVE_INCLUDE_SCHEMA": False,
    "COMPONENT_SPLIT_REQUEST": True,
    "SECURITY": [{"jwtAuth": []}],
    "ENUM_NAME_OVERRIDES": {
        # Incident.category and ReplacementCase.problem_category share the same
        # code set; catalog.Service.category is a different set.
        "IncidentCategoryEnum": "operations.models.INCIDENT_CATEGORY_CHOICES",
        "ServiceCategoryEnum": "catalog.models.SERVICE_CATEGORY_CHOICES",
    },
}

CORS_ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.getenv("CORS_ALLOWED_ORIGINS", "").split(",")
    if origin.strip()
]
CORS_ALLOW_ALL_ORIGINS = DEBUG and not CORS_ALLOWED_ORIGINS

# CSRF protection for the server-rendered portal.  Render terminates TLS and
# forwards the original scheme, so the public HTTPS origin must be trusted.
CSRF_TRUSTED_ORIGINS = split_env("CSRF_TRUSTED_ORIGINS")
if RENDER_EXTERNAL_HOSTNAME:
    render_origin = f"https://{RENDER_EXTERNAL_HOSTNAME}"
    if render_origin not in CSRF_TRUSTED_ORIGINS:
        CSRF_TRUSTED_ORIGINS.append(render_origin)

if not DEBUG:
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
    SECURE_SSL_REDIRECT = (
        os.getenv("SECURE_SSL_REDIRECT", "true").lower() == "true"
    )
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    SESSION_COOKIE_HTTPONLY = True
    SECURE_CONTENT_TYPE_NOSNIFF = True
    SECURE_REFERRER_POLICY = "same-origin"
    SECURE_HSTS_SECONDS = int(os.getenv("SECURE_HSTS_SECONDS", "31536000"))
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
    SECURE_HSTS_PRELOAD = (
        os.getenv("SECURE_HSTS_PRELOAD", "true").lower() == "true"
    )
    X_FRAME_OPTIONS = "DENY"

# ---------------------------------------------------------------------------
# Business policy defaults (all overridable through core.AppSetting)
# ---------------------------------------------------------------------------
GUARANTEE_DAYS_DEFAULT = int(os.getenv("GUARANTEE_DAYS_DEFAULT", "14"))
FOLLOW_UP_WINDOW_DAYS_DEFAULT = int(os.getenv("FOLLOW_UP_WINDOW_DAYS_DEFAULT", "7"))

# Upload limits for private verification documents.
MAX_DOCUMENT_BYTES = int(os.getenv("MAX_DOCUMENT_BYTES", str(5 * 1024 * 1024)))
ALLOWED_DOCUMENT_EXTENSIONS = {".pdf", ".jpg", ".jpeg", ".png"}

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {"console": {"class": "logging.StreamHandler"}},
    "root": {"handlers": ["console"], "level": os.getenv("LOG_LEVEL", "INFO")},
}
