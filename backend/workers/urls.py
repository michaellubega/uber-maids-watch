from django.urls import include, path
from rest_framework.routers import DefaultRouter

from workers.views import (
    VerificationCheckViewSet,
    WorkerDocumentDownloadView,
    WorkerDocumentViewSet,
    WorkerReferenceViewSet,
    WorkerViewSet,
)

router = DefaultRouter()
router.register("workers", WorkerViewSet, basename="worker")
router.register("worker-documents", WorkerDocumentViewSet, basename="worker-document")
router.register("worker-references", WorkerReferenceViewSet, basename="worker-reference")
router.register("verification-checks", VerificationCheckViewSet, basename="verification-check")

urlpatterns = [
    path(
        "worker-documents/<uuid:pk>/download/",
        WorkerDocumentDownloadView.as_view(),
        name="worker-document-download",
    ),
    path("", include(router.urls)),
]
