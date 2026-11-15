"""Server-rendered web portal for family and domestic-worker accounts."""

import os

from django.contrib import messages
from django.contrib.auth import login as auth_login
from django.contrib.auth import logout as auth_logout
from django.contrib.auth.forms import AuthenticationForm
from django.db import transaction
from django.db.models import Sum
from django.http import FileResponse, Http404
from django.shortcuts import get_object_or_404, redirect, render
from django.urls import reverse
from django.utils import timezone
from django.utils.http import url_has_allowed_host_and_scheme
from django.views.decorators.http import require_http_methods, require_POST

from catalog.models import Service
from clients.models import Client
from core.audit import log_action
from core.models import Role, User
from operations.models import Booking, FollowUp, Placement, ReplacementCase
from portal.decorators import PORTAL_ROLES, portal_required, role_required
from portal.forms import (
    BookingRequestForm,
    RegistrationForm,
    ReplacementRequestForm,
    WorkerDocumentForm,
)
from workers.models import Worker, WorkerDocument


def _is_family(user) -> bool:
    return user.role == Role.FAMILY


def _client_for(user):
    return Client.objects.filter(user=user).first()


def _worker_for(user):
    return Worker.objects.filter(user=user).first()


def _open_follow_ups(placements):
    return FollowUp.objects.filter(
        placement__in=placements, completed_at__isnull=True
    ).select_related("placement", "placement__worker", "placement__client")


def _safe_next(request, fallback: str) -> str:
    candidate = request.POST.get("next") or request.GET.get("next") or ""
    if candidate and url_has_allowed_host_and_scheme(
        candidate,
        allowed_hosts={request.get_host()},
        require_https=request.is_secure(),
    ):
        return candidate
    return fallback


def landing(request):
    services = Service.objects.filter(active=True, public_visibility=True).order_by("name")
    if not services:
        services = Service.objects.filter(active=True).order_by("name")[:6]
    return render(
        request,
        "portal/landing.html",
        {
            "services": services,
            "is_family": request.user.is_authenticated and request.user.role == Role.FAMILY,
            "is_worker": request.user.is_authenticated and request.user.role == Role.MAID,
        },
    )


@require_http_methods(["GET", "POST"])
def login_view(request):
    if request.user.is_authenticated and request.user.role in PORTAL_ROLES:
        return redirect("portal:dashboard")

    error = ""
    if request.method == "POST":
        form = AuthenticationForm(request, data=request.POST)
        if form.is_valid():
            user = form.get_user()
            if user.role not in PORTAL_ROLES:
                error = (
                    "This web portal is for family and domestic-worker accounts. "
                    "Office staff use the desktop application."
                )
            else:
                auth_login(request, user)
                log_action(
                    actor=user,
                    action="PORTAL_SIGN_IN",
                    entity="core.User",
                    entity_id=user.id,
                    request=request,
                )
                return redirect(_safe_next(request, reverse("portal:dashboard")))
        else:
            error = "Those details did not match an account. Check the username and password."
    else:
        form = AuthenticationForm(request)

    return render(
        request,
        "portal/login.html",
        {"form": form, "error": error, "next": request.GET.get("next", "")},
    )


@require_http_methods(["GET", "POST"])
def register(request):
    """Create a family or domestic-worker account from the public website.

    Registration is open, but verification is not: families get an active
    household record, while workers start as applicants with pending
    verification until the office reviews their documents.
    """

    if request.user.is_authenticated and request.user.role in PORTAL_ROLES:
        return redirect("portal:dashboard")

    if request.method == "POST":
        form = RegistrationForm(request.POST)
        if form.is_valid():
            data = form.cleaned_data
            role = data["role"]
            full_name = f"{data['first_name']} {data['last_name']}".strip()
            with transaction.atomic():
                user = User.objects.create_user(
                    username=data["username"],
                    email=data["email"],
                    password=data["password1"],
                    first_name=data["first_name"],
                    last_name=data["last_name"],
                    phone_number=data["phone_number"],
                    role=role,
                )
                if role == Role.FAMILY:
                    profile = Client.objects.create(
                        full_name=full_name,
                        phone=data["phone_number"],
                        email=data["email"],
                        area=data["area"],
                        preferred_contact=data.get("preferred_contact") or "PHONE",
                        user=user,
                    )
                    reference = {"client_number": profile.client_number}
                else:
                    profile = Worker.objects.create(
                        full_name=full_name,
                        phone=data["phone_number"],
                        area=data["area"],
                        status="APPLICANT",
                        verification_status="PENDING",
                        user=user,
                    )
                    reference = {"worker_number": profile.worker_number}

                log_action(
                    actor=user,
                    action="PORTAL_REGISTERED",
                    entity="core.User",
                    entity_id=user.id,
                    metadata={
                        "username": user.username,
                        "role": role,
                        **reference,
                    },
                    request=request,
                )

            auth_login(request, user)
            if role == Role.FAMILY:
                messages.success(
                    request,
                    "Your household account is ready. Customer care will contact "
                    "you to confirm your details and any request you send.",
                )
            else:
                messages.success(
                    request,
                    "Your worker account is ready. Upload your identity documents "
                    "so the office can complete verification. You are not verified "
                    "until the office records the outcome.",
                )
            return redirect("portal:dashboard")
    else:
        form = RegistrationForm()

    return render(request, "portal/register.html", {"form": form})


@require_POST
def logout_view(request):
    if request.user.is_authenticated:
        auth_logout(request)
    messages.success(request, "You have signed out.")
    return redirect("portal:landing")

@portal_required
def dashboard(request):
    if _is_family(request.user):
        client = _client_for(request.user)
        if client is None:
            return render(request, "portal/no_profile.html", {"profile_kind": "household"})
        placements = client.placements.select_related("worker").order_by("-start_date")
        active = [p for p in placements if p.status == "ACTIVE"]
        bookings = client.bookings.select_related("service").order_by("-created_at")[:5]
        follow_ups = _open_follow_ups(placements).order_by("due_date")[:4]
        outstanding = client.payments.filter(status__in=("PENDING", "PARTIAL")).aggregate(
            total=Sum("amount_ugx")
        )["total"] or 0
        open_cases = client.replacement_cases.exclude(
            status__in=("RESOLVED", "REJECTED")
        ).count()
        return render(
            request,
            "portal/dashboard_family.html",
            {
                "client": client,
                "placements": placements,
                "active_placements": active,
                "bookings": bookings,
                "follow_ups": follow_ups,
                "outstanding": outstanding,
                "open_cases": open_cases,
            },
        )

    worker = _worker_for(request.user)
    if worker is None:
        return render(request, "portal/no_profile.html", {"profile_kind": "worker"})
    placements = worker.placements.select_related("client").order_by("-start_date")
    current = [p for p in placements if p.status in ("ACTIVE", "PAUSED", "REPLACEMENT_REQUESTED")]
    follow_ups = _open_follow_ups(placements).order_by("due_date")[:4]
    return render(
        request,
        "portal/dashboard_maid.html",
        {
            "worker": worker,
            "placements": placements,
            "current_placements": current,
            "follow_ups": follow_ups,
            "documents_count": worker.documents.count(),
            "documents_pending": worker.documents.filter(verified=False).count(),
        },
    )


@role_required(Role.FAMILY)
def bookings(request):
    client = _client_for(request.user)
    if client is None:
        return render(request, "portal/no_profile.html", {"profile_kind": "household"})
    rows = client.bookings.select_related("service").order_by("-created_at")
    return render(request, "portal/bookings.html", {"client": client, "bookings": rows})


@role_required(Role.FAMILY)
def booking_new(request):
    client = _client_for(request.user)
    if client is None:
        return render(request, "portal/no_profile.html", {"profile_kind": "household"})

    if request.method == "POST":
        form = BookingRequestForm(request.POST)
        if form.is_valid():
            booking = form.save(commit=False)
            booking.client = client
            booking.status = "NEW"
            booking.location = booking.location or client.area
            booking.created_by_name = request.user.display_name
            booking.save()
            log_action(
                actor=request.user,
                action="PORTAL_BOOKING_REQUESTED",
                entity="operations.Booking",
                entity_id=booking.id,
                metadata={"booking_number": booking.booking_number},
                request=request,
            )
            messages.success(
                request,
                f"Request {booking.booking_number} was sent to the office. "
                "Customer care will contact you to confirm the details.",
            )
            return redirect("portal:bookings")
    else:
        form = BookingRequestForm(initial={"location": client.area})

    return render(request, "portal/booking_new.html", {"form": form, "client": client})


@portal_required
def placements(request):
    if _is_family(request.user):
        client = _client_for(request.user)
        if client is None:
            return render(request, "portal/no_profile.html", {"profile_kind": "household"})
        rows = client.placements.select_related("worker").order_by("-start_date")
        return render(
            request,
            "portal/placements.html",
            {"placements": rows, "audience": "family", "client": client},
        )

    worker = _worker_for(request.user)
    if worker is None:
        return render(request, "portal/no_profile.html", {"profile_kind": "worker"})
    rows = worker.placements.select_related("client").order_by("-start_date")
    return render(
        request,
        "portal/placements.html",
        {"placements": rows, "audience": "worker", "worker": worker},
    )


@portal_required
def placement_detail(request, pk):
    if _is_family(request.user):
        client = _client_for(request.user)
        if client is None:
            return render(request, "portal/no_profile.html", {"profile_kind": "household"})
        placement = get_object_or_404(
            Placement.objects.select_related("worker", "client"), pk=pk, client=client
        )
        audience = "family"
    else:
        worker = _worker_for(request.user)
        if worker is None:
            return render(request, "portal/no_profile.html", {"profile_kind": "worker"})
        placement = get_object_or_404(
            Placement.objects.select_related("worker", "client"), pk=pk, worker=worker
        )
        audience = "worker"

    follow_ups = placement.follow_ups.order_by("-due_date")
    cases = placement.replacement_cases.exclude(status="REJECTED").order_by("-created_at")
    return render(
        request,
        "portal/placement_detail.html",
        {
            "placement": placement,
            "follow_ups": follow_ups,
            "cases": cases,
            "audience": audience,
        },
    )

@portal_required
def followups(request):
    if _is_family(request.user):
        client = _client_for(request.user)
        if client is None:
            return render(request, "portal/no_profile.html", {"profile_kind": "household"})
        rows = FollowUp.objects.filter(
            placement__client=client
        ).select_related("placement", "placement__worker").order_by("-due_date")
        audience = "family"
    else:
        worker = _worker_for(request.user)
        if worker is None:
            return render(request, "portal/no_profile.html", {"profile_kind": "worker"})
        rows = FollowUp.objects.filter(
            placement__worker=worker
        ).select_related("placement", "placement__client").order_by("-due_date")
        audience = "worker"

    return render(
        request,
        "portal/followups.html",
        {"follow_ups": rows, "audience": audience},
    )


@role_required(Role.FAMILY)
def payments(request):
    client = _client_for(request.user)
    if client is None:
        return render(request, "portal/no_profile.html", {"profile_kind": "household"})
    rows = client.payments.select_related("booking", "placement").order_by("-created_at")
    outstanding = rows.filter(status__in=("PENDING", "PARTIAL")).aggregate(
        total=Sum("amount_ugx")
    )["total"] or 0
    paid = rows.filter(status="PAID").aggregate(total=Sum("amount_ugx"))["total"] or 0
    return render(
        request,
        "portal/payments.html",
        {"payments": rows, "outstanding": outstanding, "paid": paid, "client": client},
    )


@role_required(Role.FAMILY)
def replacements(request):
    client = _client_for(request.user)
    if client is None:
        return render(request, "portal/no_profile.html", {"profile_kind": "household"})
    rows = client.replacement_cases.select_related(
        "placement", "original_worker", "replacement_worker"
    ).order_by("-created_at")
    return render(request, "portal/replacements.html", {"cases": rows, "client": client})


@role_required(Role.FAMILY)
def replacement_new(request):
    client = _client_for(request.user)
    if client is None:
        return render(request, "portal/no_profile.html", {"profile_kind": "household"})

    if request.method == "POST":
        form = ReplacementRequestForm(request.POST, client=client)
        if form.is_valid():
            case = form.save(commit=False)
            case.client = client
            case.original_worker = case.placement.worker
            case.status = "OPEN"
            case.eligibility_decision = "PENDING"
            case.save()
            log_action(
                actor=request.user,
                action="PORTAL_REPLACEMENT_REQUESTED",
                entity="operations.ReplacementCase",
                entity_id=case.id,
                metadata={"case_number": case.case_number},
                request=request,
            )
            messages.success(
                request,
                f"Case {case.case_number} was sent to the office. A manager will "
                "review eligibility and contact you.",
            )
            return redirect("portal:replacements")
    else:
        form = ReplacementRequestForm(
            client=client, initial={"issue_reported_date": timezone.localdate()}
        )

    return render(request, "portal/replacement_new.html", {"form": form, "client": client})


@portal_required
def profile(request):
    if _is_family(request.user):
        profile_row = _client_for(request.user)
        kind = "family"
    else:
        profile_row = _worker_for(request.user)
        kind = "worker"
    if profile_row is None:
        return render(request, "portal/no_profile.html", {"profile_kind": kind})
    return render(
        request,
        "portal/profile.html",
        {"profile": profile_row, "kind": kind},
    )


@role_required(Role.MAID)
def documents(request):
    """List a worker's private documents and accept new uploads."""

    worker = _worker_for(request.user)
    if worker is None:
        return render(request, "portal/no_profile.html", {"profile_kind": "worker"})

    if request.method == "POST":
        form = WorkerDocumentForm(request.POST, request.FILES)
        if form.is_valid():
            document = form.save(commit=False)
            document.worker = worker
            document.uploaded_by_name = request.user.display_name
            document.verified = False
            document.save()
            log_action(
                actor=request.user,
                action="DOCUMENT_UPLOADED",
                entity="workers.WorkerDocument",
                entity_id=document.id,
                metadata={
                    "worker": str(worker.id),
                    "document_type": document.document_type,
                    "source": "portal",
                },
                request=request,
            )
            messages.success(
                request,
                "Document uploaded. The office will review it; uploading does "
                "not verify it automatically.",
            )
            return redirect("portal:documents")
    else:
        form = WorkerDocumentForm()

    return render(
        request,
        "portal/documents.html",
        {
            "worker": worker,
            "documents": worker.documents.all(),
            "form": form,
        },
    )


@role_required(Role.MAID)
def document_download(request, pk):
    """Stream one of the signed-in worker's documents and record the access."""

    worker = _worker_for(request.user)
    if worker is None:
        return render(request, "portal/no_profile.html", {"profile_kind": "worker"})
    document = get_object_or_404(WorkerDocument, pk=pk, worker=worker)
    if not document.file:
        raise Http404("File not found.")
    log_action(
        actor=request.user,
        action="DOCUMENT_DOWNLOADED",
        entity="workers.WorkerDocument",
        entity_id=document.id,
        metadata={"worker": str(worker.id), "source": "portal"},
        request=request,
    )
    document.file.open("rb")
    return FileResponse(
        document.file,
        as_attachment=True,
        filename=os.path.basename(document.file.name),
    )


