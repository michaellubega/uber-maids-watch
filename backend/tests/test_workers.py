import tempfile
from pathlib import Path

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings

from core.models import AuditLog, Role
from tests.base import ApiTestCase
from workers.models import Worker, WorkerDocument

TEST_MEDIA_ROOT = Path(tempfile.mkdtemp(prefix="umw-api-test-media-"))


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


@override_settings(PRIVATE_MEDIA_ROOT=TEST_MEDIA_ROOT)
class WorkerDocumentApiTests(ApiTestCase):
    def payload(self, worker=None, **overrides):
        data = {
            "worker": str((worker or self.worker).pk),
            "document_type": "NATIONAL_ID",
            "title": "National ID - front",
            "file": SimpleUploadedFile(
                "national-id.pdf", b"%PDF-1.4 test identity document"
            ),
        }
        data.update(overrides)
        return data

    def test_maid_can_upload_own_document_from_the_mobile_app(self):
        response = self.auth(self.maid).post(
            "/api/worker-documents/", self.payload(), format="multipart"
        )
        self.assertEqual(response.status_code, 201, response.data)
        document = WorkerDocument.objects.get(pk=response.data["id"])
        self.assertEqual(document.worker, self.worker)
        self.assertEqual(document.uploaded_by_name, "maid-test")
        self.assertFalse(document.verified)
        self.assertTrue(
            AuditLog.objects.filter(
                action="DOCUMENT_UPLOADED",
                entity_id=str(document.pk),
                metadata__source="mobile",
            ).exists()
        )

    def test_maid_cannot_upload_for_another_worker(self):
        other = Worker.objects.create(
            full_name="Other Worker", phone="0770", area="Kampala"
        )
        response = self.auth(self.maid).post(
            "/api/worker-documents/",
            self.payload(worker=other),
            format="multipart",
        )
        self.assertEqual(response.status_code, 403)
        self.assertFalse(WorkerDocument.objects.exists())

    def test_maid_cannot_verify_or_edit_a_document(self):
        document = WorkerDocument.objects.create(
            worker=self.worker,
            document_type="OTHER",
            title="Letter",
            file=SimpleUploadedFile("letter.pdf", b"%PDF-1.4 letter"),
        )
        response = self.auth(self.maid).patch(
            f"/api/worker-documents/{document.pk}/",
            {"verified": True},
            format="json",
        )
        self.assertEqual(response.status_code, 403)
        document.refresh_from_db()
        self.assertFalse(document.verified)

    def test_maid_only_sees_own_documents(self):
        other = Worker.objects.create(
            full_name="Other Worker", phone="0770", area="Kampala"
        )
        WorkerDocument.objects.create(
            worker=other,
            document_type="OTHER",
            title="Other file",
            file=SimpleUploadedFile("other.pdf", b"%PDF-1.4 other"),
        )
        WorkerDocument.objects.create(
            worker=self.worker,
            document_type="OTHER",
            title="Own file",
            file=SimpleUploadedFile("own.pdf", b"%PDF-1.4 own"),
        )
        response = self.auth(self.maid).get("/api/worker-documents/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["count"], 1)
        self.assertEqual(response.data["results"][0]["title"], "Own file")

    def test_customer_care_cannot_upload_documents(self):
        response = self.auth(self.care).post(
            "/api/worker-documents/", self.payload(), format="multipart"
        )
        self.assertEqual(response.status_code, 403)

    def test_api_rejects_unsupported_document_types(self):
        response = self.auth(self.ops).post(
            "/api/worker-documents/",
            self.payload(
                file=SimpleUploadedFile("notes.exe", b"not a document")
            ),
            format="multipart",
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("file", response.data)
