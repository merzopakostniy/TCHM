"""Offline permission tests: no cloud requests or outgoing email."""
import json
import os
import time
import unittest
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault('YDB_ENDPOINT', 'test')
os.environ.setdefault('YDB_DATABASE', 'test')
os.environ.setdefault('JWT_SECRET', 'test-secret-not-for-production-32-characters')

from backend import index as api


class Pool:
    def __init__(self, *responses):
        self.responses = list(responses)
        self.calls = []

    def execute_with_retries(self, query, params=None):
        self.calls.append((query, params or {}))
        rows = self.responses.pop(0) if self.responses else []
        return [SimpleNamespace(rows=rows)]

    def retry_operation_sync(self, operation):
        from contextlib import contextmanager
        pool = self
        class Transaction:
            def __enter__(self):
                return self
            def __exit__(self, *args):
                pass
            @contextmanager
            def execute(self, query, parameters=None):
                yield pool.execute_with_retries(query, parameters)
            def commit(self):
                pool.committed = True
            def rollback(self):
                pool.rolled_back = True
        return operation(SimpleNamespace(transaction=lambda mode: Transaction()))

    @property
    def writes(self):
        return [(q, p) for q, p in self.calls if any(op in q for op in ('INSERT INTO', 'UPSERT', 'UPDATE ', 'DELETE '))]


def user(role='admin', depot='tch16'):
    return {'id': 'actor', 'role': role, 'depot_id': depot, 'display_name': 'Test Admin'}


class AdminPermissionsTests(unittest.TestCase):
    def test_only_developer_can_change_lock(self):
        for role in ('admin', 'tchm', 'viewer'):
            pool = Pool()
            self.assertEqual(api._lock_write(pool, user(role), {'readsBlocked': True})['statusCode'], 403)
            self.assertEqual(pool.calls, [])
        pool = Pool()
        self.assertEqual(api._lock_write(pool, user('developer'), {})['statusCode'], 200)
        self.assertEqual(len(pool.writes), 1)

    def test_management_can_list_all_depots(self):
        for role in ('admin', 'developer'):
            for handler, table in ((api._columns_list, 'columns'), (api._machinists_list, 'machinists')):
                pool = Pool()
                self.assertEqual(handler(pool, user(role), {})['statusCode'], 200)
                self.assertEqual(pool.calls[0], ('SELECT * FROM '+table, {}))

    def test_tchm_cannot_spoof_another_depot(self):
        for handler in (api._columns_list, api._machinists_list):
            pool = Pool()
            handler(pool, user('tchm'), {'depotId': 'tch08_bl'})
            self.assertEqual(pool.calls[0][1]['$depot'][0], 'tch16')

    def test_management_can_filter_by_another_depot(self):
        pool = Pool()
        api._columns_list(pool, user(), {'depotId': 'tch08_bl'})
        self.assertEqual(pool.calls[0][1]['$depot'][0], 'tch08_bl')

    def test_unassigned_viewer_does_not_get_global_data(self):
        pool = Pool()
        api._columns_list(pool, user('viewer', None), {})
        self.assertEqual(pool.calls, [])

    def test_admin_edits_column_in_another_depot(self):
        pool = Pool([{'depot_id': 'tch08_bl'}], [{'id': 'column-bl'}])
        self.assertEqual(api._column_save(pool, user(), {'number': 2}, 'column-bl')['statusCode'], 200)
        self.assertEqual(pool.writes[0][1]['$depot'][0], 'tch08_bl')

    def test_tchm_cannot_edit_foreign_column(self):
        pool = Pool([{'depot_id': 'tch08_bl'}])
        self.assertEqual(api._column_save(pool, user('tchm'), {'number': 2, 'depotId': 'tch08_bl'}, 'column-bl')['statusCode'], 403)
        self.assertEqual(pool.writes, [])

    def test_admin_creates_column_in_selected_depot(self):
        pool = Pool()
        self.assertEqual(api._column_save(pool, user(), {'number': 2, 'depotId': 'tch08_bl'})['statusCode'], 200)
        self.assertEqual(pool.writes[0][1]['$depot'][0], 'tch08_bl')

    def test_admin_edits_machinist_using_column_depot(self):
        pool = Pool([{'depot_id': 'tch08_bl'}])
        result = api._machinist_save(pool, user(), {'columnId': 'column-bl', 'fullName': 'Тестовый сотрудник'})
        self.assertEqual(result['statusCode'], 200)
        self.assertEqual(pool.writes[0][1]['$depot'][0], 'tch08_bl')

    def test_admin_deletes_foreign_machinist_but_tchm_cannot(self):
        for role, status in [('admin', 200), ('tchm', 403), ('viewer', 403)]:
            pool = Pool([{'depot_id': 'tch08_bl', 'column_id': 'column-bl'}])
            self.assertEqual(api._machinist_delete(pool, user(role), 'machinist')['statusCode'], status)
            self.assertEqual(len(pool.writes), int(status == 200))

    def test_account_list_requires_management_role(self):
        for role, status in [('admin', 200), ('developer', 200), ('tchm', 403), ('viewer', 403)]:
            self.assertEqual(api._users_list(Pool(), user(role), {})['statusCode'], status)

    def test_admin_cannot_change_developer_even_in_mixed_batch(self):
        for handler in (api._users_status, api._users_delete):
            pool = Pool([{'role': 'viewer'}], [{'role': 'developer'}])
            result = handler(pool, user(), {'userIds': ['ordinary', 'developer'], 'status': 'disabled'})
            self.assertEqual(result['statusCode'], 403)
            self.assertEqual(pool.writes, [])

    def test_admin_can_manage_regular_accounts(self):
        for handler in (api._users_status, api._users_delete):
            pool = Pool([{'role': 'tchm'}])
            self.assertEqual(handler(pool, user(), {'userIds': ['ordinary'], 'status': 'disabled'})['statusCode'], 200)
            self.assertEqual(len(pool.writes), 1)

    def test_admin_cannot_disable_or_delete_self(self):
        for handler in (api._users_status, api._users_delete):
            pool = Pool()
            self.assertEqual(handler(pool, user(), {'userIds': ['actor'], 'status': 'disabled'})['statusCode'], 400)
            self.assertEqual(pool.calls, [])

    def test_role_is_read_from_database_not_token(self):
        row = {**user(), 'status': 'active'}
        pool = Pool([row])
        with patch.object(api, '_read_token', return_value={'sub': 'actor', 'role': 'developer'}):
            authenticated = api._auth(pool, {})
        self.assertEqual(authenticated['role'], 'admin')
        self.assertEqual(api._lock_write(pool, authenticated, {})['statusCode'], 403)


class AdminEmailTests(unittest.TestCase):
    def setUp(self):
        self.patch = patch.object(api, 'ADMIN_EMAILS', {'kutulovsv@transport.mos.ru'})
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def verify(self, status='pending', role='viewer', email='KutulovSV@transport.mos.ru'):
        pool = Pool([{'status': status, 'role': role, 'email': email}])
        token = api.jwt.encode({'act': 'verify', 'sub': 'target', 'exp': int(time.time())+300}, api.JWT_SECRET, algorithm='HS256')
        result = api._verify(pool, {'token': token})
        return result, pool

    def test_reserved_email_gets_admin_only_after_verification(self):
        result, pool = self.verify()
        self.assertEqual(result['statusCode'], 200)
        self.assertEqual(pool.writes[0][1]['$role'][0], 'admin')

    def test_other_email_does_not_get_admin(self):
        _, pool = self.verify(email='other@transport.mos.ru')
        self.assertEqual(pool.writes[0][1]['$role'][0], 'viewer')

    def test_reusing_link_does_not_restore_revoked_role(self):
        _, pool = self.verify(status='active', role='viewer')
        self.assertEqual(pool.writes[0][1]['$role'][0], 'viewer')

    def test_disabled_account_is_not_reactivated_by_link(self):
        result, pool = self.verify(status='disabled')
        self.assertEqual(result['statusCode'], 403)
        self.assertEqual(pool.writes, [])

    def test_invalid_verification_does_not_touch_database(self):
        pool = Pool()
        self.assertEqual(api._verify(pool, {'token': 'forged'})['statusCode'], 400)
        self.assertEqual(pool.calls, [])

    def test_registration_keeps_pending_role_and_cannot_request_admin(self):
        body = {'email': 'KutulovSV@transport.mos.ru', 'password': 'test-password', 'displayName': 'Test User', 'depotId': 'tch16', 'role': 'viewer', 'inviteCode': 'test'}
        pool = Pool()
        with patch.object(api, '_invite_ok', return_value=True), patch.object(api, '_find_user_by_email', return_value=None), patch.object(api, '_mail_configured', return_value=True), patch.object(api, '_send_verification'), patch.object(api, '_hash_password', return_value='test-password-hash'), patch.object(api, 'ALLOWED_EMAIL_DOMAINS', []):
            result = api._register(pool, body)
        self.assertEqual(result['statusCode'], 200)
        self.assertEqual(json.loads(result['body'])['status'], 'pending')
        self.assertEqual(pool.writes[0][1]['$role'][0], 'viewer')
        body['role'] = 'admin'
        self.assertEqual(api._register(Pool(), body)['statusCode'], 400)

    def test_yandex_uses_signed_email_not_body_email(self):
        for email, role in [('KutulovSV@transport.mos.ru', 'admin'), ('other@transport.mos.ru', 'viewer')]:
            ticket = api.jwt.encode({'act': 'signup', 'yid': 'test-yid', 'email': email, 'exp': int(time.time())+300}, api.JWT_SECRET, algorithm='HS256')
            pool = Pool()
            with patch.object(api, '_invite_ok', return_value=True), patch.object(api, '_find_user_by_email', return_value=None), patch.object(api, '_find_user_by_yandex', return_value=None):
                result = api._yandex_signup(pool, {'ticket': ticket, 'displayName': 'Test User', 'depotId': 'tch16', 'email': 'kutulovsv@transport.mos.ru', 'role': 'viewer'})
            self.assertEqual(result['statusCode'], 200)
            self.assertEqual(pool.writes[0][1]['$role'][0], role)


if __name__ == '__main__':
    unittest.main()
