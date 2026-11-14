from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from core.models import AppSetting, AuditLog, Counter, SyncSequence, User


@admin.register(User)
class CustomUserAdmin(UserAdmin):
    fieldsets = UserAdmin.fieldsets + (
        ("Business access", {"fields": ("role", "phone_number")}),
    )
    list_display = ("username", "email", "role", "phone_number", "is_active")
    list_filter = ("role", "is_active")


@admin.register(AppSetting)
class AppSettingAdmin(admin.ModelAdmin):
    list_display = ("key", "confirmed", "updated_at")
    search_fields = ("key", "description")


@admin.register(AuditLog)
class AuditLogAdmin(admin.ModelAdmin):
    list_display = ("created_at", "actor_name", "action", "entity", "entity_id")
    list_filter = ("action", "entity")
    readonly_fields = [field.name for field in AuditLog._meta.fields]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


admin.site.register(Counter)
admin.site.register(SyncSequence)
