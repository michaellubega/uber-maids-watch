from django.db import models
from django.utils import timezone

from clients.models import Client
from core.models import SyncableModel
from core.numbering import next_number
from operations.models import Booking, Placement


class Payment(SyncableModel):
    STATUS_CHOICES = [
        ("PENDING", "Pending"),
        ("PARTIAL", "Partially paid"),
        ("PAID", "Paid"),
        ("REFUNDED", "Refunded"),
        ("FAILED", "Failed"),
    ]
    METHOD_CHOICES = [
        ("CASH", "Cash"),
        ("MOBILE_MONEY", "Mobile money"),
        ("BANK", "Bank transfer"),
        ("OTHER", "Other"),
    ]

    receipt_reference = models.CharField(max_length=20, unique=True, blank=True)
    client = models.ForeignKey(Client, on_delete=models.PROTECT, related_name="payments")
    booking = models.ForeignKey(
        Booking, null=True, blank=True, on_delete=models.SET_NULL, related_name="payments"
    )
    placement = models.ForeignKey(
        Placement, null=True, blank=True, on_delete=models.SET_NULL, related_name="payments"
    )
    amount_ugx = models.DecimalField(max_digits=12, decimal_places=2)
    currency = models.CharField(max_length=3, default="UGX")
    payment_method = models.CharField(max_length=20, choices=METHOD_CHOICES, default="CASH")
    reference = models.CharField(max_length=100, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="PAID")
    paid_at = models.DateTimeField(null=True, blank=True)
    notes = models.TextField(blank=True)
    recorded_by_name = models.CharField(max_length=150, blank=True)

    class Meta(SyncableModel.Meta):
        ordering = ["-created_at"]

    def save(self, *args, **kwargs):
        if not self.receipt_reference:
            self.receipt_reference = next_number("payment")
        if self.status == "PAID" and self.paid_at is None:
            self.paid_at = timezone.now()
        super().save(*args, **kwargs)

    @property
    def is_outstanding(self) -> bool:
        return self.status in {"PENDING", "PARTIAL"}

    def __str__(self) -> str:
        return f"{self.receipt_reference} — {self.client.full_name} — {self.amount_ugx}"
