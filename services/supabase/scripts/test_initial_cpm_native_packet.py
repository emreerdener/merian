"""Offline refusal/byte-identity tests for the bounded synthetic native handoff."""
import base64
import hashlib
import json
import unittest

from initial_cpm_native_packet import MAX_PACKET, MAX_ROLE, bind_fixture_identity, bind_fixture_prefix, validate_packet


class NativePacketTests(unittest.TestCase):
    nonce = "synthetic-native-handoff-only"
    execution = {"source_sha256": "a" * 64, "app_sha256": "b" * 64, "tests_sha256": "c" * 64}

    def fixture(self):
        roles, photos = [], []
        for ordinal in range(2):
            photo = {"ordinal": ordinal}
            for name in ("source", "ai", "display"):
                data = (str(ordinal) + name).encode()
                photo[name] = {"byte_count": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                               "declared_content_type": "image/png" if name == "source" else "image/jpeg"}
                roles.append({"ordinal": ordinal, "role": name, "bytes_base64": base64.b64encode(data).decode()})
            photos.append(photo)
        content = {"scan_id": "00000000-0000-4000-8000-00000000f101", "photos": photos,
                   "contexts": [{"text_utf8_base64": base64.b64encode(" Literal  €\n$$ ' ".encode()).decode()}]}
        candidate = {"version": 1, "variant": "client_prepared_photo", "content_canonical": json.dumps(content), "admission": {}}
        canonical = json.dumps(candidate, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        return {"version": 1, "nonce": self.nonce, "owner_id": "00000000-0000-4000-8000-00000000f001",
                "execution": dict(self.execution), "candidate_canonical": canonical, "candidate_sha256": hashlib.sha256(canonical.encode()).hexdigest(), "roles": roles}

    def read(self, value):
        return validate_packet(json.dumps(value).encode(), self.nonce, self.execution)

    def test_literal_candidate_and_ordered_bytes_are_preserved(self):
        value = self.fixture()
        result = self.read(value)
        self.assertEqual(result["canonical"].encode(), value["candidate_canonical"].encode())
        self.assertEqual(result["roster"], [base64.b64decode(role["bytes_base64"]) for role in value["roles"]])
        self.assertEqual(result["content_types"], ["image/png", "image/jpeg", "image/jpeg"] * 2)

    def test_private_extra_fields_are_refused(self):
        for key in ("assignment_canonical", "backend", "credential", "funding", "unexpected"):
            with self.subTest(key=key):
                value = self.fixture(); value[key] = "not allowed"
                with self.assertRaises(ValueError): self.read(value)

    def test_stale_nonce_or_changed_candidate_is_refused(self):
        for key, changed in (("nonce", "stale"), ("candidate_sha256", "0" * 64), ("version", True), ("owner_id", "not-a-uuid")):
            with self.subTest(key=key):
                value = self.fixture(); value[key] = changed
                with self.assertRaises(ValueError): self.read(value)
        value = self.fixture(); value["candidate_canonical"] += " "
        with self.assertRaises(ValueError): self.read(value)

    def test_roster_reordering_truncation_and_role_substitution_are_refused(self):
        for change in (lambda roles: roles.reverse(), lambda roles: roles.pop(),
                       lambda roles: roles[0].update(role="ai"), lambda roles: roles[0].update(ordinal=True)):
            value = self.fixture(); change(value["roles"])
            with self.assertRaises(ValueError): self.read(value)

    def test_equal_length_changed_bytes_are_refused(self):
        value = self.fixture(); value["roles"][0]["bytes_base64"] = base64.b64encode(b"changed").decode()
        with self.assertRaises(ValueError): self.read(value)

    def test_declared_length_digest_and_type_must_match(self):
        for key, changed in (("byte_count", 999), ("sha256", "0" * 64), ("declared_content_type", "text/plain")):
            value = self.fixture(); candidate = json.loads(value["candidate_canonical"]); content = json.loads(candidate["content_canonical"])
            content["photos"][0]["source"][key] = changed
            candidate["content_canonical"] = json.dumps(content)
            value["candidate_canonical"] = json.dumps(candidate)
            value["candidate_sha256"] = hashlib.sha256(value["candidate_canonical"].encode()).hexdigest()
            with self.assertRaises(ValueError): self.read(value)

    def test_bounds_and_invalid_encoding_are_refused(self):
        for raw in (b"", b" " * (MAX_PACKET + 1), b"\xff", b'{"version":NaN}'):
            with self.assertRaises((ValueError, UnicodeError)): validate_packet(raw, self.nonce, self.execution)
        for encoded in ("!", "YQ===", base64.b64encode(b"a" * (MAX_ROLE + 1)).decode()):
            value = self.fixture(); value["roles"][0]["bytes_base64"] = encoded
            with self.assertRaises(ValueError): self.read(value)

    def test_conflicting_execution_and_unknown_execution_keys_are_refused(self):
        for value in [{**self.execution, "tests_sha256": "d" * 64}, {**self.execution, "extra": "value"}, {}]:
            packet = self.fixture(); packet["execution"] = value
            with self.assertRaises(ValueError): self.read(packet)

    def test_duplicate_fields_are_refused(self):
        value = json.dumps(self.fixture()).encode()
        with self.assertRaises(ValueError): validate_packet(value[:-1] + b',"version":1}', self.nonce, self.execution)

    def test_fixture_prefix_keeps_literal_candidate_and_requires_unique_owner(self):
        packet = self.read(self.fixture())
        prefix = "CREATE FUNCTION pg_temp.cpm_candidate(scan UUID) RETURNS TEXT LANGUAGE SQL AS $$ SELECT 'old'; $$;"
        result = bind_fixture_prefix(prefix, packet)
        self.assertIn(packet["canonical"].replace("'", "''"), result)
        self.assertIn("$native_" + packet["sha256"] + "$", result)
        for invalid in ("", prefix + prefix):
            with self.assertRaises(ValueError): bind_fixture_prefix(invalid, packet)

    def test_existing_positive_closure_uses_the_same_native_identity(self):
        from pathlib import Path
        source = (Path(__file__).parents[1] / "tests/initial_cpm_photo_intents.sql").read_text()
        writes = source[source.index("DO $$ DECLARE s internal.initial_analysis_preparation_intents; m RECORD;"):source.index("SAVEPOINT verification_revoked;")]
        self.assertIn("WHERE scan_id='00000000-0000-4000-8000-00000000f101'", writes)
        packet = self.read(self.fixture())
        packet["scan"] = "00000000-0000-4000-8000-000000009999"
        canonical = packet["canonical"]
        bound = bind_fixture_identity(writes, packet)
        self.assertIn("WHERE scan_id='" + packet["scan"] + "'", bound)
        self.assertNotIn("00000000-0000-4000-8000-00000000f101", bound)
        self.assertEqual(packet["canonical"], canonical)


if __name__ == "__main__": unittest.main()
