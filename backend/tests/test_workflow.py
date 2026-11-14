from datetime import timedelta

from django.utils import timezone

from operations.models import (
    Booking,
    FollowUp,
    Placement,
    ReplacementCase,
)
from tests.base import ApiTestCase
from workers.models import Worker


class BookingWorkflowTests(ApiTestCase):
    def test_family_can_create_booking_for_own_client(self):
        response = self.auth(self.family).post(
            "/api/bookings/",
            {
                "service": str(self.service.pk),
                "requested_start_date": str(self.today + timedelta(days=3)),
                "location": "Kololo",
                "requirements": "Childcare",
                "client": "00000000-0000-0000-0000-000000000000",
                "status": "CONFIRMED",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(str(response.data["client"]), str(self.client_record.pk))
        self.assertEqual(response.data["status"], "NEW")
        self.assertTrue(response.data["booking_number"].startswith("B-"))

    def test_care_can_confirm_booking(self):
        booking = Booking.objects.create(
            client=self.client_record, service=self.service, status="NEW"
        )
        response = self.auth(self.care).post(
            f"/api/bookings/{booking.pk}/confirm/",
            {"assigned_staff_name": "Joy"},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        booking.refresh_from_db()
        self.assertEqual(booking.status, "CONFIRMED")
        self.assertIsNotNone(booking.confirmed_at)

    def test_family_cannot_confirm_booking(self):
        booking = Booking.objects.create(
            client=self.client_record, service=self.service, status="NEW"
        )
        response = self.auth(self.family).post(
            f"/api/bookings/{booking.pk}/confirm/", {}, format="json"
        )
        self.assertEqual(response.status_code, 403)


class PlacementWorkflowTests(ApiTestCase):
    def test_placement_converts_booking_and_computes_guarantee(self):
        booking = Booking.objects.create(
            client=self.client_record, service=self.service, status="CONFIRMED"
        )
        start = self.today
        response = self.auth(self.ops).post(
            "/api/placements/",
            {
                "booking": str(booking.pk),
                "client": str(self.client_record.pk),
                "worker": str(self.worker.pk),
                "start_date": str(start),
                "status": "ACTIVE",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        booking.refresh_from_db()
        self.worker.refresh_from_db()
        self.assertEqual(booking.status, "CONVERTED")
        self.assertEqual(self.worker.status, "PLACED")
        self.assertEqual(
            response.data["guarantee_end_date"], str(start + timedelta(days=14))
        )
        self.assertEqual(response.data["guarantee_status"], "IN_GUARANTEE")

    def test_unverified_worker_cannot_be_placed(self):
        unverified = Worker.objects.create(
            full_name="Unverified", phone="0770", area="Kampala", status="AVAILABLE"
        )
        response = self.auth(self.ops).post(
            "/api/placements/",
            {
                "client": str(self.client_record.pk),
                "worker": str(unverified.pk),
                "start_date": str(self.today),
            },
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("worker", response.data)


class FollowUpTests(ApiTestCase):
    def test_complete_follow_up_and_schedule_next(self):
        placement = self.make_placement()
        follow_up = FollowUp.objects.create(
            placement=placement, due_date=self.today, created_by_name="Joy"
        )
        response = self.auth(self.care).post(
            f"/api/follow-ups/{follow_up.pk}/complete/",
            {
                "outcome": "CLIENT_SATISFIED",
                "satisfaction": 5,
                "notes": "Doing well",
                "next_follow_up_date": str(self.today + timedelta(days=7)),
            },
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        follow_up.refresh_from_db()
        self.assertIsNotNone(follow_up.completed_at)
        self.assertEqual(
            FollowUp.objects.filter(placement=placement, completed_at__isnull=True).count(),
            1,
        )


class ReplacementWorkflowTests(ApiTestCase):
    def test_expired_guarantee_is_flagged_and_review_requires_reason(self):
        placement = self.make_placement(start_date=self.today - timedelta(days=30))
        response = self.auth(self.care).post(
            "/api/replacement-cases/",
            {
                "placement": str(placement.pk),
                "problem_category": "WORKER_LEFT",
                "description": "Worker did not return.",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        case_id = response.data["id"]
        self.assertFalse(response.data["guarantee_eligible"])
        self.assertEqual(str(response.data["client"]), str(self.client_record.pk))

        review = self.auth(self.ops).post(
            f"/api/replacement-cases/{case_id}/review/",
            {"decision": "NOT_ELIGIBLE"},
            format="json",
        )
        self.assertEqual(review.status_code, 400)

        review = self.auth(self.ops).post(
            f"/api/replacement-cases/{case_id}/review/",
            {"decision": "NOT_ELIGIBLE", "decision_reason": "Outside guarantee window."},
            format="json",
        )
        self.assertEqual(review.status_code, 200, review.data)
        self.assertEqual(review.data["status"], "REJECTED")

    def test_eligible_case_can_be_assigned_to_backup_worker(self):
        placement = self.make_placement(start_date=self.today - timedelta(days=1))
        backup = Worker.objects.create(
            full_name="Backup Worker",
            phone="0770000003",
            area="Najjera",
            status="AVAILABLE",
            verification_status="VERIFIED",
        )
        case = ReplacementCase.objects.create(
            placement=placement,
            client=self.client_record,
            original_worker=self.worker,
            problem_category="CONDUCT",
            description="Client requested a replacement.",
            guarantee_eligible=True,
            eligibility_decision="ELIGIBLE",
            status="APPROVED",
        )
        response = self.auth(self.ops).post(
            f"/api/replacement-cases/{case.pk}/assign/",
            {
                "replacement_worker": str(backup.pk),
                "replacement_date": str(self.today),
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        case.refresh_from_db()
        placement.refresh_from_db()
        self.assertEqual(case.status, "ASSIGNED")
        self.assertEqual(placement.status, "REPLACEMENT_REQUESTED")
        self.assertIsNotNone(case.replacement_placement)
        self.assertEqual(case.replacement_placement.worker_id, backup.pk)
