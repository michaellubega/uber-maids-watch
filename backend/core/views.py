"""Health, session, dashboard and user-administration endpoints."""

from django.contrib.auth import get_user_model
from django.db import connection
from django.utils import timezone
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import status, viewsets
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView

from core.audit import log_action
from core.models import AuditLog, Role, STAFF_ROLES
from core.permissions import IsAdmin
from core.serializers import AuditLogSerializer, UserSerializer

User = get_user_model()


class LoginView(TokenObtainPairView):
    """JWT login that records successful sign-ins in the audit trail."""

    def post(self, request, *args, **kwargs):
        response = super().post(request, *args, **kwargs)
        if response.status_code == 200:
            username = request.data.get("username", "")
            log_action(
                actor=User.objects.filter(username=username).first(),
                action="LOGIN",
                entity="core.User",
                entity_id=username,
                metadata={"username": username},
                request=request,
            )
        return response


class HealthView(APIView):
    """Unauthenticated liveness probe used by Docker, monitoring and the app."""

    permission_classes = [AllowAny]
    authentication_classes = []

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                cursor.fetchone()
            database = "ok"
        except Exception:  # pragma: no cover - only on infrastructure failure
            database = "unavailable"
        payload = {
            "status": "ok" if database == "ok" else "degraded",
            "service": "uber-maids-watch-api",
            "version": "0.2.0",
            "database": database,
            "timestamp": timezone.now().isoformat(),
        }
        return Response(
            payload,
            status=status.HTTP_200_OK if database == "ok" else status.HTTP_503_SERVICE_UNAVAILABLE,
        )


class MeView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        user = request.user
        return Response(
            {
                "user": UserSerializer(user).data,
                "capabilities": {
                    "is_staff": user.role in STAFF_ROLES,
                    "is_admin": user.role == Role.ADMIN,
                    "can_write": {
                        "workers": user.role in {Role.ADMIN, Role.OPERATIONS, Role.VERIFICATION},
                        "clients": user.role in {Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE},
                        "services": user.role == Role.ADMIN,
                        "bookings": user.role in {
                            Role.ADMIN,
                            Role.OPERATIONS,
                            Role.CUSTOMER_CARE,
                            Role.FAMILY,
                        },
                        "placements": user.role in {Role.ADMIN, Role.OPERATIONS},
                        "followups": user.role in {Role.ADMIN, Role.OPERATIONS, Role.CUSTOMER_CARE},
                        "replacements": user.role in {
                            Role.ADMIN,
                            Role.OPERATIONS,
                            Role.CUSTOMER_CARE,
                            Role.FAMILY,
                        },
                        "payments": user.role in {Role.ADMIN, Role.FINANCE},
                    },
                },
                "server_time": timezone.now().isoformat(),
            }
        )


class DashboardSummaryView(APIView):
    permission_classes = [IsAuthenticated]

    @extend_schema(responses=OpenApiTypes.OBJECT)
    def get(self, request):
        from clients.models import Client
        from operations.models import (
            Booking,
            FollowUp,
            Placement,
            ReplacementCase,
        )
        from payments.models import Payment
        from workers.models import Worker

        user = request.user
        today = timezone.localdate()

        if user.role in STAFF_ROLES:
            payload = {
                "scope": "organisation",
                "workers_total": Worker.objects.filter(deleted_at__isnull=True).count(),
                "workers_available": Worker.objects.filter(
                    status="AVAILABLE", deleted_at__isnull=True
                ).count(),
                "workers_awaiting_verification": Worker.objects.filter(
                    verification_status__in=["PENDING", "IN_PROGRESS"],
                    deleted_at__isnull=True,
                ).count(),
                "clients_total": Client.objects.filter(deleted_at__isnull=True).count(),
                "new_bookings": Booking.objects.filter(
                    status="NEW", deleted_at__isnull=True
                ).count(),
                "confirmed_bookings": Booking.objects.filter(
                    status="CONFIRMED", deleted_at__isnull=True
                ).count(),
                "active_placements": Placement.objects.filter(
                    status="ACTIVE", deleted_at__isnull=True
                ).count(),
                "followups_due_today": FollowUp.objects.filter(
                    due_date=today, completed_at__isnull=True, deleted_at__isnull=True
                ).count(),
                "followups_overdue": FollowUp.objects.filter(
                    due_date__lt=today, completed_at__isnull=True, deleted_at__isnull=True
                ).count(),
                "open_replacements": ReplacementCase.objects.filter(
                    status__in=["OPEN", "REVIEWING"],
                    deleted_at__isnull=True,
                ).count(),
                "payments_outstanding": Payment.objects.filter(
                    status__in=["PENDING", "PARTIAL"], deleted_at__isnull=True
                ).count(),
            }
        elif user.role == Role.FAMILY:
            client = getattr(user, "client_profile", None)
            bookings = Booking.objects.filter(client=client) if client else Booking.objects.none()
            placements = Placement.objects.filter(client=client) if client else Placement.objects.none()
            payments = Payment.objects.filter(client=client) if client else Payment.objects.none()
            payload = {
                "scope": "client",
                "client_number": getattr(client, "client_number", ""),
                "open_bookings": bookings.exclude(
                    status__in=["CANCELLED", "CLOSED"]
                ).count(),
                "active_placements": placements.filter(status="ACTIVE").count(),
                "payments_due": payments.filter(status__in=["PENDING", "PARTIAL"]).count(),
                "replacements_open": ReplacementCase.objects.filter(
                    client=client, status__in=["OPEN", "REVIEWING"]
                ).count()
                if client
                else 0,
            }
        else:  # MAID
            worker = getattr(user, "worker_profile", None)
            placements = Placement.objects.filter(worker=worker) if worker else Placement.objects.none()
            payload = {
                "scope": "worker",
                "worker_number": getattr(worker, "worker_number", ""),
                "worker_status": getattr(worker, "status", ""),
                "verification_status": getattr(worker, "verification_status", ""),
                "active_placements": placements.filter(status="ACTIVE").count(),
                "followups_due": FollowUp.objects.filter(
                    placement__worker=worker,
                    completed_at__isnull=True,
                    due_date__lte=today,
                ).count()
                if worker
                else 0,
            }
        return Response(payload)


class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all().order_by("username")
    serializer_class = UserSerializer
    permission_classes = [IsAdmin]
    http_method_names = ["get", "post", "patch", "put", "head", "options"]

    def perform_create(self, serializer):
        user = serializer.save()
        log_action(
            actor=self.request.user,
            action="USER_CREATED",
            entity="core.User",
            entity_id=user.id,
            metadata={"username": user.username, "role": user.role},
            request=self.request,
        )

    def perform_update(self, serializer):
        user = serializer.save()
        log_action(
            actor=self.request.user,
            action="USER_UPDATED",
            entity="core.User",
            entity_id=user.id,
            metadata={"username": user.username, "role": user.role, "active": user.is_active},
            request=self.request,
        )


class AuditLogViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = AuditLog.objects.select_related("actor").all()
    serializer_class = AuditLogSerializer
    permission_classes = [IsAdmin]
