from django.contrib import admin

from catalog.models import Service


@admin.register(Service)
class ServiceAdmin(admin.ModelAdmin):
    list_display = ("name", "category", "pricing_type", "active", "public_visibility")
    list_filter = ("category", "active", "public_visibility")
    search_fields = ("name", "description")
