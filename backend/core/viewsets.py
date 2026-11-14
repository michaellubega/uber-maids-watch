"""Reusable view-set behaviour for audited, syncable business records."""

from rest_framework import viewsets

from core.audit import log_action


class AuditedModelViewSet(viewsets.ModelViewSet):
    """Soft-delete business records and write an audit event for every change."""

    entity_label = "record"

    def get_queryset(self):
        queryset = super().get_queryset()
        # Read-only views and supporting records may not be syncable; only
        # apply the tombstone filter when the field exists.
        if any(field.name == "deleted_at" for field in queryset.model._meta.fields):
            queryset = queryset.filter(deleted_at__isnull=True)
        return queryset

    def perform_create(self, serializer):
        instance = serializer.save()
        log_action(
            actor=self.request.user,
            action=f"{self.entity_label.upper()}_CREATED",
            entity=f"{instance._meta.app_label}.{instance.__class__.__name__}",
            entity_id=instance.pk,
            metadata={"reference": self._reference(instance)},
            request=self.request,
        )

    def perform_update(self, serializer):
        instance = serializer.save()
        log_action(
            actor=self.request.user,
            action=f"{self.entity_label.upper()}_UPDATED",
            entity=f"{instance._meta.app_label}.{instance.__class__.__name__}",
            entity_id=instance.pk,
            metadata={"reference": self._reference(instance)},
            request=self.request,
        )

    def perform_destroy(self, instance):
        log_action(
            actor=self.request.user,
            action=f"{self.entity_label.upper()}_DELETED",
            entity=f"{instance._meta.app_label}.{instance.__class__.__name__}",
            entity_id=instance.pk,
            metadata={"reference": self._reference(instance)},
            request=self.request,
        )
        instance.delete()

    @staticmethod
    def _reference(instance) -> str:
        for attribute in (
            "booking_number",
            "placement_number",
            "case_number",
            "receipt_reference",
            "worker_number",
            "client_number",
            "name",
        ):
            value = getattr(instance, attribute, "")
            if value:
                return str(value)
        return str(instance.pk)
