from rest_framework import viewsets

from core.audit import log_action
from core.models import Role
from core.permissions import RolePermission
from core.viewsets import AuditedModelViewSet
from payments.models import Payment
from payments.serializers import PaymentSerializer


class PaymentViewSet(AuditedModelViewSet):
    serializer_class = PaymentSerializer
    permission_classes = [RolePermission]
    read_roles = {
        Role.ADMIN,
        Role.OPERATIONS,
        Role.FINANCE,
        Role.READONLY,
        Role.FAMILY,
    }
    write_roles = {Role.ADMIN, Role.FINANCE}
    entity_label = "payment"

    def get_queryset(self):
        queryset = Payment.objects.select_related(
            "client", "booking", "placement"
        ).filter(deleted_at__isnull=True)
        role = getattr(getattr(self.request, "user", None), "role", None)
        if role == Role.FAMILY:
            queryset = queryset.filter(client__user=self.request.user)
        elif role == Role.MAID:
            queryset = queryset.none()
        return queryset.order_by("-created_at")

    def perform_create(self, serializer):
        payment = serializer.save(recorded_by_name=self.request.user.display_name)
        log_action(
            actor=self.request.user,
            action="PAYMENT_RECORDED",
            entity="payments.Payment",
            entity_id=payment.id,
            metadata={
                "receipt_reference": payment.receipt_reference,
                "amount_ugx": str(payment.amount_ugx),
                "status": payment.status,
            },
            request=self.request,
        )

    def perform_update(self, serializer):
        payment = serializer.save()
        log_action(
            actor=self.request.user,
            action="PAYMENT_UPDATED",
            entity="payments.Payment",
            entity_id=payment.id,
            metadata={
                "receipt_reference": payment.receipt_reference,
                "amount_ugx": str(payment.amount_ugx),
                "status": payment.status,
            },
            request=self.request,
        )
