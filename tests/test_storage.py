import tempfile
import unittest
from pathlib import Path

from lib.storage import SQLiteStore


class StorageTests(unittest.TestCase):
	def test_round_trip_uses_sqlite(self):
		defaults = {"name": "admin", "passwd": None, "nested": {"enabled": True}}
		with tempfile.TemporaryDirectory() as directory:
			store = SQLiteStore(directory)
			config, users = store.load(defaults)
			self.assertEqual(config["name"], "admin")
			self.assertEqual(users, {})

			config["name"] = "owner"
			users["alice"] = {"first_name": "Alice"}
			store.save_config(config)
			store.save_users(users)

			loaded_config, loaded_users = SQLiteStore(directory).load(defaults)
			self.assertEqual(loaded_config["name"], "owner")
			self.assertEqual(loaded_users["alice"]["first_name"], "Alice")
			self.assertTrue(Path(directory, "librebus.sqlite3").exists())

	def test_legacy_json_is_migrated(self):
		defaults = {"name": "admin", "passwd": None}
		with tempfile.TemporaryDirectory() as directory:
			Path(directory, "config.json").write_text('{"name": "legacy"}', encoding="utf-8")
			Path(directory, "database.json").write_text(
				'{"alice": {"first_name": "Alice"}}', encoding="utf-8"
			)
			config, users = SQLiteStore(directory).load(defaults)
			self.assertEqual(config["name"], "legacy")
			self.assertIn("alice", users)

	def test_empty_database_does_not_restore_legacy_backup(self):
		defaults = {"name": "admin", "passwd": None}
		with tempfile.TemporaryDirectory() as directory:
			Path(directory, "database.json").write_text(
				'{"alice": {"first_name": "Alice"}}', encoding="utf-8"
			)
			store = SQLiteStore(directory)
			store.load(defaults)
			store.save_users({})
			self.assertEqual(SQLiteStore(directory).load(defaults)[1], {})
