from django.db import models

from core.models import SyncableModel


# Module-level so the OpenAPI schema can give the set a stable enum name.
SERVICE_CATEGORY_CHOICES = [
    ("MAID", "Maid / house helper"),
    ("BABYSITTER", "Babysitter / childcare"),
    ("CLEANER", "Cleaner"),
    ("COOK", "Cook"),
    ("LAUNDRY", "Laundry / ironing"),
    ("OTHER", "Other owner-approved service"),
]


class Service(SyncableModel):
    """Configurable service catalogue entry.

    Prices remain optional and are explicitly marked as unconfirmed in the
    business-rules register.
    """

    CATEGORY_CHOICES = SERVICE_CATEGORY_CHOICES
    PRICING_CHOICES = [
        ("ONE_TIME", "One-time"),
        ("MONTHLY", "Monthly"),
        ("DAILY", "Daily"),
        ("QUOTE", "Custom quote"),
    ]

    name = models.CharField(max_length=120, unique=True)
    category = models.CharField(max_length=20, choices=CATEGORY_CHOICES, default="MAID")
    description = models.TextField(blank=True)
    pricing_type = models.CharField(
        max_length=20, choices=PRICING_CHOICES, default="QUOTE"
    )
    price_min_ugx = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )
    price_max_ugx = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )
    requirements = models.TextField(blank=True)
    active = models.BooleanField(default=True)
    public_visibility = models.BooleanField(default=False)

    def __str__(self) -> str:
        return self.name
