"""The web portal is for family and domestic-worker accounts only."""

from functools import wraps
from urllib.parse import quote

from django.shortcuts import redirect, render
from django.urls import reverse

from core.models import Role

PORTAL_ROLES = {Role.FAMILY, Role.MAID}


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
