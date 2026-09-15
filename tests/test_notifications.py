import unittest

from lib.api.sessionmanager import SessionManager


class NotificationCacheTests(unittest.TestCase):
	def test_first_snapshot_is_a_baseline(self):
		manager = SessionManager({"alice": {}})
		current = {"grades": 3, "exams": 2}

		self.assertEqual(manager.get_notifications("alice", current), {"grades": 0, "exams": 0})
		self.assertEqual(current, {"grades": 3, "exams": 2})

	def test_returns_positive_deltas_without_negative_notifications(self):
		manager = SessionManager({"alice": {}})
		manager.get_notifications("alice", {"grades": 3, "exams": 2})

		self.assertEqual(
			manager.get_notifications("alice", {"grades": 5, "exams": 1}),
			{"grades": 2, "exams": 0},
		)

	def test_users_have_isolated_baselines_and_removed_users_are_safe(self):
		manager = SessionManager({"alice": {}, "bob": {}})
		manager.get_notifications("alice", {"grades": 1})
		manager.get_notifications("bob", {"grades": 4})

		self.assertEqual(manager.get_notifications("alice", {"grades": 2}), {"grades": 1})
		self.assertEqual(manager.get_notifications("bob", {"grades": 4}), {"grades": 0})
		manager.updatedb({"bob": {}})
		self.assertEqual(manager.get_notifications("alice", {"grades": 3}), {})

	def test_invalid_snapshot_does_not_replace_baseline(self):
		manager = SessionManager({"alice": {}})
		manager.get_notifications("alice", {"grades": 1})

		self.assertEqual(manager.get_notifications("alice", None), {})
		self.assertEqual(manager.get_notifications("alice", {"grades": 2}), {"grades": 1})
