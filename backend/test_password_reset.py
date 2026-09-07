"""Password reset role assignment; test JWTs, no emails or cloud writes."""
import time
import unittest
import urllib.parse
from unittest.mock import patch

from backend.test_admin_permissions import api, Pool


def token(**changes):
    return api.jwt.encode({'act': 'reset', 'sub': 'actor',
                           'exp': int(time.time()) + 300, **changes},
                          api.JWT_SECRET, algorithm='HS256')


def profile(role='viewer', status='pending', email='KutulovSV@transport.mos.ru'):
    return {'role': role, 'status': status, 'email': email}


class PasswordResetTests(unittest.TestCase):
    def setUp(self):
        self.admins = patch.object(api, 'ADMIN_EMAILS', {'kutulovsv@transport.mos.ru'})
        self.admins.start()
        self.addCleanup(self.admins.stop)
        self.hashing = patch.object(api, '_hash_password', return_value='test-password-hash')
        self.hashing.start()
        self.addCleanup(self.hashing.stop)

    def apply(self, pool, **body):
        return api._reset_apply(pool, {}, {'token': token(), 'password': 'test-password', **body})

    def test_pending_reserved_email_becomes_admin_for_both_registration_roles(self):
        for role in ('viewer', 'tchm'):
            pool = Pool([profile(role)], [{'id': 'actor'}])
            self.assertEqual(self.apply(pool)['statusCode'], 200)
            parameters = pool.writes[0][1]
            self.assertEqual(parameters['$role'][0], 'admin')
            self.assertEqual(parameters['$hash'][0], 'test-password-hash')
            self.assertEqual(parameters['$old_status'][0], 'pending')

    def test_other_email_keeps_registration_role_despite_body_spoofing(self):
        for role in ('viewer', 'tchm'):
            pool = Pool([profile(role, email='ordinary@example.test')], [{'id': 'actor'}])
            self.assertEqual(self.apply(pool, email='kutulovsv@transport.mos.ru', role='developer')['statusCode'], 200)
            self.assertEqual(pool.writes[0][1]['$role'][0], role)

    def test_active_accounts_keep_their_current_role(self):
        for role in ('viewer', 'tchm', 'admin', 'developer'):
            pool = Pool([profile(role, status='active')], [{'id': 'actor'}])
            self.assertEqual(self.apply(pool)['statusCode'], 200)
            self.assertEqual(pool.writes[0][1]['$role'][0], role)

    def test_disabled_unknown_and_missing_accounts_cannot_be_activated(self):
        for rows, expected in [([profile(status='disabled')], 403),
                               ([profile(status='unknown')], 403), ([], 404)]:
            pool = Pool(rows)
            self.assertEqual(self.apply(pool)['statusCode'], expected)
            self.assertEqual(pool.writes, [])

    def test_changed_or_deleted_profile_does_not_get_recreated(self):
        pool = Pool([profile()], [])
        self.assertEqual(self.apply(pool)['statusCode'], 409)
        query = pool.writes[0][0]
        self.assertNotIn('UPSERT', query)
        self.assertIn('status = $old_status AND role = $old_role', query)
        self.assertIn('AND email = $email RETURNING id', query)

    def test_expired_wrong_purpose_or_malformed_links_do_not_reach_database(self):
        for value in [token(exp=int(time.time())-1), token(act='verify'),
                      token(act='access'), token(sub=''), 'invalid']:
            pool = Pool()
            self.assertEqual(self.apply(pool, token=value)['statusCode'], 400)
            self.assertEqual(pool.calls, [])
        for claims in [{'act': 'reset', 'sub': 'actor'},
                       {'act': 'reset', 'exp': int(time.time())+300}]:
            pool = Pool()
            value = api.jwt.encode(claims, api.JWT_SECRET, algorithm='HS256')
            self.assertEqual(self.apply(pool, token=value)['statusCode'], 400)
            self.assertEqual(pool.calls, [])

    def test_short_password_does_not_change_role(self):
        pool = Pool()
        self.assertEqual(self.apply(pool, password='short')['statusCode'], 400)
        self.assertEqual(pool.calls, [])

    def test_browser_form_has_same_role_assignment_as_json(self):
        pool = Pool([profile('tchm')], [{'id': 'actor'}])
        event = {'body': urllib.parse.urlencode({'token': token(), 'password': 'test-password'})}
        self.assertEqual(api._reset_apply(pool, event, {})['statusCode'], 200)
        self.assertEqual(pool.writes[0][1]['$role'][0], 'admin')


if __name__ == '__main__':
    unittest.main()
