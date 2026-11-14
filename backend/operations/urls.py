from django.urls import include, path
from rest_framework.routers import DefaultRouter

from operations.views import (
    BookingViewSet,
    FollowUpViewSet,
    IncidentViewSet,
    PlacementViewSet,
    ReplacementCaseViewSet,
)

router = DefaultRouter()
router.register("bookings", BookingViewSet, basename="booking")
router.register("placements", PlacementViewSet, basename="placement")
router.register("follow-ups", FollowUpViewSet, basename="follow-up")
router.register("incidents", IncidentViewSet, basename="incident")
router.register("replacement-cases", ReplacementCaseViewSet, basename="replacement-case")

urlpatterns = [path("", include(router.urls))]
