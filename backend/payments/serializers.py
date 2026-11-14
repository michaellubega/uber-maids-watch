from rest_framework import serializers

from payments.models import Payment


class PaymentSerializer(serializers.ModelSerializer):
    client_name = serializers.CharField(source="client.full_name", read_only=True)
    client_number = serializers.CharField(source="client.client_number", read_only=True)
    is_outstanding = serializers.BooleanField(read_only=True)
    booking_number = serializers.CharField(source="booking.booking_number", read_only=True)
    placement_number = serializers.CharField(source="placement.placement_number", read_only=True)

    class Meta:
        model = Payment
        fields = (
            "id",
            "receipt_reference",
            "client",
            "client_name",
            "client_number",
            "booking",
            "booking_number",
            "placement",
            "placement_number",
            "amount_ugx",
            "currency",
            "payment_method",
            "reference",
            "status",
            "paid_at",
            "notes",
            "recorded_by_name",
            "is_outstanding",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )
        read_only_fields = (
            "id",
            "receipt_reference",
            "recorded_by_name",
            "paid_at",
            "created_at",
            "updated_at",
            "server_version",
            "change_seq",
            "deleted_at",
        )

    def validate_amount_ugx(self, value):
        if value <= 0:
            raise serializers.ValidationError("The amount must be greater than zero.")
        return value
