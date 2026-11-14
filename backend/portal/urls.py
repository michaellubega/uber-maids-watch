from django.urls import path

from portal import views

app_name = "portal"

urlpatterns = [
    path("", views.landing, name="landing"),
    path("login/", views.login_view, name="login"),
    path("logout/", views.logout_view, name="logout"),
    path("portal/", views.dashboard, name="dashboard"),
    path("portal/bookings/", views.bookings, name="bookings"),
    path("portal/bookings/new/", views.booking_new, name="booking_new"),
    path("portal/placements/", views.placements, name="placements"),
    path(
        "portal/placements/<uuid:pk>/",
        views.placement_detail,
        name="placement_detail",
    ),
    path("portal/follow-ups/", views.followups, name="followups"),
    path("portal/payments/", views.payments, name="payments"),
    path("portal/replacements/", views.replacements, name="replacements"),
    path("portal/replacements/new/", views.replacement_new, name="replacement_new"),
    path("portal/profile/", views.profile, name="profile"),
]
