from clients.models import Client
from core.models import Role
from tests.base import ApiTestCase
from workers.models import Worker


class WorkerApiTests(ApiTestCase):
    def test_create_worker_generates_reference_and_history(self):
        response = self.auth(self.ops).post(
            "/api/workers/",
            {
                "full_name": "New Worker",
                "phone": "0771234567",
                "area": "Kireka",
                "skills": ["Cleaning"],
                "languages": ["Luganda"],
                "service_categories": ["Cleaner"],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(response.data["worker_number"].startswith("W-"))
        worker = Worker.objects.get(pk=response.data["id"])
        self.assertEqual(worker.status_history.count(), 1)

    def test_worker_cannot_be_marked_verified_without_verification(self):
        worker = Worker.objects.create(
            full_name="Unverified", phone="0770", area="Kampala", status="APPLICANT"
        )
        response = self.auth(self.ops).patch(
            f"/api/workers/{worker.pk}/", {"status": "VERIFIED"}, format="json"
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("status", response.data)

    def test_verify_action_sets_status_and_audit(self):
        response = self.auth(self.verifier).post(
            f"/api/workers/{self.worker.pk}/verify/",
            {"checks_complete": True},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.worker.refresh_from_db()
        self.assertEqual(self.worker.verification_status, "VERIFIED")
        self.assertEqual(self.worker.verified_by_name, "verify-test")

    def test_sensitive_fields_hidden_from_customer_care(self):
        self.worker.national_id_number = "CM900001"
        self.worker.notes = "Private note"
        self.worker.save()
        response = self.auth(self.care).get(f"/api/workers/{self.worker.pk}/")
        self.assertEqual(response.status_code, 200)
        self.assertNotIn("national_id_number", response.data)
        self.assertNotIn("notes", response.data)

    def test_maid_sees_only_own_worker_profile(self):
        other = Worker.objects.create(
            full_name="Other Worker", phone="0770", area="Kampala", status="AVAILABLE"
        )
        response = self.auth(self.maid).get("/api/workers/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["count"], 1)
        self.assertEqual(response.data["results"][0]["id"], str(self.worker.pk))
        self.assertNotEqual(response.data["results"][0]["id"], str(other.pk))
