"""Access tokens and account status: test-only JWTs, no cloud writes."""
import time
import unittest
from unittest.mock import patch

from backend.test_admin_permissions import api, Pool, user


def claims(**changes):
    now = int(time.time())
    return {'act': 'access', 'sub': 'actor', 'iat': now, 'exp': now+300, **changes}


def headers(payload):
    return {'Authorization': 'Bearer '+api.jwt.encode(payload, api.JWT_SECRET, algorithm='HS256')}


def account(status='active'):
    return {**user('viewer'), 'status': status, 'email': 'test@example.test', 'personnel_number': ''}


class AccessTokenTests(unittest.TestCase):
    def test_issued_token_is_accepted(self):
        token = api._issue_token('actor', 'viewer', 'tch16')
        decoded = api._read_token({'authorization': 'Bearer '+token})
        self.assertEqual(decoded['act'], 'access')
        self.assertEqual(decoded['sub'], 'actor')

    def test_service_tokens_and_old_access_tokens_are_rejected(self):
        for purpose in ['verify', 'reset', 'signup', 'state', '', None]:
            with self.subTest(purpose=purpose):
                payload = claims(act=purpose)
                if purpose is None:
                    payload.pop('act')
                self.assertIsNone(api._read_token(headers(payload)))

    def test_required_claims_cannot_be_omitted(self):
        for field in ['act', 'sub', 'iat', 'exp']:
            payload = claims()
            payload.pop(field)
            self.assertIsNone(api._read_token(headers(payload)))

    def test_invalid_or_expired_claims_are_rejected(self):
        now = int(time.time())
        for changes in [{'sub': ''}, {'sub': 123}, {'iat': now+60}, {'exp': now-1}, {'exp': now}, {'iat': str(now)}, {'iat': True}, {'exp': str(now+300)}, {'iat': []}, {'exp': {}}, {'iat': None}]:
            with self.subTest(changes=changes):
                self.assertIsNone(api._read_token(headers(claims(**changes))))

    def test_malformed_headers_and_wrong_signatures_are_rejected(self):
        wrong = api.jwt.encode(claims(), 'different-test-secret-of-sufficient-length', algorithm='HS256')
        for value in ['', 'Basic x', 'Bearer malformed', 123, None, 'Bearer '+wrong]:
            self.assertIsNone(api._read_token({'Authorization': value}))

    def test_only_active_profiles_can_authenticate(self):
        for status in ['pending', 'disabled', 'unknown', None, 'active']:
            with self.subTest(status=status):
                result = api._auth(Pool([account(status)]), headers(claims()))
                self.assertEqual(result is not None, status == 'active')
        self.assertIsNone(api._auth(Pool([]), headers(claims())))

    def test_me_rejects_inactive_profiles(self):
        for status in ['pending', 'disabled', 'unknown', None]:
            self.assertEqual(api._me(Pool([account(status)]), claims())['statusCode'], 403)
        self.assertEqual(api._me(Pool([account()]), claims())['statusCode'], 200)

    def test_protected_routes_reject_service_tokens_before_reading_data(self):
        routes = [('GET', '/me'), ('GET', '/columns'), ('GET', '/machinists'), ('GET', '/users'), ('GET', '/lock'), ('PUT', '/lock'), ('POST', '/columns'), ('POST', '/machinists')]
        for purpose in ['verify', 'reset', 'signup', 'state']:
            for method, path in routes:
                with self.subTest(purpose=purpose, path=path, method=method):
                    pool = Pool()
                    with patch.object(api, '_connect', return_value=pool), patch.object(api, '_ensure_schema'):
                        result = api.handler({'httpMethod': method, 'path': path, 'headers': headers(claims(act=purpose)), 'body': '{}'}, None)
                    self.assertEqual(result['statusCode'], 401)
                    self.assertEqual(pool.calls, [])

    def test_pending_access_token_cannot_reach_data_handlers(self):
        for method, path in [('GET', '/columns'), ('POST', '/columns'), ('PUT', '/lock'), ('POST', '/users/delete')]:
            pool = Pool([account('pending')])
            with patch.object(api, '_connect', return_value=pool), patch.object(api, '_ensure_schema'):
                result = api.handler({'httpMethod': method, 'path': path, 'headers': headers(claims()), 'body': '{}'}, None)
            self.assertEqual(result['statusCode'], 401)
            self.assertEqual(pool.writes, [])
            self.assertEqual(len(pool.calls), 1)

    def test_valid_access_token_reaches_me_and_scoped_data(self):
        for path in ['/me', '/columns']:
            pool = Pool([account()])
            with patch.object(api, '_connect', return_value=pool), patch.object(api, '_ensure_schema'):
                result = api.handler({'httpMethod': 'GET', 'path': path, 'headers': headers(claims())}, None)
            self.assertEqual(result['statusCode'], 200)


if __name__ == '__main__':
    unittest.main()
