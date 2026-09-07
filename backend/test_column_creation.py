"""Column creation conflict handling and update-only behavior."""
import json
import unittest
from unittest.mock import patch

from backend.test_admin_permissions import api, Pool, user
from backend.test_access_tokens import account, claims, headers


class ColumnCreationTests(unittest.TestCase):
    def test_query_service_duplicate_message_returns_conflict(self):
        pool = Pool()
        with patch.object(pool, 'execute_with_retries', side_effect=api.ydb.PreconditionFailed('Conflict with existing key.')):
            self.assertEqual(api._column_save(pool, user(), {'number': 1})['statusCode'], 409)

    def test_duplicate_post_returns_conflict_at_http_boundary(self):
        pool = Pool()
        def execute(query, parameters=None):
            if 'FROM users' in query:
                return Pool([{**account(), 'role': 'tchm'}]).execute_with_retries(query, parameters)
            if 'app_config' in query:
                return Pool().execute_with_retries(query, parameters)
            self.assertIn('INSERT INTO columns', query)
            raise api.ydb.PreconditionFailed('Operation aborted due to constraint violation: insert_pk')
        pool.execute_with_retries = execute
        with patch.object(api, '_connect', return_value=pool), patch.object(api, '_ensure_schema'):
            response = api.handler({'httpMethod': 'POST', 'path': '/columns',
                                    'headers': headers(claims()),
                                    'body': json.dumps({'number': 1})}, None)
        self.assertEqual(response['statusCode'], 409)
        self.assertIn('уже существует', json.loads(response['body'])['error'])

    def test_unrelated_database_failure_is_not_reported_as_duplicate(self):
        pool = Pool()
        pool.execute_with_retries = lambda *args: (_ for _ in ()).throw(api.ydb.PreconditionFailed('unrelated constraint'))
        with self.assertRaises(api.ydb.PreconditionFailed):
            api._column_save(pool, user(), {'number': 1})

    def test_invalid_numbers_are_rejected_before_database_access(self):
        for number in [True, False, 0, -1, 1.5, '1', None, 4_294_967_296]:
            pool = Pool()
            self.assertEqual(api._column_save(pool, user(), {'number': number})['statusCode'], 400)
            self.assertEqual(pool.calls, [])

    def test_update_does_not_recreate_deleted_column(self):
        pool = Pool([{'depot_id': 'tch16'}], [])
        result = api._column_save(pool, user(), {'number': 1}, 'existing')
        self.assertEqual(result['statusCode'], 404)
        query = pool.writes[0][0]
        self.assertIn('UPDATE columns', query)
        self.assertNotIn('UPSERT', query)
        self.assertIn('WHERE id = $id AND depot_id = $depot', query)

    def test_new_column_remains_scoped_to_depot(self):
        for role in ('tchm', 'admin', 'developer'):
            pool = Pool()
            result = api._column_save(pool, user(role), {'number': 1, 'depotId': 'tch08_bl'})
            self.assertEqual(result['statusCode'], 200)
            expected = 'tch16' if role == 'tchm' else 'tch08_bl'
            self.assertEqual(pool.writes[0][1]['$id'][0], expected+'_column_1')
        pool = Pool()
        self.assertEqual(api._column_save(pool, user('viewer'), {'number': 1})['statusCode'], 403)
        self.assertEqual(pool.calls, [])


if __name__ == '__main__':
    unittest.main()
