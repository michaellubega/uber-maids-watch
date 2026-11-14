from django.urls import include, path
from rest_framework.routers import DefaultRouter

from core.views import AuditLogViewSet, UserViewSet

router = DefaultRouter()
router.register("users", UserViewSet, basename="user")
router.register("audit-logs", AuditLogViewSet, basename="audit-log")

urlpatterns = [path("", include(router.urls))]
