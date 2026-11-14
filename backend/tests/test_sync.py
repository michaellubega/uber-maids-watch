import uuid
from datetime import timedelta

from clients.models import Client
from operations.models import Booking
from tests.base import ApiTestCase
from workers.models import Worker


class SyncPullTests(ApiTestCase):
    def test_staff_pull_returns_changes_in_sequence_order(self):
        response = self.auth(self.ops).get("/api/sync/pull/?since=0")
        self.assertEqual(response.status_code, 200)
        self.assertGreater(len(response.data["changes"]), 0)
        sequences = [row["change_seq"] for row in response.data["changes"]]
        self.assertEqual(sequences, sorted(sequences))
        entities = {row["entity"] for row in response.data["changes"]}
        self.assertIn("worker", entities)
        self.assertIn("client", entities)

    def test_pull_is_scoped_for_family(self):
        other = Client.objects.create(full_name="Other", phone="0770", area="Muyenga")
        response = self.auth(self.family).get("/api/sync/pull/?since=0")
        client_ids = [
            row["id"] for row in response.data["changes"] if row["entity"] == "client"
        ]
        self.assertEqual(client_ids, [str(self.client_record.pk)])
        self.assertNotIn(str(other.pk), client_ids)
        # Workers are only visible through the family's own placements.
        worker_rows = [row for row in response.data["changes"] if row["entity"] == "worker"]
        self.assertEqual(worker_rows, [])

    def test_maid_pull_does_not_leak_client_records(self):
        response = self.auth(self.maid).get("/api/sync/pull/?since=0")
        entities = {row["entity"] for row in response.data["changes"]}
        self.assertNotIn("client", entities)
        worker_rows = [row for row in response.data["changes"] if row["entity"] == "worker"]
        self.assertEqual([row["id"] for row in worker_rows], [str(self.worker.pk)])


class SyncPushTests(ApiTestCase):
    def mutation(self, *, mutation_id=None, entity="worker", record_id=None, **overrides):
        payload = {
            "mutation_id": str(mutation_id or uuid.uuid4()),
            "entity": entity,
            "id": str(record_id or uuid.uuid4()),
            "operation": "upsert",
            "base_version": 0,
            "data": {},
        }
        payload.update(overrides)
        return payload

    def push(self, user, *mutations):
        return self.auth(user).post(
            "/api/sync/push/", {"mutations": list(mutations)}, format="json"
        )

    def test_create_worker_from_device(self):
        record_id = uuid.uuid4()
        response = self.push(
            self.ops,
            self.mutation(
                record_id=record_id,
                data={
                    "full_name": "Offline Worker",
                    "phone": "0770000099",
                    "area": "Kira",
                    "skills": ["Cleaning"],
                },
            ),
        )
        self.assertEqual(response.status_code, 200)
        result = response.data["results"][0]
        self.assertEqual(result["status"], "applied", result)
        worker = Worker.objects.get(pk=record_id)
        self.assertEqual(worker.full_name, "Offline Worker")
        self.assertTrue(worker.worker_number)

    def test_mutation_is_idempotent(self):
        mutation_id = uuid.uuid4()
        mutation = self.mutation(
            mutation_id=mutation_id,
            data={"full_name": "Once Only", "phone": "0770", "area": "Kira"},
        )
        first = self.push(self.ops, mutation)
        second = self.push(self.ops, mutation)
        self.assertEqual(first.data["results"][0]["status"], "applied")
        self.assertEqual(second.data["results"][0]["status"], "duplicate")
        self.assertEqual(Worker.objects.filter(full_name="Once Only").count(), 1)

    def test_stale_base_version_returns_conflict(self):
        response = self.push(
            self.ops,
            self.mutation(
                entity="worker",
                record_id=self.worker.pk,
                base_version=999,
                data={"full_name": "Stale Edit"},
            ),
        )
        result = response.data["results"][0]
        self.assertEqual(result["status"], "conflict")
        self.assertIn("record", result)
        self.worker.refresh_from_db()
        self.assertEqual(self.worker.full_name, "Test Worker")

    def test_family_cannot_push_worker_changes(self):
        response = self.push(
            self.family,
            self.mutation(
                data={"full_name": "Not Allowed", "phone": "0770", "area": "Kira"}
            ),
        )
        self.assertEqual(response.data["results"][0]["status"], "rejected")

    def test_family_booking_create_is_forced_to_own_client(self):
        response = self.push(
            self.family,
            self.mutation(
                entity="booking",
                data={
                    "service": str(self.service.pk),
                    "location": "Kololo",
                    "requirements": "Offline request",
                    "client": str(self.client_record.pk),
                },
            ),
        )
        result = response.data["results"][0]
        self.assertEqual(result["status"], "applied", result)
        booking = Booking.objects.get(pk=result["record"]["id"])
        self.assertEqual(booking.client_id, self.client_record.pk)
        self.assertEqual(booking.status, "NEW")

    def test_family_cannot_edit_existing_booking_via_sync(self):
        booking = Booking.objects.create(
            client=self.client_record, service=self.service, status="NEW"
        )
        response = self.push(
            self.family,
            self.mutation(
                entity="booking",
                record_id=booking.pk,
                base_version=booking.server_version,
                data={"status": "CONFIRMED"},
            ),
        )
        self.assertEqual(response.data["results"][0]["status"], "rejected")

    def test_delete_is_a_tombstone_and_visible_to_pull(self):
        record_id = self.worker.pk
        response = self.push(
            self.admin,
            {
                "mutation_id": str(uuid.uuid4()),
                "entity": "worker",
                "id": str(record_id),
                "operation": "delete",
                "base_version": self.worker.server_version,
            },
        )
        self.assertEqual(response.data["results"][0]["status"], "applied")
        self.worker.refresh_from_db()
        self.assertIsNotNone(self.worker.deleted_at)
        pull = self.auth(self.admin).get("/api/sync/pull/?since=0&limit=1000")
        row = next(
            change
            for change in pull.data["changes"]
            if change["entity"] == "worker" and change["id"] == str(record_id)
        )
        self.assertTrue(row["deleted"])
