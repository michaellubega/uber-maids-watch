from rest_framework import viewsets

from clients.models import Client
from clients.serializers import ClientSerializer
from core.models import Role
from core.permissions import RolePermission
from core.viewsets import AuditedModelViewSet


class ClientViewSet(AuditedModelViewSet):
    serializer_class = ClientSerializer
    permission_classes = [RolePermission]
    read_roles = {
        Role.ADMIN,
        Role.OPERATIONS,
        Role.VERIFICATION,
        Role.CUSTOMER_CARE,
        Role.FINANCE,
        Role.READONLY,
        Role.FAMILY,
    }
    write_roles = {Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE}
    entity_label = "client"

    def get_queryset(self):
        queryset = Client.objects.select_related("user").filter(deleted_at__isnull=True)
        role = getattr(getattr(self.request, "user", None), "role", None)
        if role == Role.FAMILY:
            queryset = queryset.filter(user=self.request.user)
        elif role is not None and role not in self.read_roles:
            queryset = queryset.none()
        return queryset.order_by("full_name")
