"""Forms used by family and worker portal accounts."""

import os

from django import forms
from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.contrib.auth.validators import UnicodeUsernameValidator
from django.core.exceptions import ValidationError

from catalog.models import Service
from operations.models import Booking, ReplacementCase
from workers.models import WorkerDocument

User = get_user_model()

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


class RegistrationForm(PortalFormMixin, forms.Form):
    """Self-service sign-up for families and domestic workers.

    The account is created immediately but the linked client/worker record is
    left unverified: the office still decides whether identity documents are
    acceptable and records the verification outcome.
    """

    ROLE_CHOICES = (
        ("FAMILY", "I am a family looking for domestic help"),
        ("MAID", "I am a domestic worker looking for work"),
    )

    role = forms.ChoiceField(
        choices=ROLE_CHOICES,
        label="I am registering as",
        widget=forms.Select(),
    )
    first_name = forms.CharField(max_length=150, label="First name")
    last_name = forms.CharField(max_length=150, label="Last name")
    username = forms.CharField(
        max_length=150,
        label="Username",
        help_text="You will use this to sign in. Letters, digits and @/./+/-/_ only.",
        widget=forms.TextInput(attrs={"autocomplete": "username", "autocapitalize": "none"}),
    )
    email = forms.EmailField(
        required=False,
        label="Email (optional)",
        widget=forms.EmailInput(attrs={"autocomplete": "email"}),
    )
    phone_number = forms.CharField(
        max_length=25,
        label="Phone number",
        widget=forms.TextInput(attrs={"autocomplete": "tel", "placeholder": "e.g. 0770 000 000"}),
    )
    area = forms.CharField(
        max_length=160,
        label="Area",
        help_text="The neighbourhood or district where you live or need help.",
        widget=forms.TextInput(attrs={"placeholder": "e.g. Kololo, Ntinda, Kireka"}),
    )
    preferred_contact = forms.ChoiceField(
        choices=(
            ("PHONE", "Phone call"),
            ("WHATSAPP", "WhatsApp"),
            ("SMS", "SMS"),
            ("EMAIL", "Email"),
        ),
        required=False,
        initial="PHONE",
        label="Preferred contact (families)",
    )
    password1 = forms.CharField(
        label="Password",
        strip=False,
        widget=forms.PasswordInput(attrs={"autocomplete": "new-password"}),
        help_text="At least 8 characters; avoid a name or a common password.",
    )
    password2 = forms.CharField(
        label="Confirm password",
        strip=False,
        widget=forms.PasswordInput(attrs={"autocomplete": "new-password"}),
    )

    def clean_username(self):
        username = self.cleaned_data["username"].strip()
        UnicodeUsernameValidator()(username)
        if User.objects.filter(username__iexact=username).exists():
            raise forms.ValidationError("That username is already taken. Choose another.")
        return username

    def clean_role(self):
        role = self.cleaned_data["role"]
        if role not in {"FAMILY", "MAID"}:
            raise forms.ValidationError("Choose family or domestic worker.")
        return role

    def clean(self):
        cleaned = super().clean()
        password1 = cleaned.get("password1")
        password2 = cleaned.get("password2")
        if password1 and password2 and password1 != password2:
            self.add_error("password2", "The two passwords do not match.")
        if password1:
            candidate = User(
                username=cleaned.get("username", ""),
                first_name=cleaned.get("first_name", ""),
                last_name=cleaned.get("last_name", ""),
                email=cleaned.get("email", ""),
            )
            try:
                validate_password(password1, candidate)
            except ValidationError as error:
                self.add_error("password1", error)
        return cleaned


class WorkerDocumentForm(PortalFormMixin, forms.ModelForm):
    """Upload a private verification document for the signed-in worker."""

    class Meta:
        model = WorkerDocument
        fields = ("document_type", "title", "file")
        widgets = {
            "title": forms.TextInput(
                attrs={"placeholder": "e.g. National ID - front"}
            ),
            "file": forms.ClearableFileInput(
                attrs={
                    "accept": ".pdf,.jpg,.jpeg,.png",
                }
            ),
        }
        labels = {
            "document_type": "Document type",
            "title": "Document name",
            "file": "Choose a file",
        }
        help_texts = {
            "file": "PDF, JPG or PNG, up to "
            f"{settings.MAX_DOCUMENT_BYTES // (1024 * 1024)} MB. Files are stored privately.",
        }

    def clean_file(self):
        upload = self.cleaned_data.get("file")
        if upload in (None, ""):
            return upload
        extension = os.path.splitext(upload.name)[1].lower()
        if extension not in settings.ALLOWED_DOCUMENT_EXTENSIONS:
            raise forms.ValidationError(
                "Allowed file types: "
                + ", ".join(sorted(settings.ALLOWED_DOCUMENT_EXTENSIONS))
            )
        if upload.size > settings.MAX_DOCUMENT_BYTES:
            raise forms.ValidationError(
                f"File is larger than {settings.MAX_DOCUMENT_BYTES // (1024 * 1024)} MB."
            )
        return upload
