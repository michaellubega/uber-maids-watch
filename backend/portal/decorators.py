"""The web portal serves family, domestic-worker and administrator accounts.

Officer accounts (operations, verification, customer care, finance and
read-only) still work in the desktop system; only the owner/administrator
account gets the web office console.
"""

from functools import wraps
from urllib.parse import quote

from django.shortcuts import redirect, render
from django.urls import reverse

from core.models import Role

PORTAL_ROLES = {Role.FAMILY, Role.MAID}
OFFICE_ROLES = {Role.ADMIN}


def portal_required(view):
    """Send anonymous visitors to the sign-in page and keep staff out."""

    @wraps(view)
    def wrapper(request, *args, **kwargs):
        if not request.user.is_authenticated:
            login_url = reverse("portal:login")
            return redirect(f"{login_url}?next={quote(request.get_full_path())}")
        if request.user.role not in PORTAL_ROLES:
            return render(request, "portal/staff_notice.html", status=403)
        return view(request, *args, **kwargs)

    return wrapper


def office_required(view):
    """Restrict a page to the owner/administrator account."""

    @wraps(view)
    def wrapper(request, *args, **kwargs):
        if not request.user.is_authenticated:
            login_url = reverse("portal:login")
            return redirect(f"{login_url}?next={quote(request.get_full_path())}")
        if request.user.role not in OFFICE_ROLES:
            return render(request, "portal/staff_notice.html", status=403)
        return view(request, *args, **kwargs)

    return wrapper


def role_required(*roles):
    """Restrict a portal page to one or more roles."""

    def decorator(view):
        @wraps(view)
        @portal_required
        def wrapper(request, *args, **kwargs):
            if request.user.role not in roles:
                return render(request, "portal/forbidden.html", status=403)
            return view(request, *args, **kwargs)

        return wrapper

    return decorator
