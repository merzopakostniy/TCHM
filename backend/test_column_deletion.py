"""Column deletion permissions and protection of related machinists."""
import unittest
from backend.test_admin_permissions import api, Pool, user


class ColumnDeletionTests(unittest.TestCase):
    def test_viewer_cannot_delete(self):
        pool = Pool()
        self.assertEqual(api._column_delete(pool, user('viewer'), 'c')['statusCode'], 403)
        self.assertEqual(pool.calls, [])

    def test_missing_column(self):
        pool = Pool([])
        self.assertEqual(api._column_delete(pool, user(), 'missing')['statusCode'], 404)
        self.assertEqual(pool.writes, [])

    def test_tchm_cannot_delete_foreign_column(self):
        pool = Pool([{'depot_id': 'tch08'}])
        self.assertEqual(api._column_delete(pool, user('tchm'), 'c')['statusCode'], 403)
        self.assertEqual(pool.writes, [])

    def test_nonempty_column_is_preserved_for_every_editor(self):
        for role in ('tchm', 'admin', 'developer'):
            pool = Pool([{'depot_id': 'tch16'}], [{'id': 'm'}])
            self.assertEqual(api._column_delete(pool, user(role), 'c')['statusCode'], 409)
            self.assertEqual(pool.writes, [])
            self.assertFalse(getattr(pool, 'committed', False))

    def test_empty_column_is_deleted_without_touching_people(self):
        for role, depot in [('tchm', 'tch16'), ('admin', 'tch08'), ('developer', 'tch08')]:
            pool = Pool([{'depot_id': depot}], [])
            self.assertEqual(api._column_delete(pool, user(role), 'c')['statusCode'], 200)
            self.assertEqual(len(pool.writes), 1)
            self.assertIn('DELETE FROM columns', pool.writes[0][0])
            self.assertTrue(pool.committed)

    def test_save_cannot_recreate_a_deleted_columns_machinist(self):
        pool = Pool([])
        result = api._machinist_save(pool, user(), {'columnId': 'deleted', 'fullName': 'Test'})
        self.assertEqual(result['statusCode'], 404)
        self.assertEqual(pool.writes, [])
        self.assertFalse(getattr(pool, 'committed', False))


if __name__ == '__main__':
    unittest.main()
