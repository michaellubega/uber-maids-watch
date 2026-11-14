from django.utils import timezone
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import SAFE_METHODS
from rest_framework.response import Response

from core.audit import log_action
from core.models import Role, STAFF_ROLES
from core.permissions import RolePermission
from core.viewsets import AuditedModelViewSet
from operations.models import (
    Booking,
    FollowUp,
    Incident,
    Placement,
    ReplacementCase,
)
from operations.serializers import (
    BookingSerializer,
    FollowUpSerializer,
    IncidentSerializer,
    PlacementSerializer,
    ReplacementAssignSerializer,
    ReplacementCaseSerializer,
    ReplacementReviewSerializer,
)
from workers.models import Worker, WorkerStatusHistory


class BookingViewSet(AuditedModelViewSet):
    serializer_class = BookingSerializer
    permission_classes = [RolePermission]
    read_roles = {
        Role.ADMIN,
        Role.OPERATIONS,
        Role.CUSTOMER_CARE,
        Role.FINANCE,
        Role.READONLY,
        Role.FAMILY,
    }
    write_roles = {Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE, Role.FAMILY}
    entity_label = "booking"

    def get_queryset(self):
        queryset = Booking.objects.select_related("client", "service").filter(
            deleted_at__isnull=True
        )
        role = getattr(getattr(self.request, "user", None), "role", None)
        if role == Role.FAMILY:
            queryset = queryset.filter(client__user=self.request.user)
        elif role == Role.MAID:
            queryset = queryset.none()
        return queryset.order_by("-created_at")

    def check_permissions(self, request):
        super().check_permissions(request)
        if request.user.role == Role.FAMILY and request.method not in SAFE_METHODS + ("POST",):
            raise PermissionDenied("Clients may create booking requests but cannot edit them.")

    def perform_create(self, serializer):
        booking = serializer.save(created_by_name=self.request.user.display_name)
        log_action(
            actor=self.request.user,
            action="BOOKING_CREATED",
            entity="operations.Booking",
            entity_id=booking.id,
            metadata={"booking_number": booking.booking_number},
            request=self.request,
        )

    @action(detail=True, methods=["post"], url_path="confirm")
    def confirm(self, request, pk=None):
        if request.user.role not in {Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE}:
            raise PermissionDenied("Only customer care, operations or an administrator can confirm a booking.")
        booking = self.get_object()
        if booking.status in {"CANCELLED", "CLOSED", "CONVERTED"}:
            return Response(
                {"detail": f"A {booking.status.lower()} booking cannot be confirmed."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        booking.status = "CONFIRMED"
        booking.confirmed_at = timezone.now()
        if request.data.get("assigned_staff_name"):
            booking.assigned_staff_name = request.data["assigned_staff_name"]
        booking.save()
        log_action(
            actor=request.user,
            action="BOOKING_CONFIRMED",
            entity="operations.Booking",
            entity_id=booking.id,
            metadata={"booking_number": booking.booking_number},
            request=request,
        )
        return Response(self.get_serializer(booking).data)


class PlacementViewSet(AuditedModelViewSet):
    serializer_class = PlacementSerializer
    permission_classes = [RolePermission]
    read_roles = {
        Role.ADMIN,
        Role.OPERATIONS,
        Role.CUSTOMER_CARE,
        Role.FINANCE,
        Role.READONLY,
        Role.FAMILY,
        Role.MAID,
    }
    write_roles = {Role.ADMIN, Role.OPERATIONS}
    entity_label = "placement"

    def get_queryset(self):
        queryset = Placement.objects.select_related(
            "client", "worker", "booking"
        ).filter(deleted_at__isnull=True)
        role = getattr(getattr(self.request, "user", None), "role", None)
        if role == Role.FAMILY:
            queryset = queryset.filter(client__user=self.request.user)
        elif role == Role.MAID:
            queryset = queryset.filter(worker__user=self.request.user)
        return queryset.order_by("-start_date")

    def perform_create(self, serializer):
        placement = serializer.save()
        if placement.booking:
            placement.booking.status = "CONVERTED"
            placement.booking.save()
        previous_status = placement.worker.status
        placement.worker.status = "PLACED"
        placement.worker.save()
        WorkerStatusHistory.objects.create(
            worker=placement.worker,
            from_status=previous_status,
            to_status="PLACED",
            reason=f"Placed with {placement.client.client_number}.",
            changed_by_name=self.request.user.display_name,
        )
        log_action(
            actor=self.request.user,
            action="PLACEMENT_CREATED",
            entity="operations.Placement",
            entity_id=placement.id,
            metadata={"placement_number": placement.placement_number},
            request=self.request,
        )

    @action(detail=True, methods=["get"], url_path="guarantee")
    def guarantee(self, request, pk=None):
        placement = self.get_object()
        return Response(
            {
                "placement_number": placement.placement_number,
                "start_date": placement.start_date,
                "guarantee_days": placement.guarantee_days,
                "guarantee_end_date": placement.guarantee_end_date,
                "guarantee_status": placement.guarantee_status,
                "policy_confirmed": False,
            }
        )


class FollowUpViewSet(AuditedModelViewSet):
    serializer_class = FollowUpSerializer
    permission_classes = [RolePermission]
    read_roles = {
        Role.ADMIN,
        Role.OPERATIONS,
        Role.CUSTOMER_CARE,
        Role.READONLY,
        Role.FAMILY,
        Role.MAID,
    }
    write_roles = {Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE}
    entity_label = "follow-up"

    def get_queryset(self):
        queryset = FollowUp.objects.select_related(
            "placement__client", "placement__worker"
        ).filter(deleted_at__isnull=True)
        role = getattr(getattr(self.request, "user", None), "role", None)
        if role == Role.FAMILY:
            queryset = queryset.filter(placement__client__user=self.request.user)
        elif role == Role.MAID:
            queryset = queryset.filter(placement__worker__user=self.request.user)
        return queryset.order_by("due_date")

    def perform_create(self, serializer):
        follow_up = serializer.save(
            created_by_name=self.request.user.display_name,
            staff_name=serializer.validated_data.get("staff_name")
            or self.request.user.display_name,
        )
        log_action(
            actor=self.request.user,
            action="FOLLOWUP_CREATED",
            entity="operations.FollowUp",
            entity_id=follow_up.id,
            metadata={"placement": str(follow_up.placement_id), "due": str(follow_up.due_date)},
            request=self.request,
        )

    @action(detail=True, methods=["post"], url_path="complete")
    def complete(self, request, pk=None):
        follow_up = self.get_object()
        if follow_up.completed_at:
            return Response(
                {"detail": "This follow-up is already complete."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        follow_up.completed_at = timezone.now()
        follow_up.staff_name = follow_up.staff_name or request.user.display_name
        for field in ("contact_method", "outcome", "satisfaction", "notes", "next_follow_up_date"):
            if request.data.get(field) not in (None, ""):
                setattr(follow_up, field, request.data[field])
        follow_up.save()

        if follow_up.next_follow_up_date:
            FollowUp.objects.create(
                placement=follow_up.placement,
                due_date=follow_up.next_follow_up_date,
                created_by_name=request.user.display_name,
            )
        log_action(
            actor=request.user,
            action="FOLLOWUP_COMPLETED",
            entity="operations.FollowUp",
            entity_id=follow_up.id,
            metadata={"outcome": follow_up.outcome},
            request=request,
        )
        return Response(self.get_serializer(follow_up).data)


class IncidentViewSet(AuditedModelViewSet):
    serializer_class = IncidentSerializer
    permission_classes = [RolePermission]
    read_roles = {Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE, Role.READONLY}
    write_roles = {Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE}
    entity_label = "incident"

    def get_queryset(self):
        return Incident.objects.select_related("placement").filter(
            deleted_at__isnull=True
        ).order_by("-reported_at")

    def perform_create(self, serializer):
        incident = serializer.save(reported_by_name=self.request.user.display_name)
        log_action(
            actor=self.request.user,
            action="INCIDENT_CREATED",
            entity="operations.Incident",
            entity_id=incident.id,
            metadata={"placement": str(incident.placement_id)},
            request=self.request,
        )


class ReplacementCaseViewSet(AuditedModelViewSet):
    serializer_class = ReplacementCaseSerializer
    permission_classes = [RolePermission]
    read_roles = {
        Role.ADMIN,
        Role.OPERATIONS,
        Role.CUSTOMER_CARE,
        Role.READONLY,
        Role.FAMILY,
    }
    write_roles = {Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE, Role.FAMILY}
    entity_label = "replacement case"

    def get_queryset(self):
        queryset = ReplacementCase.objects.select_related(
            "placement", "client", "original_worker", "replacement_worker"
        ).filter(deleted_at__isnull=True)
        role = getattr(getattr(self.request, "user", None), "role", None)
        if role == Role.FAMILY:
            queryset = queryset.filter(client__user=self.request.user)
        return queryset.order_by("-created_at")

    def check_permissions(self, request):
        super().check_permissions(request)
        if request.user.role == Role.FAMILY and request.method not in SAFE_METHODS + ("POST",):
            raise PermissionDenied("Clients may open a replacement case but cannot edit it.")

    def perform_create(self, serializer):
        placement = serializer.validated_data["placement"]
        case = serializer.save(
            client=placement.client,
            original_worker=placement.worker,
            guarantee_eligible=placement.guarantee_status == "IN_GUARANTEE",
            status="OPEN",
        )
        log_action(
            actor=self.request.user,
            action="REPLACEMENT_OPENED",
            entity="operations.ReplacementCase",
            entity_id=case.id,
            metadata={"case_number": case.case_number, "placement": placement.placement_number},
            request=self.request,
        )

    @action(detail=True, methods=["post"], url_path="review")
    def review(self, request, pk=None):
        if request.user.role not in {Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE}:
            raise PermissionDenied("Only a manager can review replacement eligibility.")
        case = self.get_object()
        serializer = ReplacementReviewSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        decision = serializer.validated_data["decision"]
        reason = serializer.validated_data.get("decision_reason", "").strip()
        if decision == "NOT_ELIGIBLE" and not reason:
            return Response(
                {"decision_reason": "Record the reason for an ineligible decision."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        case.eligibility_decision = decision
        case.decision_reason = reason
        case.approved_by_name = request.user.display_name
        case.guarantee_eligible = serializer.validated_data.get(
            "guarantee_confirmed", decision == "ELIGIBLE"
        )
        case.status = "APPROVED" if decision == "ELIGIBLE" else "REJECTED"
        case.save()
        log_action(
            actor=request.user,
            action="REPLACEMENT_REVIEWED",
            entity="operations.ReplacementCase",
            entity_id=case.id,
            metadata={"case_number": case.case_number, "decision": decision},
            request=request,
        )
        return Response(self.get_serializer(case).data)

    @action(detail=True, methods=["post"], url_path="assign")
    def assign(self, request, pk=None):
        if request.user.role not in {Role.ADMIN, Role.OPERATIONS}:
            raise PermissionDenied("Only operations or an administrator can assign a replacement.")
        case = self.get_object()
        if case.eligibility_decision != "ELIGIBLE":
            return Response(
                {"detail": "Eligibility must be approved before assigning a backup worker."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = ReplacementAssignSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        worker = serializer.validated_data["replacement_worker"]
        if worker.verification_status not in {"VERIFIED", "EXCEPTION"}:
            return Response(
                {"replacement_worker": "The backup worker must be verified."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        replacement_date = serializer.validated_data.get("replacement_date") or timezone.localdate()
        placement = Placement.objects.create(
            booking=case.placement.booking,
            client=case.client,
            worker=worker,
            start_date=replacement_date,
            terms=f"Replacement for {case.placement.placement_number} ({case.case_number})",
            status="ACTIVE",
            guarantee_days=case.placement.guarantee_days,
            responsible_staff_name=request.user.display_name,
            notes=serializer.validated_data.get("notes", ""),
        )
        previous_worker_status = worker.status
        worker.status = "PLACED"
        worker.save()
        WorkerStatusHistory.objects.create(
            worker=worker,
            from_status=previous_worker_status,
            to_status="PLACED",
            reason=f"Replacement assignment for {case.case_number}.",
            changed_by_name=request.user.display_name,
        )
        case.placement.status = "REPLACEMENT_REQUESTED"
        case.placement.save()
        case.replacement_worker = worker
        case.replacement_date = replacement_date
        case.replacement_placement = placement
        case.status = "ASSIGNED"
        case.save()
        log_action(
            actor=request.user,
            action="REPLACEMENT_ASSIGNED",
            entity="operations.ReplacementCase",
            entity_id=case.id,
            metadata={
                "case_number": case.case_number,
                "replacement_placement": placement.placement_number,
            },
            request=request,
        )
        data = self.get_serializer(case).data
        data["replacement_placement_number"] = placement.placement_number
        return Response(data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=["post"], url_path="resolve")
    def resolve(self, request, pk=None):
        if request.user.role not in {Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE}:
            raise PermissionDenied("Only staff can resolve a replacement case.")
        case = self.get_object()
        case.status = "RESOLVED"
        case.resolution_notes = request.data.get("resolution_notes", case.resolution_notes)
        case.client_confirmed = bool(request.data.get("client_confirmed", case.client_confirmed))
        case.save()
        log_action(
            actor=request.user,
            action="REPLACEMENT_RESOLVED",
            entity="operations.ReplacementCase",
            entity_id=case.id,
            metadata={"case_number": case.case_number},
            request=request,
        )
        return Response(self.get_serializer(case).data)
