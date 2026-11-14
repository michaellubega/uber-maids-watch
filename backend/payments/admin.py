from django.contrib import admin

from payments.models import Payment


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = (
        "receipt_reference",
        "client",
        "amount_ugx",
        "currency",
        "payment_method",
        "status",
        "paid_at",
    )
    list_filter = ("status", "payment_method")
    search_fields = ("receipt_reference", "client__full_name", "reference")
