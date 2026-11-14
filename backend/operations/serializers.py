from django.utils import timezone
from rest_framework import serializers

from clients.models import Client
from core.models import Role
from operations.models import (
    Booking,
    FollowUp,
    Incident,
    Placement,
    ReplacementCase,
)
from workers.models import Worker


class BookingSerializer(serializers.ModelSerializer):
    client_name = serializers.CharField(source="client.full_name", read_only=True)
    client_number = serializers.CharField(source="client.client_number", read_only=True)
    service_name = serializers.CharField(source="service.name", read_only=True)

    def to_internal_value(self, data):
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if user and user.role == Role.FAMILY:
            # A client's booking always belongs to their own client record and
            # starts as a request; ignore any spoofed values sent by a device.
            data = data.copy()
            data.pop("client", None)
            data.pop("status", None)
        return super().to_internal_value(data)

    class Meta:
        model = Booking
        fields = (
            "id",
            "booking_number",
            "client",
            "client_name",
            "client_number",
            "service",
            "service_name",
            "requested_start_date",
            "location",
            "schedule",
            "requirements",
            "budget_ugx",
            "special_instructions",
            "status",
            "assigned_staff_name",
            "confirmed_at",
            "created_by_name",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )
        read_only_fields = (
            "id",
            "booking_number",
            "created_by_name",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )
        extra_kwargs = {"client": {"required": False}}

    def validate(self, attrs):
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if user and user.role == Role.FAMILY:
            client = getattr(user, "client_profile", None)
            if not client:
                raise serializers.ValidationError(
                    "This account is not linked to a client record."
                )
            attrs["client"] = client
            if not self.instance:
                attrs["status"] = "NEW"
            elif attrs.get("status") and attrs["status"] != self.instance.status:
                raise serializers.ValidationError(
                    "Clients cannot change booking status. Please contact the office."
                )
        elif not self.instance and not attrs.get("client"):
            raise serializers.ValidationError({"client": "A client is required."})
        return attrs


class PlacementSerializer(serializers.ModelSerializer):
    client_name = serializers.CharField(source="client.full_name", read_only=True)
    client_number = serializers.CharField(source="client.client_number", read_only=True)
    worker_name = serializers.CharField(source="worker.full_name", read_only=True)
    worker_number = serializers.CharField(source="worker.worker_number", read_only=True)
    booking_number = serializers.CharField(source="booking.booking_number", read_only=True)
    guarantee_status = serializers.CharField(read_only=True)

    class Meta:
        model = Placement
        fields = (
            "id",
            "placement_number",
            "booking",
            "booking_number",
            "client",
            "client_name",
            "client_number",
            "worker",
            "worker_name",
            "worker_number",
            "start_date",
            "terms",
            "status",
            "guarantee_days",
            "guarantee_end_date",
            "guarantee_status",
            "responsible_staff_name",
            "client_acknowledgement",
            "notes",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )
        read_only_fields = (
            "id",
            "placement_number",
            "guarantee_end_date",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )

    def validate(self, attrs):
        worker = attrs.get("worker") or getattr(self.instance, "worker", None)
        booking = attrs.get("booking") or getattr(self.instance, "booking", None)
        if booking:
            attrs.setdefault("client", booking.client)
            if attrs.get("client") and attrs["client"] != booking.client:
                raise serializers.ValidationError(
                    {"client": "The placement client must match the booking client."}
                )
        for candidate in (attrs.get("worker"),):
            if candidate and not self.instance:
                if candidate.verification_status not in {"VERIFIED", "EXCEPTION"}:
                    raise serializers.ValidationError(
                        {"worker": "Only a verified worker can be placed."}
                    )
                if candidate.status in {"SUSPENDED", "INACTIVE"}:
                    raise serializers.ValidationError(
                        {"worker": "This worker is not available for placement."}
                    )
        if not attrs.get("client") and not booking and not self.instance:
            raise serializers.ValidationError({"client": "A client is required."})
        return attrs


class FollowUpSerializer(serializers.ModelSerializer):
    placement_number = serializers.CharField(
        source="placement.placement_number", read_only=True
    )
    client_name = serializers.CharField(source="placement.client.full_name", read_only=True)
    worker_name = serializers.CharField(source="placement.worker.full_name", read_only=True)
    is_overdue = serializers.SerializerMethodField()
    is_completed = serializers.SerializerMethodField()

    class Meta:
        model = FollowUp
        fields = (
            "id",
            "placement",
            "placement_number",
            "client_name",
            "worker_name",
            "due_date",
            "completed_at",
            "staff_name",
            "contact_method",
            "outcome",
            "satisfaction",
            "notes",
            "next_follow_up_date",
            "created_by_name",
            "is_overdue",
            "is_completed",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )
        read_only_fields = (
            "id",
            "created_by_name",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )

    def get_is_overdue(self, obj) -> bool:
        return bool(obj.completed_at is None and obj.due_date < timezone.localdate())

    def get_is_completed(self, obj) -> bool:
        return obj.completed_at is not None


class IncidentSerializer(serializers.ModelSerializer):
    placement_number = serializers.CharField(
        source="placement.placement_number", read_only=True
    )

    class Meta:
        model = Incident
        fields = (
            "id",
            "placement",
            "placement_number",
            "category",
            "description",
            "status",
            "reported_by_name",
            "reported_at",
            "resolved_at",
            "notes",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )
        read_only_fields = (
            "id",
            "reported_by_name",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )


class ReplacementCaseSerializer(serializers.ModelSerializer):
    client_name = serializers.CharField(source="client.full_name", read_only=True)
    client_number = serializers.CharField(source="client.client_number", read_only=True)
    original_worker_name = serializers.CharField(
        source="original_worker.full_name", read_only=True
    )
    replacement_worker_name = serializers.CharField(
        source="replacement_worker.full_name", read_only=True
    )
    placement_number = serializers.CharField(
        source="placement.placement_number", read_only=True
    )

    class Meta:
        model = ReplacementCase
        fields = (
            "id",
            "case_number",
            "placement",
            "placement_number",
            "client",
            "client_name",
            "client_number",
            "original_worker",
            "original_worker_name",
            "issue_reported_date",
            "problem_category",
            "description",
            "guarantee_eligible",
            "eligibility_decision",
            "decision_reason",
            "approved_by_name",
            "replacement_worker",
            "replacement_worker_name",
            "replacement_date",
            "replacement_placement",
            "status",
            "resolution_notes",
            "client_confirmed",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )
        read_only_fields = (
            "id",
            "case_number",
            "client",
            "original_worker",
            "guarantee_eligible",
            "eligibility_decision",
            "decision_reason",
            "approved_by_name",
            "replacement_worker",
            "replacement_date",
            "replacement_placement",
            "status",
            "resolution_notes",
            "client_confirmed",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )
        extra_kwargs = {"placement": {"required": True}}

    def validate_placement(self, value):
        request = self.context.get("request")
        if request and request.user.role == Role.FAMILY:
            if value.client.user_id != request.user.id:
                raise serializers.ValidationError("You can only report issues on your own placement.")
        return value


class ReplacementReviewSerializer(serializers.Serializer):
    decision = serializers.ChoiceField(choices=["ELIGIBLE", "NOT_ELIGIBLE"])
    decision_reason = serializers.CharField(allow_blank=True, required=False)
    guarantee_confirmed = serializers.BooleanField(default=False)


class ReplacementAssignSerializer(serializers.Serializer):
    replacement_worker = serializers.PrimaryKeyRelatedField(
        queryset=Worker.objects.filter(deleted_at__isnull=True)
    )
    replacement_date = serializers.DateField(required=False)
    notes = serializers.CharField(allow_blank=True, required=False)
