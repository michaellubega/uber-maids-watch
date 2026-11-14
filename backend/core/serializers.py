from django.contrib.auth import get_user_model
from rest_framework import serializers

from core.models import AuditLog, Role

User = get_user_model()


class UserSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, required=False, min_length=8)
    display_name = serializers.CharField(read_only=True)

    class Meta:
        model = User
        fields = (
            "id",
            "username",
            "first_name",
            "last_name",
            "display_name",
            "email",
            "phone_number",
            "role",
            "is_active",
            "is_staff",
            "last_login",
            "password",
        )
        read_only_fields = ("id", "is_staff", "last_login")

    def validate_role(self, value):
        request = self.context.get("request")
        # Only administrators may mint another administrator.
        if (
            request
            and request.user.is_authenticated
            and request.user.role != Role.ADMIN
            and value == Role.ADMIN
        ):
            raise serializers.ValidationError("Only an administrator can assign the ADMIN role.")
        return value

    def create(self, validated_data):
        password = validated_data.pop("password", None)
        if not password:
            raise serializers.ValidationError({"password": "A password is required."})
        user = User(**validated_data)
        user.set_password(password)
        user.save()
        return user

    def update(self, instance, validated_data):
        password = validated_data.pop("password", None)
        user = super().update(instance, validated_data)
        if password:
            user.set_password(password)
            user.save(update_fields=["password"])
        return user


class AuditLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = AuditLog
        fields = (
            "id",
            "actor_name",
            "action",
            "entity",
            "entity_id",
            "metadata",
            "ip_address",
            "created_at",
        )
        read_only_fields = fields
