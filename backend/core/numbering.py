"""Reference-number generation for business records."""

from django.db import transaction

from core.models import Counter

PREFIXES = {
    "worker": ("W", 4),
    "client": ("C", 4),
    "booking": ("B", 6),
    "placement": ("P", 6),
    "replacement": ("R", 6),
    "payment": ("RCPT", 6),
}


def next_number(kind: str) -> str:
    prefix, width = PREFIXES[kind]
    with transaction.atomic():
        counter, _ = Counter.objects.select_for_update().get_or_create(name=kind)
        counter.value += 1
        counter.save(update_fields=["value"])
        return f"{prefix}-{counter.value:0{width}d}"
