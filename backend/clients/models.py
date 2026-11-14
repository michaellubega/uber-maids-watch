from django.conf import settings
from django.db import models

from core.models import SyncableModel
from core.numbering import next_number


class Client(SyncableModel):
    """Household / customer record.  Only necessary contact data is stored."""

    STATUS_CHOICES = [("ACTIVE", "Active"), ("INACTIVE", "Inactive")]

    client_number = models.CharField(max_length=20, unique=True, blank=True)
    full_name = models.CharField(max_length=160)
    phone = models.CharField(max_length=25)
    email = models.EmailField(blank=True)
    area = models.CharField(max_length=160, help_text="General service area / location")
    preferred_contact = models.CharField(
        max_length=20,
        choices=[("PHONE", "Phone call"), ("WHATSAPP", "WhatsApp"), ("SMS", "SMS"), ("EMAIL", "Email")],
        default="PHONE",
    )
    notes = models.TextField(blank=True)
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default="ACTIVE")
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="client_profile",
        help_text="Optional self-service family account.",
    )

    def save(self, *args, **kwargs):
        if not self.client_number:
            self.client_number = next_number("client")
        super().save(*args, **kwargs)

    def __str__(self) -> str:
        return f"{self.client_number} — {self.full_name}"
