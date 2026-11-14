from django.conf import settings
from rest_framework import serializers

from core.models import Role
from workers.models import (
    VerificationCheck,
    Worker,
    WorkerDocument,
    WorkerReference,
    WorkerStatusHistory,
)

SENSITIVE_ROLES = {Role.ADMIN, Role.OPERATIONS, Role.VERIFICATION}
SENSITIVE_FIELDS = (
    "date_of_birth",
    "national_id_type",
    "national_id_number",
    "emergency_contact_name",
    "emergency_contact_phone",
    "notes",
    "exception_reason",
)


class WorkerSerializer(serializers.ModelSerializer):
    class Meta:
        model = Worker
        fields = (
            "id",
            "worker_number",
            "full_name",
            "phone",
            "area",
            "date_of_birth",
            "photo",
            "national_id_type",
            "national_id_number",
            "emergency_contact_name",
            "emergency_contact_phone",
            "skills",
            "languages",
            "service_categories",
            "experience_years",
            "expected_salary_ugx",
            "availability",
            "status",
            "verification_status",
            "verified_at",
            "verified_by_name",
            "exception_reason",
            "notes",
            "user",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )
        read_only_fields = (
            "id",
            "worker_number",
            "verified_at",
            "verified_by_name",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )
        extra_kwargs = {"user": {"required": False, "allow_null": True}}

    def to_representation(self, instance):
        data = super().to_representation(instance)
        request = self.context.get("request")
        user = getattr(request, "user", None)
        allowed = bool(
            user
            and user.is_authenticated
            and (user.role in SENSITIVE_ROLES or instance.user_id == user.id)
        )
        if not allowed:
            for field in SENSITIVE_FIELDS:
                data.pop(field, None)
        if data.get("photo"):
            # Never expose a storage path or public URL; documents/photos are
            # fetched through an authorised endpoint.
            data["photo"] = None
        return data

    def validate_status(self, value):
        instance = self.instance
        if value == "VERIFIED":
            current = instance.verification_status if instance else "PENDING"
            if current not in {"VERIFIED", "EXCEPTION"}:
                raise serializers.ValidationError(
                    "Record the verification outcome before marking a worker verified."
                )
        return value

    def update(self, instance, validated_data):
        request = self.context.get("request")
        if (
            validated_data.get("verification_status") == "VERIFIED"
            and instance.verification_status != "VERIFIED"
        ):
            from django.utils import timezone

            validated_data["verified_at"] = timezone.now()
            if request and request.user.is_authenticated:
                validated_data["verified_by_name"] = request.user.display_name
        return super().update(instance, validated_data)


class WorkerMinimalSerializer(serializers.ModelSerializer):
    """Fields safe for a client's placement view and for the public website."""

    class Meta:
        model = Worker
        fields = (
            "id",
            "worker_number",
            "full_name",
            "area",
            "skills",
            "languages",
            "experience_years",
            "status",
            "verification_status",
        )


class WorkerReferenceSerializer(serializers.ModelSerializer):
    class Meta:
        model = WorkerReference
        fields = ("id", "worker", "full_name", "relationship", "phone", "address", "notes")
        read_only_fields = ("id",)


class VerificationCheckSerializer(serializers.ModelSerializer):
    class Meta:
        model = VerificationCheck
        fields = (
            "id",
            "worker",
            "name",
            "status",
            "notes",
            "checked_by_name",
            "checked_at",
            "created_at",
        )
        read_only_fields = ("id", "created_at")


class WorkerStatusHistorySerializer(serializers.ModelSerializer):
    class Meta:
        model = WorkerStatusHistory
        fields = (
            "id",
            "worker",
            "from_status",
            "to_status",
            "reason",
            "changed_by_name",
            "changed_at",
        )
        read_only_fields = fields


class WorkerDocumentSerializer(serializers.ModelSerializer):
    download_url = serializers.SerializerMethodField()

    class Meta:
        model = WorkerDocument
        fields = (
            "id",
            "worker",
            "document_type",
            "title",
            "uploaded_by_name",
            "verified",
            "uploaded_at",
            "download_url",
            "file",
        )
        extra_kwargs = {"file": {"write_only": True}}
        read_only_fields = ("id", "uploaded_by_name", "uploaded_at")

    def get_download_url(self, obj) -> str:
        return f"/api/worker-documents/{obj.pk}/download/"

    def validate_file(self, value):
        import os

        extension = os.path.splitext(value.name)[1].lower()
        if extension not in settings.ALLOWED_DOCUMENT_EXTENSIONS:
            raise serializers.ValidationError(
                "Allowed file types: " + ", ".join(sorted(settings.ALLOWED_DOCUMENT_EXTENSIONS))
            )
        if value.size > settings.MAX_DOCUMENT_BYTES:
            raise serializers.ValidationError(
                f"File is larger than {settings.MAX_DOCUMENT_BYTES // (1024 * 1024)} MB."
            )
        return value
