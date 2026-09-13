"""SQLite persistence with a one-time migration from the legacy JSON files."""

from __future__ import annotations

import copy
import json
import os
import sqlite3
from pathlib import Path
from typing import Any


class SQLiteStore:
	def __init__(self, data_dir: str | os.PathLike[str]):
		self.data_dir = Path(data_dir)
		self.path = self.data_dir / "librebus.sqlite3"

	def _connect(self) -> sqlite3.Connection:
		connection = sqlite3.connect(self.path, timeout=10)
		connection.row_factory = sqlite3.Row
		connection.execute("PRAGMA foreign_keys = ON")
		return connection

	def initialize(self) -> None:
		self.data_dir.mkdir(parents=True, exist_ok=True)
		with self._connect() as connection:
			connection.execute("PRAGMA journal_mode = WAL")
			connection.execute(
				"CREATE TABLE IF NOT EXISTS app_config (key TEXT PRIMARY KEY, value TEXT NOT NULL)"
			)
			connection.execute(
				"CREATE TABLE IF NOT EXISTS users (username TEXT PRIMARY KEY, payload TEXT NOT NULL)"
			)
		try:
			os.chmod(self.path, 0o600)
		except OSError:
			pass

	def load(self, config_default: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
		storage_exists = self.path.exists()
		self.initialize()
		config = self._load_config()
		users = self._load_users()

		if config is None:
			legacy_config = self.data_dir / "config.json"
			config = self._read_json(legacy_config) or copy.deepcopy(config_default)
			self._restrict_file(legacy_config)
		if users is None:
			if storage_exists:
				# An initialized database can legitimately contain zero users. Do not
				# resurrect a stale legacy backup after the last account is deleted.
				users = {}
			else:
				legacy_users = self.data_dir / "database.json"
				users = self._read_json(legacy_users) or {}
				self._restrict_file(legacy_users)

		for key, value in config_default.items():
			if key not in config:
				config[key] = copy.deepcopy(value)

		# Upsert the migrated/current snapshot. The legacy JSON files are left in
		# place as a recoverable backup and are ignored on subsequent starts.
		self.save_config(config)
		self.save_users(users)
		return config, users

	def _load_config(self) -> dict[str, Any] | None:
		with self._connect() as connection:
			rows = connection.execute("SELECT key, value FROM app_config").fetchall()
		if not rows:
			return None
		return {row["key"]: json.loads(row["value"]) for row in rows}

	def _load_users(self) -> dict[str, Any] | None:
		with self._connect() as connection:
			rows = connection.execute("SELECT username, payload FROM users").fetchall()
		if not rows:
			return None
		return {row["username"]: json.loads(row["payload"]) for row in rows}

	def save_config(self, config: dict[str, Any]) -> None:
		with self._connect() as connection:
			connection.execute("DELETE FROM app_config")
			connection.executemany(
				"INSERT INTO app_config(key, value) VALUES (?, ?)",
				[(key, json.dumps(value, ensure_ascii=False)) for key, value in config.items()],
			)

	def save_users(self, users: dict[str, Any]) -> None:
		with self._connect() as connection:
			connection.execute("DELETE FROM users")
			connection.executemany(
				"INSERT INTO users(username, payload) VALUES (?, ?)",
				[
					(username, json.dumps(payload, ensure_ascii=False))
					for username, payload in users.items()
				],
			)

	@staticmethod
	def _read_json(path: Path) -> dict[str, Any] | None:
		try:
			with path.open("r", encoding="utf-8") as handle:
				value = json.load(handle)
			return value if isinstance(value, dict) else None
		except (FileNotFoundError, OSError, json.JSONDecodeError):
			return None

	@staticmethod
	def _restrict_file(path: Path) -> None:
		try:
			if path.exists():
				os.chmod(path, 0o600)
		except OSError:
			pass
