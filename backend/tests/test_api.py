from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import tempfile
import unittest

from fastapi.testclient import TestClient

from app.main import create_app


class APITest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.path = Path(self.directory.name) / "test.sqlite3"
        self.client = TestClient(create_app(self.path))
        self.client.__enter__()
        self.a = self.account("小林")
        self.b = self.account("小周")
        self.c = self.account("第三个人")

    def tearDown(self):
        self.client.__exit__(None, None, None)
        self.directory.cleanup()

    def account(self, name):
        response = self.client.post("/v1/accounts", json={"name": name})
        self.assertEqual(response.status_code, 201, response.text)
        headers = {"Authorization": "Bearer " + response.json()["token"]}
        return headers, self.client.get("/v1/me", headers=headers).json()

    def pair(self):
        result = self.client.post("/v1/pair", headers=self.a[0], json={"invite_code": self.b[1]["invite_code"]})
        self.assertEqual(result.status_code, 200, result.text)

    def send(self, text="记得喝水", client_id="request-1"):
        return self.client.post("/v1/notes", headers=self.a[0], json={"text": text, "client_id": client_id})

    def test_auth_and_validation(self):
        self.assertEqual(self.client.get("/v1/me").status_code, 401)
        self.assertEqual(self.client.get("/v1/me", headers={"Authorization": "Bearer bogus"}).status_code, 401)
        self.assertEqual(self.client.post("/v1/accounts", json={"name": "  "}).status_code, 422)
        self.assertEqual(self.send().status_code, 409)
        self.assertNotIn("token_hash", self.a[1])

    def test_pair_is_mutual_and_exclusive(self):
        self.pair()
        self.assertEqual(self.client.get("/v1/me", headers=self.b[0]).json()["peer_name"], "小林")
        again = self.client.post("/v1/pair", headers=self.a[0], json={"invite_code": self.b[1]["invite_code"]})
        self.assertEqual(again.status_code, 200)
        result = self.client.post("/v1/pair", headers=self.c[0], json={"invite_code": self.b[1]["invite_code"]})
        self.assertEqual(result.status_code, 409)

    def test_inbox_and_ack_authorization(self):
        self.pair()
        note = self.send().json()["id"]
        self.assertEqual(self.client.get("/v1/notes/inbox", headers=self.c[0]).json(), [])
        self.client.post("/v1/notes/ack", headers=self.c[0], json={"ids": [note]})
        inbox = self.client.get("/v1/notes/inbox", headers=self.b[0]).json()
        self.assertEqual(len(inbox), 1)
        self.assertEqual(inbox[0]["sender_name"], "小林")
        for _ in range(2):
            self.assertEqual(self.client.post("/v1/notes/ack", headers=self.b[0], json={"ids": [note]}).status_code, 204)
        self.assertEqual(self.client.get("/v1/notes/inbox", headers=self.b[0]).json(), [])

    def test_send_retry_is_idempotent(self):
        self.pair()
        first = self.send()
        second = self.send()
        self.assertEqual(first.json(), second.json())
        self.assertEqual(self.send(text="不同内容").status_code, 409)
        self.assertEqual(len(self.client.get("/v1/notes/inbox", headers=self.b[0]).json()), 1)

    def test_unpair_removes_pending_and_can_rebind(self):
        self.pair()
        self.send()
        self.assertEqual(self.client.delete("/v1/pair", headers=self.b[0]).status_code, 204)
        self.assertIsNone(self.client.get("/v1/me", headers=self.a[0]).json()["peer_name"])
        self.assertEqual(self.client.get("/v1/notes/inbox", headers=self.b[0]).json(), [])
        self.assertEqual(self.send(client_id="another").status_code, 409)
        self.pair()

    def test_binding_race_has_one_winner(self):
        def bind(account):
            return self.client.post("/v1/pair", headers=account[0],
                                    json={"invite_code": self.b[1]["invite_code"]}).status_code
        with ThreadPoolExecutor(max_workers=2) as pool:
            self.assertEqual(sorted(pool.map(bind, [self.a, self.c])), [200, 409])

    def test_rate_limit_on_guessing(self):
        results = [self.client.post("/v1/pair", headers=self.a[0], json={"invite_code": "FFFFFFFFFFFF"}).status_code for _ in range(11)]
        self.assertEqual(results[-1], 429)

    def test_persists_across_restart(self):
        self.pair()
        note = self.send().json()["id"]
        with TestClient(create_app(self.path)) as restarted:
            self.assertEqual(restarted.get("/v1/notes/inbox", headers=self.b[0]).json()[0]["id"], note)

    def test_note_limits_and_whitespace(self):
        self.pair()
        self.assertEqual(self.send(text=" " * 3).status_code, 422)
        self.assertEqual(self.send(text="水" * 141).status_code, 422)


if __name__ == "__main__":
    unittest.main()
