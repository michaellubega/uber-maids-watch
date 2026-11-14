import uuid

from django.conf import settings
from django.db import models

from core.models import SyncableModel
from core.numbering import next_number
from core.storage import private_storage


class Worker(SyncableModel):
    """Domestic worker profile and verification state."""

    STATUS_CHOICES = [
        ("APPLICANT", "Applicant"),
        ("DOCUMENTS_PENDING", "Documents pending"),
        ("UNDER_VERIFICATION", "Under verification"),
        ("VERIFIED", "Verified"),
        ("TRAINING", "Training"),
        ("AVAILABLE", "Available"),
        ("RESERVED", "Reserved"),
        ("PLACED", "Placed"),
        ("ON_LEAVE", "On leave"),
        ("SUSPENDED", "Suspended"),
        ("INACTIVE", "Inactive"),
    ]
    VERIFICATION_CHOICES = [
        ("PENDING", "Pending"),
        ("IN_PROGRESS", "In progress"),
        ("VERIFIED", "Verified"),
        ("EXCEPTION", "Approved exception"),
        ("REJECTED", "Rejected"),
    ]

    worker_number = models.CharField(max_length=20, unique=True, blank=True)
    full_name = models.CharField(max_length=160)
    phone = models.CharField(max_length=25)
    area = models.CharField(max_length=160, help_text="General residential area")
    date_of_birth = models.DateField(null=True, blank=True)
    photo = models.ImageField(
        storage=private_storage, upload_to="worker_photos/%Y/%m/", blank=True, null=True
    )
    national_id_type = models.CharField(max_length=60, blank=True)
    national_id_number = models.CharField(max_length=80, blank=True)
    emergency_contact_name = models.CharField(max_length=160, blank=True)
    emergency_contact_phone = models.CharField(max_length=25, blank=True)
    skills = models.JSONField(default=list, blank=True)
    languages = models.JSONField(default=list, blank=True)
    service_categories = models.JSONField(default=list, blank=True)
    experience_years = models.PositiveSmallIntegerField(default=0)
    expected_salary_ugx = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )
    availability = models.CharField(max_length=30, blank=True)
    status = models.CharField(max_length=25, choices=STATUS_CHOICES, default="APPLICANT")
    verification_status = models.CharField(
        max_length=20, choices=VERIFICATION_CHOICES, default="PENDING"
    )
    verified_at = models.DateTimeField(null=True, blank=True)
    verified_by_name = models.CharField(max_length=150, blank=True)
    exception_reason = models.TextField(blank=True)
    notes = models.TextField(blank=True)
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="worker_profile",
        help_text="Optional self-service worker account.",
    )

    class Meta(SyncableModel.Meta):
        ordering = ["full_name"]

    def save(self, *args, **kwargs):
        if not self.worker_number:
            self.worker_number = next_number("worker")
        super().save(*args, **kwargs)

    def __str__(self) -> str:
        return f"{self.worker_number} — {self.full_name}"


class WorkerReference(models.Model):
    """Family / next-of-kin contact.  Sensitive; never exposed publicly."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    worker = models.ForeignKey(
        Worker, on_delete=models.CASCADE, related_name="references"
    )
    full_name = models.CharField(max_length=160)
    relationship = models.CharField(max_length=80, blank=True)
    phone = models.CharField(max_length=25)
    address = models.TextField(blank=True)
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)


class VerificationCheck(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    worker = models.ForeignKey(
        Worker, on_delete=models.CASCADE, related_name="verification_checks"
    )
    name = models.CharField(max_length=160)
    status = models.CharField(
        max_length=20,
        choices=[("PENDING", "Pending"), ("PASSED", "Passed"), ("FAILED", "Failed")],
        default="PENDING",
    )
    notes = models.TextField(blank=True)
    checked_by_name = models.CharField(max_length=150, blank=True)
    checked_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)


class WorkerStatusHistory(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    worker = models.ForeignKey(
        Worker, on_delete=models.CASCADE, related_name="status_history"
    )
    from_status = models.CharField(max_length=25, blank=True)
    to_status = models.CharField(max_length=25)
    reason = models.TextField(blank=True)
    changed_by_name = models.CharField(max_length=150, blank=True)
    changed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-changed_at"]


class WorkerDocument(models.Model):
    DOCUMENT_TYPES = [
        ("NATIONAL_ID", "National ID"),
        ("LC1_LETTER", "LC1 letter"),
        ("PHOTO", "Photograph"),
        ("TRAINING", "Training certificate"),
        ("OTHER", "Other"),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    worker = models.ForeignKey(
        Worker, on_delete=models.CASCADE, related_name="documents"
    )
    document_type = models.CharField(
        max_length=20, choices=DOCUMENT_TYPES, default="OTHER"
    )
    title = models.CharField(max_length=160)
    file = models.FileField(storage=private_storage, upload_to="worker_documents/%Y/%m/")
    uploaded_by_name = models.CharField(max_length=150, blank=True)
    verified = models.BooleanField(default=False)
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-uploaded_at"]

    def __str__(self) -> str:
        return f"{self.worker.worker_number} — {self.title}"
