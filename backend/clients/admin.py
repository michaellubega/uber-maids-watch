from django.contrib import admin

from clients.models import Client


@admin.register(Client)
class ClientAdmin(admin.ModelAdmin):
    list_display = ("client_number", "full_name", "phone", "area", "status")
    list_filter = ("status", "preferred_contact")
    search_fields = ("client_number", "full_name", "phone", "area")
