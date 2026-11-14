from django.contrib import admin
from django.urls import include, path
from drf_spectacular.views import (
    SpectacularAPIView,
    SpectacularSwaggerView,
)

from core.views import DashboardSummaryView, HealthView, MeView
from sync.views import PullView, PushView

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/health/", HealthView.as_view(), name="health"),
    path("api/auth/", include("core.auth_urls")),
    path("api/auth/me/", MeView.as_view(), name="me"),
    path("api/dashboard/summary/", DashboardSummaryView.as_view(), name="dashboard-summary"),
    path("api/sync/pull/", PullView.as_view(), name="sync-pull"),
    path("api/sync/push/", PushView.as_view(), name="sync-push"),
    path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
    path(
        "api/docs/",
        SpectacularSwaggerView.as_view(url_name="schema"),
        name="swagger-ui",
    ),
    path("api/", include("catalog.urls")),
    path("api/", include("workers.urls")),
    path("api/", include("clients.urls")),
    path("api/", include("operations.urls")),
    path("api/", include("payments.urls")),
    path("api/", include("core.urls")),
    path("", include("portal.urls")),
]
