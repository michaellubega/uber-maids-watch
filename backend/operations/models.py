from datetime import timedelta

from django.conf import settings
from django.db import models
from django.utils import timezone

from clients.models import Client
from core.models import SyncableModel
from core.numbering import next_number
from workers.models import Worker


# Shared by Incident.category and ReplacementCase.problem_category. Declared at
# module level so the OpenAPI schema can give the set a stable enum name.
INCIDENT_CATEGORY_CHOICES = [
    ("WORKER_LEFT", "Worker left / absconded"),
    ("CONDUCT", "Conduct complaint"),
    ("SKILLS_MISMATCH", "Skills mismatch"),
    ("THEFT_ALLEGATION", "Theft allegation"),
    ("ATTENDANCE", "Attendance / reliability"),
    ("OTHER", "Other"),
]


class Booking(SyncableModel):
    STATUS_CHOICES = [
        ("NEW", "New"),
        ("CONTACTED", "Contacted"),
        ("REQUIREMENTS_CONFIRMED", "Requirements confirmed"),
        ("AWAITING_CLIENT", "Awaiting client"),
        ("AWAITING_WORKER", "Awaiting worker"),
        ("CONFIRMED", "Confirmed"),
        ("CANCELLED", "Cancelled"),
        ("CONVERTED", "Converted to placement"),
        ("CLOSED", "Closed"),
    ]

    booking_number = models.CharField(max_length=20, unique=True, blank=True)
    client = models.ForeignKey(Client, on_delete=models.PROTECT, related_name="bookings")
    service = models.ForeignKey("catalog.Service", on_delete=models.PROTECT, related_name="bookings")
    requested_start_date = models.DateField(null=True, blank=True)
    location = models.CharField(max_length=255, blank=True)
    schedule = models.CharField(max_length=255, blank=True)
    requirements = models.TextField(blank=True)
    budget_ugx = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    special_instructions = models.TextField(blank=True)
    status = models.CharField(max_length=30, choices=STATUS_CHOICES, default="NEW")
    assigned_staff_name = models.CharField(max_length=150, blank=True)
    confirmed_at = models.DateTimeField(null=True, blank=True)
    created_by_name = models.CharField(max_length=150, blank=True)

    def save(self, *args, **kwargs):
        if not self.booking_number:
            self.booking_number = next_number("booking")
        super().save(*args, **kwargs)

    def __str__(self) -> str:
        return f"{self.booking_number} — {self.client.full_name}"


class Placement(SyncableModel):
    STATUS_CHOICES = [
        ("PREPARING", "Preparing"),
        ("ACTIVE", "Active"),
        ("PAUSED", "Paused"),
        ("COMPLETED", "Completed"),
        ("TERMINATED", "Terminated"),
        ("REPLACEMENT_REQUESTED", "Replacement requested"),
    ]

    placement_number = models.CharField(max_length=20, unique=True, blank=True)
    booking = models.ForeignKey(
        Booking, null=True, blank=True, on_delete=models.PROTECT, related_name="placements"
    )
    client = models.ForeignKey(Client, on_delete=models.PROTECT, related_name="placements")
    worker = models.ForeignKey(Worker, on_delete=models.PROTECT, related_name="placements")
    start_date = models.DateField()
    terms = models.TextField(blank=True)
    status = models.CharField(max_length=30, choices=STATUS_CHOICES, default="PREPARING")
    guarantee_days = models.PositiveSmallIntegerField(
        default=settings.GUARANTEE_DAYS_DEFAULT
    )
    guarantee_end_date = models.DateField(null=True, blank=True)
    responsible_staff_name = models.CharField(max_length=150, blank=True)
    client_acknowledgement = models.TextField(blank=True)
    notes = models.TextField(blank=True)

    def save(self, *args, **kwargs):
        if not self.placement_number:
            self.placement_number = next_number("placement")
        if self.start_date and self.guarantee_days:
            self.guarantee_end_date = self.start_date + timedelta(days=self.guarantee_days)
        super().save(*args, **kwargs)

    @property
    def guarantee_status(self) -> str:
        if not self.guarantee_end_date:
            return "UNKNOWN"
        today = timezone.localdate()
        if today < self.start_date:
            return "NOT_STARTED"
        if today <= self.guarantee_end_date:
            return "IN_GUARANTEE"
        return "EXPIRED"

    def __str__(self) -> str:
        return f"{self.placement_number} — {self.worker.full_name}"


class FollowUp(SyncableModel):
    OUTCOME_CHOICES = [
        ("CLIENT_SATISFIED", "Client satisfied"),
        ("WORKER_SETTLED", "Worker settled in"),
        ("CLIENT_REQUESTED_SUPPORT", "Client requested support"),
        ("WORKER_UNAVAILABLE", "Worker unavailable"),
        ("CONDUCT_CONCERN", "Conduct concern"),
        ("REPLACEMENT_REQUESTED", "Replacement requested"),
        ("CLIENT_UNREACHABLE", "Client unreachable"),
        ("OTHER", "Other"),
    ]
    CONTACT_METHODS = [
        ("PHONE", "Phone"),
        ("WHATSAPP", "WhatsApp"),
        ("SMS", "SMS"),
        ("VISIT", "Visit"),
        ("EMAIL", "Email"),
    ]

    placement = models.ForeignKey(Placement, on_delete=models.PROTECT, related_name="follow_ups")
    due_date = models.DateField()
    completed_at = models.DateTimeField(null=True, blank=True)
    staff_name = models.CharField(max_length=150, blank=True)
    contact_method = models.CharField(
        max_length=20, choices=CONTACT_METHODS, default="PHONE"
    )
    outcome = models.CharField(max_length=30, choices=OUTCOME_CHOICES, blank=True)
    satisfaction = models.PositiveSmallIntegerField(null=True, blank=True)
    notes = models.TextField(blank=True)
    next_follow_up_date = models.DateField(null=True, blank=True)
    created_by_name = models.CharField(max_length=150, blank=True)

    class Meta(SyncableModel.Meta):
        ordering = ["due_date"]

    def __str__(self) -> str:
        return f"Follow-up {self.due_date} for {self.placement.placement_number}"


class Incident(SyncableModel):
    CATEGORY_CHOICES = INCIDENT_CATEGORY_CHOICES
    STATUS_CHOICES = [
        ("OPEN", "Open"),
        ("INVESTIGATING", "Investigating"),
        ("RESOLVED", "Resolved"),
    ]

    placement = models.ForeignKey(Placement, on_delete=models.PROTECT, related_name="incidents")
    category = models.CharField(max_length=30, choices=CATEGORY_CHOICES, default="OTHER")
    description = models.TextField()
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="OPEN")
    reported_by_name = models.CharField(max_length=150, blank=True)
    reported_at = models.DateTimeField(default=timezone.now)
    resolved_at = models.DateTimeField(null=True, blank=True)
    notes = models.TextField(blank=True)

    def __str__(self) -> str:
        return f"Incident {self.category} — {self.placement.placement_number}"


class ReplacementCase(SyncableModel):
    PROBLEM_CHOICES = INCIDENT_CATEGORY_CHOICES
    STATUS_CHOICES = [
        ("OPEN", "Open"),
        ("REVIEWING", "Under review"),
        ("APPROVED", "Approved"),
        ("ASSIGNED", "Replacement assigned"),
        ("RESOLVED", "Resolved"),
        ("REJECTED", "Rejected"),
    ]
    DECISION_CHOICES = [
        ("PENDING", "Pending review"),
        ("ELIGIBLE", "Eligible"),
        ("NOT_ELIGIBLE", "Not eligible"),
    ]

    case_number = models.CharField(max_length=20, unique=True, blank=True)
    placement = models.ForeignKey(
        Placement, on_delete=models.PROTECT, related_name="replacement_cases"
    )
    client = models.ForeignKey(Client, on_delete=models.PROTECT, related_name="replacement_cases")
    original_worker = models.ForeignKey(
        Worker, on_delete=models.PROTECT, related_name="replacement_cases"
    )
    issue_reported_date = models.DateField(default=timezone.localdate)
    problem_category = models.CharField(
        max_length=30, choices=PROBLEM_CHOICES, default="OTHER"
    )
    description = models.TextField()
    guarantee_eligible = models.BooleanField(null=True, blank=True)
    eligibility_decision = models.CharField(
        max_length=20, choices=DECISION_CHOICES, default="PENDING"
    )
    decision_reason = models.TextField(blank=True)
    approved_by_name = models.CharField(max_length=150, blank=True)
    replacement_worker = models.ForeignKey(
        Worker,
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="replacement_assignments",
    )
    replacement_date = models.DateField(null=True, blank=True)
    replacement_placement = models.ForeignKey(
        Placement,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="source_replacement_case",
    )
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="OPEN")
    resolution_notes = models.TextField(blank=True)
    client_confirmed = models.BooleanField(default=False)

    def save(self, *args, **kwargs):
        if not self.case_number:
            self.case_number = next_number("replacement")
        super().save(*args, **kwargs)

    def __str__(self) -> str:
        return f"{self.case_number} — {self.client.full_name}"
