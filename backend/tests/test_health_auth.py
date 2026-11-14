from django.urls import reverse

from tests.base import ApiTestCase


class HealthAndAuthTests(ApiTestCase):
    def test_health_is_public_and_reports_database(self):
        response = self.client.get(reverse("health"))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["database"], "ok")
        self.assertEqual(response.data["status"], "ok")

    def test_protected_endpoint_requires_authentication(self):
        response = self.client.get("/api/workers/")
        self.assertEqual(response.status_code, 401)

    def test_login_returns_jwt_and_me_returns_role(self):
        response = self.client.post(
            "/api/auth/token/",
            {"username": "ops-test", "password": "Pass1234!"},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn("access", response.data)
        access = response.data["access"]

        me = self.client.get("/api/auth/me/", HTTP_AUTHORIZATION=f"Bearer {access}")
        self.assertEqual(me.status_code, 200)
        self.assertEqual(me.data["user"]["role"], "OPERATIONS")
        self.assertTrue(me.data["capabilities"]["can_write"]["workers"])

    def test_readonly_role_cannot_create_a_worker(self):
        response = self.auth(self.readonly).post(
            "/api/workers/",
            {"full_name": "Blocked", "phone": "0700", "area": "Kampala"},
            format="json",
        )
        self.assertEqual(response.status_code, 403)

    def test_maid_cannot_list_all_clients(self):
        response = self.auth(self.maid).get("/api/clients/")
        self.assertEqual(response.status_code, 403)
