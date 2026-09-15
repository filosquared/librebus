"""Single-window macOS launcher for LibreCap."""

from __future__ import annotations

import asyncio
import os
import subprocess
import sys
import threading


# A packaged app has no terminal for the interactive setup wizard. Defaults are
# intentionally local-only; configuration can be changed from the admin panel.
os.environ["LIBRECAP_SKIP_WIZARD"] = "1"
os.environ["LIBRECAP_CHECK_BROWSER"] = "0"

import librusik
from lib import utils


def app_url() -> str:
	scheme = "https" if librusik.config["ssl"] else "http"
	return f"{scheme}://127.0.0.1:{librusik.config['port']}{librusik.config['subdirectory']}"


def show_initial_password() -> None:
	password = utils.INITIAL_ADMIN_PASSWORD
	if not password:
		return
	message = (
		"LibreCap is ready.\n\n"
		f"Administrator: {librusik.config['name']}\n"
		f"Initial password: {password}\n\n"
		"Save this password, then change it in the admin panel."
	)
	escaped = message.replace("\\", "\\\\").replace('"', '\\"')
	script = f'display dialog "{escaped}" with title "LibreCap" buttons {{"OK"}} default button "OK"'
	result = subprocess.run(["/usr/bin/osascript", "-e", script], check=False)
	if result.returncode != 0:
		print(message)


def run_embedded() -> None:
	try:
		import webview
	except ImportError:
		asyncio.run(librusik.run_server(open_browser=True, on_started=show_initial_password))
		return

	ready = threading.Event()
	startup_error: list[BaseException] = []

	def on_started() -> None:
		ready.set()

	def serve() -> None:
		try:
			asyncio.run(librusik.run_server(on_started=on_started))
		except BaseException as error:
			startup_error.append(error)
			ready.set()

	threading.Thread(target=serve, name="librecap-server", daemon=True).start()
	if not ready.wait(timeout=15):
		raise RuntimeError("LibreCap server did not start within 15 seconds")
	if startup_error:
		raise startup_error[0]

	show_initial_password()
	webview.create_window("LibreCap", app_url(), width=1200, height=800, min_size=(900, 600))
	webview.start(debug=False)


if __name__ == "__main__":
	if sys.platform != "darwin":
		raise SystemExit("The macOS app launcher must run on macOS.")
	run_embedded()
