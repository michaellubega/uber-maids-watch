"""Small presentation helpers for the portal templates."""

from decimal import Decimal, InvalidOperation

from django import template
from django.utils import timezone

register = template.Library()

GOOD = {"ACTIVE", "VERIFIED", "PAID", "CONFIRMED", "RESOLVED", "ELIGIBLE",
        "CLIENT_SATISFIED", "WORKER_SETTLED", "COMPLETED", "IN_GUARANTEE",
        "ASSIGNED", "CONVERTED"}
WARN = {"NEW", "CONTACTED", "REQUIREMENTS_CONFIRMED", "AWAITING_CLIENT",
        "AWAITING_WORKER", "PENDING", "PARTIAL", "REVIEWING", "IN_PROGRESS",
        "OPEN", "PREPARING", "RESERVED", "TRAINING", "DOCUMENTS_PENDING",
        "UNDER_VERIFICATION", "APPLICANT"}
BAD = {"REJECTED", "CANCELLED", "TERMINATED", "NOT_ELIGIBLE", "FAILED",
       "OVERDUE", "SUSPENDED", "INACTIVE", "EXPIRED"}


@register.filter
def ugx(value):
    if value in (None, ""):
        return "—"
    try:
        amount = Decimal(value)
    except (InvalidOperation, TypeError, ValueError):
        return "—"
    return f"UGX {amount:,.0f}"


@register.filter
def tone(value):
    label = str(value or "").upper()
    if label in GOOD:
        return "good"
    if label in WARN:
        return "warn"
    if label in BAD:
        return "bad"
    return "neutral"


@register.filter
def labelize(value):
    text = str(value or "").replace("_", " ").strip()
    return text.title() if text else "—"


@register.filter
def followup_state(follow_up):
    if follow_up.completed_at:
        return "Completed"
    today = timezone.localdate()
    if follow_up.due_date < today:
        return "Overdue"
    if follow_up.due_date == today:
        return "Due today"
    return "Scheduled"


@register.filter
def followup_tone(follow_up):
    if follow_up.completed_at:
        return "good"
    today = timezone.localdate()
    if follow_up.due_date < today:
        return "bad"
    if follow_up.due_date == today:
        return "warn"
    return "neutral"


@register.filter
def days_left(placement):
    if not placement.guarantee_end_date:
        return None
    return (placement.guarantee_end_date - timezone.localdate()).days


@register.filter
def has_role(user, role):
    return getattr(user, "role", None) == role
