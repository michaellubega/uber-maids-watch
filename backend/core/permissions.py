"""Role-based API permissions.

Permissions are always enforced on the server.  Hiding a button in Flutter is a
usability aid, never a security control.
"""

from rest_framework.permissions import BasePermission, SAFE_METHODS

from core.models import Role, STAFF_ROLES


class RolePermission(BasePermission):
    """ViewSets declare ``read_roles`` and ``write_roles``."""

    message = "Your role does not permit this action."

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated):
            return False
        if request.method in SAFE_METHODS:
            allowed = getattr(view, "read_roles", None)
        else:
            allowed = getattr(view, "write_roles", None)
        if allowed is None:
            allowed = STAFF_ROLES
        return user.role in allowed


class IsAdmin(BasePermission):
    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.role == Role.ADMIN
        )


class IsStaffRole(BasePermission):
    def has_permission(self, request, view):
        return bool(
            request.user
            and request.user.is_authenticated
            and request.user.role in STAFF_ROLES
        )
