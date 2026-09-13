import unittest

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

