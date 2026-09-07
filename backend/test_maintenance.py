"""HTTP maintenance enforcement with test JWTs and an isolated fake database."""
import json
import unittest
from unittest.mock import patch

from backend.test_access_tokens import account, claims, headers
from backend.test_admin_permissions import api, Pool


def lock(writes=False, reads=False):
    return {'writes_blocked': writes, 'reads_blocked': reads,
            'note': 'Технические работы', 'updated_by': 'developer'}


READS = [('GET', '/columns', '_columns_list'),
         ('GET', '/machinists', '_machinists_list'),
         ('GET', '/users', '_users_list')]
WRITES = [('POST', '/columns', '_column_save'),
          ('PUT', '/columns/one', '_column_save'),
          ('DELETE', '/columns/one', '_column_delete'),
          ('POST', '/machinists', '_machinist_save'),
          ('PUT', '/machinists/one', '_machinist_save'),
          ('DELETE', '/machinists/one', '_machinist_delete'),
          ('PUT', '/users/status', '_users_status'),
          ('POST', '/users/delete', '_users_delete')]


class MaintenanceTests(unittest.TestCase):
    def request(self, pool, method, path, body=None):
        with patch.object(api, '_connect', return_value=pool), patch.object(api, '_ensure_schema'):
            return api.handler({'httpMethod': method, 'path': path,
                                'headers': headers(claims()),
                                'body': json.dumps(body or {})}, None)

    def test_all_roles_and_data_routes_obey_both_flags(self):
        for role in ('viewer', 'tchm', 'admin', 'developer'):
            for writes, reads in ((False, False), (True, False), (False, True), (True, True)):
                for method, path, handler in READS + WRITES:
                    with self.subTest(role=role, writes=writes, reads=reads, method=method, path=path):
                        pool = Pool([{**account(), 'role': role}], [lock(writes, reads)])
                        blocked = (reads and (method != 'GET' or role != 'developer')) or (writes and method != 'GET')
                        with patch.object(api, handler, return_value=api._reply(200, {})) as target:
                            result = self.request(pool, method, path)
                        self.assertEqual(result['statusCode'], 503 if blocked else 200)
                        self.assertEqual(target.call_count, 0 if blocked else 1)
                        self.assertEqual(len(pool.calls), 2)
                        self.assertEqual(pool.writes, [])
                        if blocked:
                            body = json.loads(result['body'])
                            self.assertEqual(body['code'], 'maintenance_full' if reads else 'maintenance_read_only')
                            self.assertEqual(body['lock']['readsBlocked'], reads)

    def test_lock_can_be_read_and_only_developer_can_unlock(self):
        for role in ('viewer', 'tchm', 'admin', 'developer'):
            profile = {**account(), 'role': role}
            pool = Pool([profile], [lock(True, True)])
            self.assertEqual(self.request(pool, 'GET', '/lock')['statusCode'], 200)
            pool = Pool([profile])
            response = self.request(pool, 'PUT', '/lock', {'readsBlocked': False, 'writesBlocked': False})
            self.assertEqual(response['statusCode'], 200 if role == 'developer' else 403)
            self.assertEqual(len(pool.writes), 1 if role == 'developer' else 0)

    def test_missing_config_preserves_normal_operation(self):
        pool = Pool([account()], [])
        with patch.object(api, '_columns_list', return_value=api._reply(200, {})) as target:
            self.assertEqual(self.request(pool, 'GET', '/columns')['statusCode'], 200)
        target.assert_called_once()

    def test_flags_are_reread_on_the_next_request(self):
        pool = Pool([account()], [lock()], [account()], [lock(reads=True)], [account()], [lock()])
        with patch.object(api, '_columns_list', return_value=api._reply(200, {})) as target:
            codes = [self.request(pool, 'GET', '/columns')['statusCode'] for _ in range(3)]
        self.assertEqual(codes, [200, 503, 200])
        self.assertEqual(target.call_count, 2)

    def test_config_failure_does_not_allow_data_access(self):
        with patch.object(api, '_lock_read', side_effect=RuntimeError('unavailable')), patch.object(api, '_column_save') as target:
            result = self.request(Pool([account()]), 'POST', '/columns')
        self.assertEqual(result['statusCode'], 500)
        target.assert_not_called()

    def test_identity_and_login_remain_available_for_recovery(self):
        self.assertEqual(self.request(Pool([account()]), 'GET', '/me')['statusCode'], 200)
        with patch.object(api, '_login', return_value=api._reply(200, {})) as target:
            self.assertEqual(self.request(Pool(), 'POST', '/auth/login')['statusCode'], 200)
        target.assert_called_once()
        self.assertEqual(self.request(Pool(), 'GET', '/health')['statusCode'], 200)


if __name__ == '__main__':
    unittest.main()
