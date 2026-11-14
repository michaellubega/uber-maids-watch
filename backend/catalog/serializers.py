from rest_framework import serializers

from catalog.models import Service


class ServiceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Service
        fields = (
            "id",
            "name",
            "category",
            "description",
            "pricing_type",
            "price_min_ugx",
            "price_max_ugx",
            "requirements",
            "active",
            "public_visibility",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )
        read_only_fields = (
            "id",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )
