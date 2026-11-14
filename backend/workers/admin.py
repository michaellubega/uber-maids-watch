from django.contrib import admin

from workers.models import (
    VerificationCheck,
    Worker,
    WorkerDocument,
    WorkerReference,
    WorkerStatusHistory,
)


class WorkerDocumentInline(admin.TabularInline):
    model = WorkerDocument
    extra = 0


@admin.register(Worker)
class WorkerAdmin(admin.ModelAdmin):
    list_display = ("worker_number", "full_name", "phone", "area", "status", "verification_status")
    list_filter = ("status", "verification_status", "service_categories")
    search_fields = ("worker_number", "full_name", "phone", "area")
    inlines = [WorkerDocumentInline]


admin.site.register(WorkerReference)
admin.site.register(VerificationCheck)
admin.site.register(WorkerStatusHistory)
