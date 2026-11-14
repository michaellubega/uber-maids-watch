from datetime import timedelta

from django.utils import timezone
from rest_framework.test import APIClient, APITestCase

from catalog.models import Service
from clients.models import Client
from core.models import Role, User
from workers.models import Worker


class ApiTestCase(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username="admin-test", password="Pass1234!", role=Role.ADMIN
        )
        self.ops = User.objects.create_user(
            username="ops-test", password="Pass1234!", role=Role.OPERATIONS
        )
        self.verifier = User.objects.create_user(
            username="verify-test", password="Pass1234!", role=Role.VERIFICATION
        )
        self.care = User.objects.create_user(
            username="care-test", password="Pass1234!", role=Role.CUSTOMER_CARE
        )
        self.finance = User.objects.create_user(
            username="finance-test", password="Pass1234!", role=Role.FINANCE
        )
        self.readonly = User.objects.create_user(
            username="read-test", password="Pass1234!", role=Role.READONLY
        )
        self.family = User.objects.create_user(
            username="family-test", password="Pass1234!", role=Role.FAMILY
        )
        self.maid = User.objects.create_user(
            username="maid-test", password="Pass1234!", role=Role.MAID
        )

        self.service = Service.objects.create(
            name="Maid / house helper",
            category="MAID",
            pricing_type="MONTHLY",
            public_visibility=True,
        )
        self.client_record = Client.objects.create(
            full_name="Test Household",
            phone="0770000001",
            area="Kololo",
            user=self.family,
        )
        self.worker = Worker.objects.create(
            full_name="Test Worker",
            phone="0770000002",
            area="Ntinda",
            status="AVAILABLE",
            verification_status="VERIFIED",
            verified_at=timezone.now(),
            verified_by_name="Test verifier",
            user=self.maid,
        )
        self.today = timezone.localdate()

    def auth(self, user):
        client = APIClient()
        client.force_authenticate(user=user)
        return client

    def make_placement(self, *, start_date=None, worker=None):
        from operations.models import Placement

        return Placement.objects.create(
            client=self.client_record,
            worker=worker or self.worker,
            start_date=start_date or (self.today - timedelta(days=2)),
            status="ACTIVE",
            guarantee_days=14,
            responsible_staff_name="Ops",
        )
