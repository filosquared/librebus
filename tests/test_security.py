import unittest

from lib.security import AuthSessionManager, hash_password, needs_rehash, verify_password


class PasswordTests(unittest.TestCase):
	def test_password_hash_is_not_plaintext_and_round_trips(self):
		stored = hash_password("correct horse battery staple")
		self.assertNotEqual(stored, "correct horse battery staple")
		self.assertTrue(verify_password("correct horse battery staple", stored))
		self.assertFalse(verify_password("wrong", stored))
		self.assertFalse(needs_rehash(stored))

	def test_legacy_sha256_hash_can_be_verified_for_migration(self):
		import hashlib

		legacy = hashlib.sha256(b"admin").hexdigest()
		self.assertTrue(verify_password("admin", legacy))
		self.assertTrue(needs_rehash(legacy))


class SessionTests(unittest.TestCase):
	def test_session_token_is_opaque_and_revocable(self):
		manager = AuthSessionManager(ttl_seconds=60)
		token = manager.create("alice")
		self.assertGreaterEqual(len(token), 32)
		self.assertEqual(manager.get_subject(token), "alice")
		self.assertIsNone(manager.get_subject("alice"))
		manager.revoke(token)
		self.assertIsNone(manager.get_subject(token))
