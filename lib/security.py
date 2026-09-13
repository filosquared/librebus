"""Security primitives shared by the web application.

This module has no dependency on the application itself, so it can be tested
without starting the server or contacting a school provider.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
import time
from typing import Any
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt


PASSWORD_SCHEME = "scrypt"
SESSION_TTL_SECONDS = 28 * 24 * 60 * 60


def _encode(value: bytes) -> str:
	return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def _decode(value: str) -> bytes:
	return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def hash_password(password: str) -> str:
	"""Return a salted, memory-hard password hash.

	The parameters are encoded with the hash so future migrations can select a
	different cost without losing the ability to verify existing passwords.
	"""
	if not isinstance(password, str) or not password:
		raise ValueError("password must be a non-empty string")

	n, r, p = 2**14, 8, 1
	salt = secrets.token_bytes(16)
	digest = Scrypt(salt=salt, length=64, n=n, r=r, p=p).derive(password.encode("utf-8"))
	return f"{PASSWORD_SCHEME}${n}${r}${p}${_encode(salt)}${_encode(digest)}"


def verify_password(password: Any, stored: Any) -> bool:
	"""Verify current scrypt hashes and legacy SHA-256 hashes during migration."""
	if not isinstance(password, str) or not isinstance(stored, str):
		return False

	if stored.startswith(f"{PASSWORD_SCHEME}$"):
		try:
			scheme, n, r, p, salt, expected = stored.split("$", 5)
			if scheme != PASSWORD_SCHEME:
				return False
			actual = Scrypt(
				salt=_decode(salt), length=64, n=int(n), r=int(r), p=int(p)
			).derive(password.encode("utf-8"))
			return hmac.compare_digest(_encode(actual), expected)
		except (ValueError, TypeError, IndexError):
			return False

	# Existing installations stored SHA-256 digests. Keep them readable so a
	# successful login can transparently upgrade the account in the server.
	legacy = hashlib.sha256(password.encode("utf-8")).hexdigest()
	return hmac.compare_digest(legacy, stored)


def needs_rehash(stored: Any) -> bool:
	return not isinstance(stored, str) or not stored.startswith(f"{PASSWORD_SCHEME}$")


class AuthSessionManager:
	"""Short-lived, in-memory bearer sessions.

	Only an opaque random token is sent to the browser. Provider passwords and
	application passwords never live in a browser cookie.
	"""

	def __init__(self, ttl_seconds: int = SESSION_TTL_SECONDS):
		self.ttl_seconds = ttl_seconds
		self._sessions: dict[str, tuple[str, float]] = {}

	def create(self, subject: str) -> str:
		self._purge_expired()
		token = secrets.token_urlsafe(32)
		self._sessions[token] = (subject, time.time() + self.ttl_seconds)
		return token

	def get_subject(self, token: Any) -> str | None:
		if not isinstance(token, str):
			return None
		session = self._sessions.get(token)
		if session is None:
			return None
		subject, expires_at = session
		if expires_at <= time.time():
			self._sessions.pop(token, None)
			return None
		return subject

	def revoke(self, token: Any) -> None:
		if isinstance(token, str):
			self._sessions.pop(token, None)

	def _purge_expired(self) -> None:
		now = time.time()
		for token, (_, expires_at) in list(self._sessions.items()):
			if expires_at <= now:
				del self._sessions[token]
