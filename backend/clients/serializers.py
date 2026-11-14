from django.contrib.auth import get_user_model
from rest_framework import serializers

from clients.models import Client

User = get_user_model()


class ClientSerializer(serializers.ModelSerializer):
    user = serializers.PrimaryKeyRelatedField(
        queryset=User.objects.filter(role="FAMILY"), required=False, allow_null=True
    )

    class Meta:
        model = Client
        fields = (
            "id",
            "client_number",
            "full_name",
            "phone",
            "email",
            "area",
            "preferred_contact",
            "notes",
            "status",
            "user",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )
        read_only_fields = (
            "id",
            "client_number",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )


class ClientSummarySerializer(serializers.ModelSerializer):
    """Minimal client record safe to mirror on a maid's device."""

    class Meta:
        model = Client
        fields = ("id", "client_number", "full_name", "area")
