"""Tests for the family and worker web portal."""

import tempfile
from pathlib import Path

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone

from clients.models import Client
from core.models import AuditLog, Role, User
from operations.models import Booking, Placement, ReplacementCase
from tests.base import ApiTestCase
from workers.models import Worker, WorkerDocument

TEST_MEDIA_ROOT = Path(tempfile.mkdtemp(prefix="umw-portal-test-media-"))


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


class AndroidDownloadTests(ApiTestCase):
    def test_android_apk_is_served_as_an_attachment(self):
        response = self.client.get(reverse("portal:download_app"))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response["Content-Type"], "application/vnd.android.package-archive"
        )
        self.assertIn("attachment", response["Content-Disposition"])
        self.assertIn("uber-maids-watch.apk", response["Content-Disposition"])

    def test_landing_page_links_to_the_android_app(self):
        response = self.client.get(reverse("portal:landing"))
        self.assertContains(response, reverse("portal:download_app"))


class PortalRegistrationTests(ApiTestCase):
    def family_payload(self, **overrides):
        payload = {
            "role": "FAMILY",
            "first_name": "Nakato",
            "last_name": "Sarah",
            "username": "sarah-family",
            "email": "sarah@example.com",
            "phone_number": "0772000111",
            "area": "Muyenga",
            "preferred_contact": "WHATSAPP",
            "password1": "StrongPass123!",
            "password2": "StrongPass123!",
        }
        payload.update(overrides)
        return payload

    def maid_payload(self, **overrides):
        payload = {
            "role": "MAID",
            "first_name": "Amina",
            "last_name": "Nabirye",
            "username": "amina-worker",
            "email": "",
            "phone_number": "0772000222",
            "area": "Kireka",
            "password1": "StrongPass123!",
            "password2": "StrongPass123!",
        }
        payload.update(overrides)
        return payload

    def test_family_can_create_an_account_and_is_signed_in(self):
        response = self.client.post(
            reverse("portal:register"), self.family_payload()
        )
        self.assertEqual(response.status_code, 302)
        self.assertEqual(response["Location"], reverse("portal:dashboard"))

        user = User.objects.get(username="sarah-family")
        self.assertEqual(user.role, Role.FAMILY)
        self.assertEqual(user.phone_number, "0772000111")
        profile = Client.objects.get(user=user)
        self.assertEqual(profile.full_name, "Nakato Sarah")
        self.assertEqual(profile.area, "Muyenga")
        self.assertEqual(profile.preferred_contact, "WHATSAPP")
        self.assertTrue(profile.client_number)
        self.assertIn("_auth_user_id", self.client.session)
        self.assertTrue(
            AuditLog.objects.filter(
                action="PORTAL_REGISTERED",
                entity_id=str(user.pk),
                metadata__role=Role.FAMILY,
            ).exists()
        )

    def test_maid_account_starts_unverified(self):
        response = self.client.post(reverse("portal:register"), self.maid_payload())
        self.assertEqual(response.status_code, 302)

        user = User.objects.get(username="amina-worker")
        self.assertEqual(user.role, Role.MAID)
        profile = Worker.objects.get(user=user)
        self.assertEqual(profile.full_name, "Amina Nabirye")
        self.assertEqual(profile.status, "APPLICANT")
        self.assertEqual(profile.verification_status, "PENDING")
        self.assertIsNone(profile.verified_at)
        self.assertEqual(profile.verified_by_name, "")

    def test_duplicate_username_is_rejected(self):
        response = self.client.post(
            reverse("portal:register"),
            self.family_payload(username="family-test"),
        )
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "already taken")
        self.assertEqual(User.objects.filter(username="family-test").count(), 1)

    def test_password_mismatch_is_rejected(self):
        response = self.client.post(
            reverse("portal:register"),
            self.family_payload(password2="DifferentPass123!"),
        )
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "do not match")
        self.assertFalse(User.objects.filter(username="sarah-family").exists())

    def test_only_family_and_maid_can_register(self):
        response = self.client.post(
            reverse("portal:register"), self.family_payload(role="ADMIN")
        )
        self.assertEqual(response.status_code, 200)
        self.assertFalse(User.objects.filter(username="sarah-family").exists())

    def test_signed_in_portal_user_is_redirected_from_register(self):
        self.client.force_login(self.family)
        response = self.client.get(reverse("portal:register"))
        self.assertEqual(response.status_code, 302)
        self.assertEqual(response["Location"], reverse("portal:dashboard"))


@override_settings(PRIVATE_MEDIA_ROOT=TEST_MEDIA_ROOT)
class PortalDocumentTests(ApiTestCase):
    def upload(self, **overrides):
        payload = {
            "document_type": "NATIONAL_ID",
            "title": "National ID - front",
            "file": SimpleUploadedFile(
                "national-id.pdf", b"%PDF-1.4 test identity document"
            ),
        }
        payload.update(overrides)
        return self.client.post(reverse("portal:documents"), payload)

    def test_maid_can_upload_a_document(self):
        self.client.force_login(self.maid)
        response = self.upload()
        self.assertEqual(response.status_code, 302)
        self.assertEqual(response["Location"], reverse("portal:documents"))

        document = WorkerDocument.objects.get(worker=self.worker)
        self.assertEqual(document.title, "National ID - front")
        self.assertEqual(document.document_type, "NATIONAL_ID")
        self.assertEqual(document.uploaded_by_name, self.maid.display_name)
        self.assertFalse(document.verified)
        self.assertTrue(document.file.name)
        self.assertTrue(
            AuditLog.objects.filter(
                action="DOCUMENT_UPLOADED",
                entity_id=str(document.pk),
                metadata__source="portal",
            ).exists()
        )

    def test_upload_rejects_unsupported_file_types(self):
        self.client.force_login(self.maid)
        response = self.upload(
            file=SimpleUploadedFile("notes.exe", b"not a document")
        )
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "Allowed file types")
        self.assertFalse(WorkerDocument.objects.exists())

    def test_maid_document_list_is_private(self):
        other_worker = Worker.objects.create(
            full_name="Other Worker", phone="0770000010", area="Kireka"
        )
        WorkerDocument.objects.create(
            worker=other_worker,
            document_type="OTHER",
            title="Other worker file",
            file=SimpleUploadedFile("other.pdf", b"%PDF-1.4 other"),
        )
        self.client.force_login(self.maid)
        response = self.client.get(reverse("portal:documents"))
        self.assertEqual(response.status_code, 200)
        self.assertNotContains(response, "Other worker file")

    def test_maid_cannot_download_another_workers_document(self):
        other_worker = Worker.objects.create(
            full_name="Other Worker", phone="0770000010", area="Kireka"
        )
        document = WorkerDocument.objects.create(
            worker=other_worker,
            document_type="OTHER",
            title="Other worker file",
            file=SimpleUploadedFile("other.pdf", b"%PDF-1.4 other"),
        )
        self.client.force_login(self.maid)
        response = self.client.get(
            reverse("portal:document_download", args=[document.pk])
        )
        self.assertEqual(response.status_code, 404)

    def test_maid_can_download_own_document_and_access_is_audited(self):
        self.client.force_login(self.maid)
        self.upload()
        document = WorkerDocument.objects.get(worker=self.worker)
        response = self.client.get(
            reverse("portal:document_download", args=[document.pk])
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn("attachment", response["Content-Disposition"])
        self.assertTrue(
            AuditLog.objects.filter(
                action="DOCUMENT_DOWNLOADED",
                entity_id=str(document.pk),
                metadata__source="portal",
            ).exists()
        )

    def test_family_account_cannot_open_document_pages(self):
        self.client.force_login(self.family)
        for name in ("documents",):
            response = self.client.get(reverse(f"portal:{name}"))
            self.assertEqual(response.status_code, 403, name)
