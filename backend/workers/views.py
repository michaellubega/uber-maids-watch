from django.http import FileResponse, Http404
from django.shortcuts import get_object_or_404
from django.utils import timezone
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView

from core.audit import log_action
from core.models import Role, STAFF_ROLES
from core.permissions import RolePermission
from core.viewsets import AuditedModelViewSet
from workers.models import (
    VerificationCheck,
    Worker,
    WorkerDocument,
    WorkerReference,
    WorkerStatusHistory,
)
from workers.serializers import (
    VerificationCheckSerializer,
    WorkerDocumentSerializer,
    WorkerMinimalSerializer,
    WorkerReferenceSerializer,
    WorkerSerializer,
    WorkerStatusHistorySerializer,
)

DOCUMENT_ROLES = {Role.ADMIN, Role.OPERATIONS, Role.VERIFICATION}


class WorkerViewSet(AuditedModelViewSet):
    serializer_class = WorkerSerializer
    permission_classes = [RolePermission]
    read_roles = {
        Role.ADMIN,
        Role.OPERATIONS,
        Role.VERIFICATION,
        Role.CUSTOMER_CARE,
        Role.FINANCE,
        Role.READONLY,
        Role.MAID,
    }
    write_roles = {Role.ADMIN, Role.OPERATIONS, Role.VERIFICATION}
    entity_label = "worker"

    def get_queryset(self):
        queryset = Worker.objects.select_related("user").filter(deleted_at__isnull=True)
        role = getattr(getattr(self.request, "user", None), "role", None)
        if role == Role.MAID:
            queryset = queryset.filter(user=self.request.user)
        return queryset.order_by("full_name")

    def perform_create(self, serializer):
        worker = serializer.save()
        WorkerStatusHistory.objects.create(
            worker=worker,
            from_status="",
            to_status=worker.status,
            changed_by_name=self.request.user.display_name,
        )
        log_action(
            actor=self.request.user,
            action="WORKER_CREATED",
            entity="workers.Worker",
            entity_id=worker.id,
            metadata={"worker_number": worker.worker_number},
            request=self.request,
        )

    def perform_update(self, serializer):
        previous_status = serializer.instance.status
        worker = serializer.save()
        if worker.status != previous_status:
            WorkerStatusHistory.objects.create(
                worker=worker,
                from_status=previous_status,
                to_status=worker.status,
                changed_by_name=self.request.user.display_name,
            )
        log_action(
            actor=self.request.user,
            action="WORKER_UPDATED",
            entity="workers.Worker",
            entity_id=worker.id,
            metadata={
                "worker_number": worker.worker_number,
                "status": worker.status,
                "verification_status": worker.verification_status,
            },
            request=self.request,
        )

    @action(detail=True, methods=["post"], url_path="verify")
    def verify(self, request, pk=None):
        worker = self.get_object()
        checks_complete = bool(request.data.get("checks_complete"))
        exception_reason = (request.data.get("exception_reason") or "").strip()
        if not checks_complete and not exception_reason:
            return Response(
                {
                    "detail": (
                        "Required verification checks must be complete, or an "
                        "authorised exception reason must be recorded."
                    )
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        previous_status = worker.status
        worker.verification_status = "EXCEPTION" if exception_reason else "VERIFIED"
        worker.exception_reason = exception_reason
        worker.verified_at = timezone.now()
        worker.verified_by_name = request.user.display_name
        if worker.status in {"APPLICANT", "DOCUMENTS_PENDING", "UNDER_VERIFICATION"}:
            worker.status = "VERIFIED"
        worker.save()

        WorkerStatusHistory.objects.create(
            worker=worker,
            from_status=previous_status,
            to_status=worker.status,
            reason=exception_reason or "Verification checks completed.",
            changed_by_name=request.user.display_name,
        )
        log_action(
            actor=request.user,
            action="WORKER_VERIFIED",
            entity="workers.Worker",
            entity_id=worker.id,
            metadata={
                "worker_number": worker.worker_number,
                "exception": bool(exception_reason),
            },
            request=request,
        )
        return Response(WorkerSerializer(worker, context={"request": request}).data)

    @action(detail=True, methods=["get"], url_path="history")
    def history(self, request, pk=None):
        worker = self.get_object()
        rows = worker.status_history.all()
        return Response(WorkerStatusHistorySerializer(rows, many=True).data)

    @action(detail=True, methods=["get"], url_path="documents")
    def documents(self, request, pk=None):
        worker = self.get_object()
        rows = worker.documents.all()
        return Response(
            WorkerDocumentSerializer(rows, many=True, context={"request": request}).data
        )


class WorkerDocumentViewSet(viewsets.ModelViewSet):
    serializer_class = WorkerDocumentSerializer
    permission_classes = [RolePermission]
    read_roles = DOCUMENT_ROLES | {Role.MAID}
    write_roles = DOCUMENT_ROLES
    http_method_names = ["get", "post", "patch", "delete", "head", "options"]

    def get_queryset(self):
        queryset = WorkerDocument.objects.select_related("worker")
        role = getattr(getattr(self.request, "user", None), "role", None)
        if role == Role.MAID:
            queryset = queryset.filter(worker__user=self.request.user)
        worker_id = self.request.query_params.get("worker")
        if worker_id:
            queryset = queryset.filter(worker_id=worker_id)
        return queryset

    def perform_create(self, serializer):
        document = serializer.save(uploaded_by_name=self.request.user.display_name)
        log_action(
            actor=self.request.user,
            action="DOCUMENT_UPLOADED",
            entity="workers.WorkerDocument",
            entity_id=document.id,
            metadata={
                "worker": str(document.worker_id),
                "document_type": document.document_type,
            },
            request=self.request,
        )


class WorkerReferenceViewSet(AuditedModelViewSet):
    serializer_class = WorkerReferenceSerializer
    permission_classes = [RolePermission]
    read_roles = DOCUMENT_ROLES
    write_roles = DOCUMENT_ROLES
    entity_label = "worker reference"

    def get_queryset(self):
        queryset = WorkerReference.objects.select_related("worker")
        worker_id = self.request.query_params.get("worker")
        return queryset.filter(worker_id=worker_id) if worker_id else queryset


class VerificationCheckViewSet(AuditedModelViewSet):
    serializer_class = VerificationCheckSerializer
    permission_classes = [RolePermission]
    read_roles = DOCUMENT_ROLES | {Role.READONLY}
    write_roles = DOCUMENT_ROLES
    entity_label = "verification check"

    def get_queryset(self):
        queryset = VerificationCheck.objects.select_related("worker")
        worker_id = self.request.query_params.get("worker")
        return queryset.filter(worker_id=worker_id) if worker_id else queryset


class WorkerDocumentDownloadView(APIView):
    permission_classes = [RolePermission]
    read_roles = DOCUMENT_ROLES | {Role.MAID}

    @extend_schema(responses={200: OpenApiTypes.BINARY})
    def get(self, request, pk):
        document = get_object_or_404(WorkerDocument.objects.select_related("worker"), pk=pk)
        if request.user.role == Role.MAID and document.worker.user_id != request.user.id:
            raise Http404
        if not document.file:
            raise Http404("File not found.")
        log_action(
            actor=request.user,
            action="DOCUMENT_DOWNLOADED",
            entity="workers.WorkerDocument",
            entity_id=document.id,
            metadata={"worker": str(document.worker_id)},
            request=request,
        )
        document.file.open("rb")
        return FileResponse(
            document.file,
            as_attachment=True,
            filename=document.file.name.rsplit("/", 1)[-1],
        )
