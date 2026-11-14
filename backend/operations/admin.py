from django.contrib import admin

from operations.models import Booking, FollowUp, Incident, Placement, ReplacementCase


@admin.register(Booking)
class BookingAdmin(admin.ModelAdmin):
    list_display = ("booking_number", "client", "service", "status", "requested_start_date")
    list_filter = ("status", "service")
    search_fields = ("booking_number", "client__full_name", "client__client_number")


@admin.register(Placement)
class PlacementAdmin(admin.ModelAdmin):
    list_display = ("placement_number", "client", "worker", "status", "start_date", "guarantee_end_date")
    list_filter = ("status",)
    search_fields = ("placement_number", "client__full_name", "worker__full_name")


@admin.register(FollowUp)
class FollowUpAdmin(admin.ModelAdmin):
    list_display = ("placement", "due_date", "completed_at", "outcome")
    list_filter = ("outcome", "contact_method")


@admin.register(Incident)
class IncidentAdmin(admin.ModelAdmin):
    list_display = ("placement", "category", "status", "reported_at")
    list_filter = ("category", "status")


@admin.register(ReplacementCase)
class ReplacementCaseAdmin(admin.ModelAdmin):
    list_display = ("case_number", "client", "original_worker", "status", "eligibility_decision")
    list_filter = ("status", "eligibility_decision", "problem_category")
