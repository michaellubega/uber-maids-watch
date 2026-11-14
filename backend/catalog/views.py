from rest_framework import viewsets

from catalog.models import Service
from catalog.serializers import ServiceSerializer
from core.models import Role
from core.permissions import RolePermission
from core.viewsets import AuditedModelViewSet


class ServiceViewSet(AuditedModelViewSet):
    queryset = Service.objects.all().order_by("name")
    serializer_class = ServiceSerializer
    permission_classes = [RolePermission]
    read_roles = {
        Role.ADMIN,
        Role.OPERATIONS,
        Role.VERIFICATION,
        Role.CUSTOMER_CARE,
        Role.FINANCE,
        Role.READONLY,
        Role.MAID,
        Role.FAMILY,
    }
    write_roles = {Role.ADMIN}
    entity_label = "service"
