"""Tests for the family and worker web portal."""

from django.urls import reverse
from django.utils import timezone

from clients.models import Client
from core.models import AuditLog, Role, User
from operations.models import Booking, Placement, ReplacementCase
from tests.base import ApiTestCase


class PortalAccessTests(ApiTestCase):
    def test_landing_page_is_public_and_branded(self):
        response = self.client.get(reverse("portal:landing"))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "Uber Maids Watch")
        self.assertContains(response, "Help Our Girls Practice")
        self.assertContains(response, "Maid / house helper")

    def test_anonymous_portal_page_redirects_to_login(self):
        response = self.client.get(reverse("portal:dashboard"))
        self.assertEqual(response.status_code, 302)
        self.assertIn(reverse("portal:login"), response["Location"])
        self.assertIn("next=", response["Location"])

    def test_staff_account_sees_desktop_notice(self):
        self.client.force_login(self.admin)
        response = self.client.get(reverse("portal:dashboard"))
        self.assertEqual(response.status_code, 403)
        self.assertContains(
            response,
            "Office accounts use the desktop application",
            status_code=403,
        )

    def test_staff_cannot_sign_in_to_portal(self):
        response = self.client.post(
            reverse("portal:login"),
            {"username": "admin-test", "password": "Pass1234!"},
        )
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "family and domestic-worker accounts")
        self.assertNotIn("_auth_user_id", self.client.session)

    def test_family_dashboard_is_scoped_to_their_record(self):
        other_client = Client.objects.create(
            full_name="Other Household", phone="0770000009", area="Muyenga"
        )
        other_worker = self.worker.__class__.objects.create(
            full_name="Other Worker", phone="0770000010", area="Kireka"
        )
        Placement.objects.create(
            client=other_client,
            worker=other_worker,
            start_date=self.today,
            status="ACTIVE",
            guarantee_days=14,
        )
        self.client.force_login(self.family)
        response = self.client.get(reverse("portal:dashboard"))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "Test Household")
        self.assertNotContains(response, "Other Household")

    def test_family_cannot_open_another_households_placement(self):
        other_client = Client.objects.create(
            full_name="Other Household", phone="0770000009", area="Muyenga"
        )
        placement = Placement.objects.create(
            client=other_client,
            worker=self.worker,
            start_date=self.today,
            status="ACTIVE",
            guarantee_days=14,
        )
        self.client.force_login(self.family)
        response = self.client.get(
            reverse("portal:placement_detail", args=[placement.pk])
        )
        self.assertEqual(response.status_code, 404)

    def test_maid_cannot_open_family_only_pages(self):
        self.client.force_login(self.maid)
        for name in ("payments", "replacements", "bookings"):
            response = self.client.get(reverse(f"portal:{name}"))
            self.assertEqual(response.status_code, 403, name)

    def test_maid_placement_detail_does_not_expose_client_phone(self):
        placement = self.make_placement()
        self.client.force_login(self.maid)
        response = self.client.get(
            reverse("portal:placement_detail", args=[placement.pk])
        )
        self.assertEqual(response.status_code, 200)
        self.assertNotContains(response, self.client_record.phone)

    def test_logout_requires_post_and_clears_session(self):
        self.client.force_login(self.family)
        self.assertEqual(self.client.get(reverse("portal:logout")).status_code, 405)
        response = self.client.post(reverse("portal:logout"))
        self.assertEqual(response.status_code, 302)
        self.assertNotIn("_auth_user_id", self.client.session)

    def test_login_next_redirect_cannot_leave_the_site(self):
        response = self.client.post(
            reverse("portal:login") + "?next=https://evil.example/steal",
            {"username": "family-test", "password": "Pass1234!"},
        )
        self.assertEqual(response.status_code, 302)
        self.assertEqual(response["Location"], reverse("portal:dashboard"))

    def test_account_without_linked_record_gets_guidance(self):
        lonely = User.objects.create_user(
            username="family-nolink", password="Pass1234!", role=Role.FAMILY
        )
        self.client.force_login(lonely)
        response = self.client.get(reverse("portal:dashboard"))
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "not linked yet")
        self.assertContains(response, "family-nolink")


class PortalBookingTests(ApiTestCase):
    def test_family_can_send_a_booking_request(self):
        self.client.force_login(self.family)
        response = self.client.post(
            reverse("portal:booking_new"),
            {
                "service": self.service.pk,
                "requested_start_date": "2026-12-01",
                "location": "Kololo",
                "schedule": "Monday to Saturday",
                "requirements": "Childcare for two children.",
                "budget_ugx": "600000",
                "special_instructions": "Call after 6pm.",
            },
        )
        self.assertEqual(response.status_code, 302)
        booking = Booking.objects.get(client=self.client_record)
        self.assertEqual(booking.service, self.service)
        self.assertEqual(booking.status, "NEW")
        self.assertEqual(booking.created_by_name, self.family.display_name)
        self.assertTrue(booking.booking_number)
        self.assertTrue(
            AuditLog.objects.filter(
                action="PORTAL_BOOKING_REQUESTED", entity_id=str(booking.pk)
            ).exists()
        )

    def test_booking_form_rejects_negative_budget(self):
        self.client.force_login(self.family)
        response = self.client.post(
            reverse("portal:booking_new"),
            {
                "service": self.service.pk,
                "location": "Kololo",
                "requirements": "Cleaning.",
                "budget_ugx": "-5",
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "Enter a positive amount")
        self.assertFalse(Booking.objects.exists())

    def test_inactive_service_is_not_offered(self):
        self.service.active = False
        self.service.save(update_fields=["active"])
        self.client.force_login(self.family)
        response = self.client.get(reverse("portal:booking_new"))
        self.assertEqual(response.status_code, 200)
        self.assertNotContains(response, self.service.name)


class PortalReplacementTests(ApiTestCase):
    def test_family_can_raise_replacement_case(self):
        placement = self.make_placement()
        self.client.force_login(self.family)
        response = self.client.post(
            reverse("portal:replacement_new"),
            {
                "placement": placement.pk,
                "problem_category": "CONDUCT",
                "issue_reported_date": timezone.localdate().isoformat(),
                "description": "Worker did not arrive for three days.",
            },
        )
        self.assertEqual(response.status_code, 302)
        case = ReplacementCase.objects.get(placement=placement)
        self.assertEqual(case.client, self.client_record)
        self.assertEqual(case.original_worker, self.worker)
        self.assertEqual(case.status, "OPEN")
        self.assertEqual(case.eligibility_decision, "PENDING")
        self.assertTrue(
            AuditLog.objects.filter(
                action="PORTAL_REPLACEMENT_REQUESTED", entity_id=str(case.pk)
            ).exists()
        )

    def test_duplicate_open_case_is_blocked(self):
        placement = self.make_placement()
        ReplacementCase.objects.create(
            placement=placement,
            client=self.client_record,
            original_worker=self.worker,
            problem_category="ATTENDANCE",
            description="Already reported.",
            status="REVIEWING",
        )
        self.client.force_login(self.family)
        response = self.client.post(
            reverse("portal:replacement_new"),
            {
                "placement": placement.pk,
                "problem_category": "CONDUCT",
                "issue_reported_date": timezone.localdate().isoformat(),
                "description": "Second report.",
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "already an open replacement case")
        self.assertEqual(ReplacementCase.objects.count(), 1)

    def test_closed_placement_is_not_offered(self):
        placement = self.make_placement()
        placement.status = "COMPLETED"
        placement.save(update_fields=["status"])
        self.client.force_login(self.family)
        response = self.client.get(reverse("portal:replacement_new"))
        self.assertEqual(response.status_code, 200)
        self.assertNotContains(response, placement.placement_number)
