"""Core domain: staff accounts, audit trail and sync bookkeeping."""

import uuid

from django.contrib.auth.models import AbstractUser
from django.db import models
from django.utils import timezone


class Role(models.TextChoices):
    ADMIN = "ADMIN", "Owner / Administrator"
    OPERATIONS = "OPERATIONS", "Operations Manager"
    VERIFICATION = "VERIFICATION", "Recruitment / Verification Officer"
    CUSTOMER_CARE = "CUSTOMER_CARE", "Customer Care Officer"
    FINANCE = "FINANCE", "Finance Officer"
    READONLY = "READONLY", "Read-only Manager"
    MAID = "MAID", "Domestic Worker"
    FAMILY = "FAMILY", "Client / Family"


STAFF_ROLES = {
    Role.ADMIN,
    Role.OPERATIONS,
    Role.VERIFICATION,
    Role.CUSTOMER_CARE,
    Role.FINANCE,
    Role.READONLY,
}


class User(AbstractUser):
    """Individual staff or self-service account.

    UUID primary keys keep device-generated records consistent when the Flutter
    client creates data while offline.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    role = models.CharField(max_length=20, choices=Role.choices, default=Role.FAMILY)
    phone_number = models.CharField(max_length=25, blank=True)

    @property
    def is_staff_role(self) -> bool:
        return self.role in STAFF_ROLES

    @property
    def display_name(self) -> str:
        return self.get_full_name() or self.username


class AppSetting(models.Model):
    """Configurable business rule.

    Values that the owner has not confirmed are stored here with
    ``confirmed=False`` so the UI can show "pending owner confirmation".
    """

    key = models.CharField(max_length=80, unique=True)
    value = models.JSONField(default=dict, blank=True)
    description = models.CharField(max_length=255, blank=True)
    confirmed = models.BooleanField(default=False)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return self.key


class Counter(models.Model):
    """Monotonic counter used to generate human-readable reference numbers."""

    name = models.CharField(max_length=40, unique=True)
    value = models.PositiveIntegerField(default=0)

    def __str__(self) -> str:
        return f"{self.name}:{self.value}"


class SyncSequence(models.Model):
    """Single-row global sequence for the offline sync change log."""

    id = models.PositiveSmallIntegerField(primary_key=True, default=1)
    value = models.BigIntegerField(default=0)

    def __str__(self) -> str:
        return f"sync-sequence:{self.value}"


class SyncableModel(models.Model):
    """Base class for records mirrored to the Flutter client.

    Every save receives a globally increasing ``change_seq``.  Clients pull
    records in change order and can therefore resume from a cursor without
    missing updates.  Deletes are soft tombstones so offline devices learn about
    them too.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    server_version = models.PositiveIntegerField(default=1)
    change_seq = models.BigIntegerField(default=0, db_index=True, editable=False)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        abstract = True
        ordering = ["-updated_at"]

    @property
    def is_deleted(self) -> bool:
        return self.deleted_at is not None

    def save(self, *args, **kwargs):
        from core.sequences import next_change_seq

        if self._state.adding:
            self.server_version = 1
        else:
            self.server_version = (self.server_version or 1) + 1
        self.change_seq = next_change_seq()
        super().save(*args, **kwargs)

    def delete(self, using=None, keep_parents=False):
        """Soft delete: keep history and tell connected devices about removal."""
        from core.sequences import next_change_seq

        self.deleted_at = timezone.now()
        self.server_version = (self.server_version or 1) + 1
        self.change_seq = next_change_seq()
        # Bypass the version bump in save() because we already applied it.
        models.Model.save(
            self,
            using=using,
            update_fields=[
                "deleted_at",
                "server_version",
                "change_seq",
                "updated_at",
            ],
        )


class ProcessedMutation(models.Model):
    """Idempotency ledger for offline mutations pushed by devices."""

    mutation_id = models.UUIDField(primary_key=True)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="processed_mutations")
    entity = models.CharField(max_length=40)
    record_id = models.UUIDField()
    response = models.JSONField(default=dict)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class AuditLog(models.Model):
    """Append-only record of security and business-sensitive actions."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    actor = models.ForeignKey(
        User, null=True, blank=True, on_delete=models.SET_NULL, related_name="audit_events"
    )
    actor_name = models.CharField(max_length=150, blank=True)
    action = models.CharField(max_length=80)
    entity = models.CharField(max_length=80, blank=True)
    entity_id = models.CharField(max_length=80, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["action", "created_at"]),
            models.Index(fields=["entity", "entity_id"]),
        ]

    def __str__(self) -> str:
        return f"{self.created_at:%Y-%m-%d %H:%M} {self.actor_name or 'system'} {self.action}"
