from datetime import timedelta

from payments.models import Payment
from tests.base import ApiTestCase


class PaymentTests(ApiTestCase):
    def test_finance_can_record_payment_and_receipt_is_generated(self):
        response = self.auth(self.finance).post(
            "/api/payments/",
            {
                "client": str(self.client_record.pk),
                "amount_ugx": "150000.00",
                "payment_method": "MOBILE_MONEY",
                "status": "PAID",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(response.data["receipt_reference"].startswith("RCPT-"))
        self.assertIsNotNone(response.data["paid_at"])

    def test_operations_cannot_record_payment(self):
        response = self.auth(self.ops).post(
            "/api/payments/",
            {
                "client": str(self.client_record.pk),
                "amount_ugx": "1000.00",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 403)

    def test_family_sees_only_own_payments(self):
        other_client = self.client_record.__class__.objects.create(
            full_name="Other household", phone="0770", area="Muyenga"
        )
        Payment.objects.create(
            client=self.client_record, amount_ugx=1000, recorded_by_name="Finance"
        )
        Payment.objects.create(
            client=other_client, amount_ugx=2000, recorded_by_name="Finance"
        )
        response = self.auth(self.family).get("/api/payments/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["count"], 1)
        self.assertEqual(
            str(response.data["results"][0]["client"]), str(self.client_record.pk)
        )

    def test_amount_must_be_positive(self):
        response = self.auth(self.finance).post(
            "/api/payments/",
            {"client": str(self.client_record.pk), "amount_ugx": "0.00"},
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("amount_ugx", response.data)
