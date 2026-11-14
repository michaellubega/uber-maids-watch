"""Forms used by family and worker portal accounts."""

from django import forms

from catalog.models import Service
from operations.models import Booking, ReplacementCase

TEXT_CLASS = "field-input"


class PortalFormMixin:
    """Apply the portal styles to every widget without repeating attrs."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        for field in self.fields.values():
            widget = field.widget
            if isinstance(widget, forms.CheckboxInput):
                widget.attrs.setdefault("class", "field-check")
            elif isinstance(widget, (forms.Select, forms.SelectMultiple)):
                widget.attrs.setdefault("class", "field-input field-select")
            else:
                widget.attrs.setdefault("class", TEXT_CLASS)
            if isinstance(widget, forms.Textarea):
                widget.attrs.setdefault("rows", 4)


class BookingRequestForm(PortalFormMixin, forms.ModelForm):
    class Meta:
        model = Booking
        fields = (
            "service",
            "requested_start_date",
            "location",
            "schedule",
            "requirements",
            "budget_ugx",
            "special_instructions",
        )
        widgets = {
            "requested_start_date": forms.DateInput(attrs={"type": "date"}),
            "requirements": forms.Textarea(
                attrs={"placeholder": "Who is the worker for? Any ages, tasks or hours we should know about?"}
            ),
            "special_instructions": forms.Textarea(
                attrs={"placeholder": "Anything else the office should know?"}
            ),
            "location": forms.TextInput(attrs={"placeholder": "Area or neighbourhood"}),
            "schedule": forms.TextInput(attrs={"placeholder": "e.g. Monday to Saturday, live-in"}),
        }
        labels = {
            "requested_start_date": "Preferred start date",
            "budget_ugx": "Budget (UGX, optional)",
            "requirements": "What do you need?",
            "special_instructions": "Special instructions",
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["service"].queryset = Service.objects.filter(active=True).order_by("name")
        self.fields["service"].empty_label = "Choose a service"
        self.fields["budget_ugx"].widget.attrs.setdefault("min", "0")
        self.fields["budget_ugx"].widget.attrs.setdefault("step", "1000")

    def clean_budget_ugx(self):
        value = self.cleaned_data.get("budget_ugx")
        if value is not None and value < 0:
            raise forms.ValidationError("Enter a positive amount or leave it blank.")
        return value


class ReplacementRequestForm(PortalFormMixin, forms.ModelForm):
    class Meta:
        model = ReplacementCase
        fields = ("placement", "problem_category", "issue_reported_date", "description")
        widgets = {
            "issue_reported_date": forms.DateInput(attrs={"type": "date"}),
            "description": forms.Textarea(
                attrs={"placeholder": "Describe what happened, when, and what support you need."}
            ),
        }
        labels = {
            "placement": "Which placement?",
            "problem_category": "What is the issue?",
            "issue_reported_date": "When did it happen?",
            "description": "Tell us more",
        }

    def __init__(self, *args, client=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.client = client
        placements = client.placements.exclude(
            status__in=("COMPLETED", "TERMINATED")
        ).order_by("-start_date")
        self.fields["placement"].queryset = placements
        self.fields["placement"].empty_label = "Choose a placement"

    def clean_placement(self):
        placement = self.cleaned_data["placement"]
        if self.client is None or placement.client_id != self.client.id:
            raise forms.ValidationError("Choose one of your own placements.")
        if placement.replacement_cases.filter(
            status__in=("OPEN", "REVIEWING", "APPROVED", "ASSIGNED")
        ).exists():
            raise forms.ValidationError(
                "There is already an open replacement case for this placement. "
                "The office will contact you about it."
            )
        return placement
