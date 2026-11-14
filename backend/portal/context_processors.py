"""Shared values for portal templates."""

from core.models import Role


def branding(request):
    user = getattr(request, "user", None)
    role = getattr(user, "role", None) if user is not None else None
    return {
        "brand": {
            "name": "Uber Maids Watch",
            "tagline": "House Organising Practice",
            "promise": "Help Our Girls Practice — Get Your House Organised",
        },
        "is_portal_user": bool(
            user is not None
            and user.is_authenticated
            and role in {Role.FAMILY, Role.MAID}
        ),
    }
