class SessionManager:
	def __init__(self, database):
		self.sessions = {}
		self.notifications = {}
		self.updatedb(database)

	def updatedb(self, database):
		for user in database:
			if user not in self.sessions:
				self.sessions[user] = None
			if user not in self.notifications:
				# None means that the first successful fetch is the baseline.  An
				# empty dictionary would make the first fetch look like new data.
				self.notifications[user] = None
		s_ = self.sessions.copy()
		for user in s_:
			if user not in database:
				del self.sessions[user]
				self.notifications.pop(user, None)

	def get(self, user):
		try:
			return self.sessions[user]
		except:
			return None

	def save(self, user, session):
		if user in self.sessions:
			self.sessions[user] = session

	def get_notifications(self, user, notifs):
		"""Return newly observed notification counts for *user*.

		The cache is deliberately in-memory: it is a per-process baseline and
		must never contain school data in the persistent account database.  A
		failed or malformed upstream response is ignored so a temporary outage
		cannot turn all existing records into notifications on the next retry.
		"""
		if user not in self.notifications or not isinstance(notifs, dict):
			return {}

		current = {}
		for subject, value in notifs.items():
			if not isinstance(subject, str) or isinstance(value, bool):
				continue
			try:
				value = int(value)
			except (TypeError, ValueError):
				continue
			current[subject] = max(0, value)

		previous = self.notifications[user]
		self.notifications[user] = current.copy()
		if previous is None:
			return {subject: 0 for subject in current}

		return {
			subject: max(0, value - previous.get(subject, 0))
			for subject, value in current.items()
		}
