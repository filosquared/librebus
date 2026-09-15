import unittest
from datetime import datetime, timedelta

from lib.api.librus import Librus


class FakeLibrus(Librus):
	async def get_data(self, method):
		if method == "TimetableEntries":
			return {
				"TimetableEntries": [
					{"Classroom": {"Id": 7, "Name": "Room 7", "Symbol": "B-07"}},
				]
			}
		return None


class LibrusAdapterTests(unittest.IsolatedAsyncioTestCase):
	async def test_classrooms_are_indexed_by_string_id_and_symbol(self):
		classrooms = await FakeLibrus().get_classrooms()
		self.assertEqual(classrooms, {"7": "B-07"})

	async def test_notifications_count_recent_changes_only(self):
		now = datetime.now()
		recent = (now - timedelta(days=2)).strftime("%Y-%m-%d %H:%M:%S")
		old = (now - timedelta(days=30)).strftime("%Y-%m-%d %H:%M:%S")

		class NotificationLibrus(Librus):
			async def get_data(self, method):
				return {
					"Grades": {"Grades": [{"AddDate": recent}, {"AddDate": old}]},
					"HomeWorks": {"HomeWorks": [{"AddDate": recent}, {"AddDate": old}]},
					"Attendances": {"Attendances": [
						{"AddDate": recent, "Type": {"Id": 1}},
						{"AddDate": recent, "Type": {"Id": 2}},
						{"AddDate": old, "Type": {"Id": 2}},
					]},
					"Attendances/Types": {
						"Types": [
							{"Id": 1, "IsPresenceKind": True},
							{"Id": 2, "IsPresenceKind": False},
						]
					},
					"ParentTeacherConferences": {
						"ParentTeacherConferences": [
							{"AddDate": recent},
							{"AddDate": old},
						]
					},
				}[method]

		result = await NotificationLibrus().get_notifications()
		self.assertEqual(result, {"grades": 1, "exams": 1, "absences": 1, "conferences": 1})

	async def test_notifications_return_none_for_incomplete_upstream_data(self):
		class IncompleteLibrus(Librus):
			async def get_data(self, method):
				return None

		self.assertIsNone(await IncompleteLibrus().get_notifications())
