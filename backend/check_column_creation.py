"""Opt-in integration check: creates and drops one isolated YDB test table.

Run as `python -m backend.check_column_creation` with YDB_ENDPOINT,
YDB_DATABASE, YDB_ACCESS_TOKEN and a test-only JWT_SECRET set.
No production table is read or changed; application queries are redirected
to a new UUID-named table, which is removed in finally.
"""
import json
import os
import re
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor

import ydb
from backend import index as api


def main():
    table = 'release_check_columns_' + uuid.uuid4().hex
    actor = {'id': 'test', 'role': 'admin', 'depot_id': 'test_a', 'display_name': 'Test'}
    with ydb.Driver(endpoint=api.YDB_ENDPOINT, database=api.YDB_DATABASE,
                    credentials=ydb.AccessTokenCredentials(os.environ['YDB_ACCESS_TOKEN'])) as driver:
        driver.wait(fail_fast=True, timeout=15)
        with ydb.QuerySessionPool(driver) as pool:
            class IsolatedPool:
                def execute_with_retries(self, query, parameters=None):
                    assert re.search(r'\bcolumns\b', query)
                    return pool.execute_with_retries(re.sub(r'\bcolumns\b', table, query), parameters)
            isolated = IsolatedPool()
            schema = next(s for s in api.SCHEMA if 'CREATE TABLE IF NOT EXISTS columns (' in s)
            schema = schema.replace('IF NOT EXISTS ', '').replace('columns (', table+' (', 1)
            pool.execute_with_retries(schema)
            try:
                def save(number, title, depot='test_a', column_id=None):
                    return api._column_save(isolated, actor,
                                            {'number': number, 'title': title, 'depotId': depot}, column_id)
                assert save(1, 'original')['statusCode'] == 200
                assert save(1, 'replacement')['statusCode'] == 409
                assert save(1, 'other depot', 'test_b')['statusCode'] == 200
                rows = pool.execute_with_retries(f'SELECT title FROM {table} WHERE id = "test_a_column_1"')[0].rows
                assert rows[0]['title'] == 'original'
                assert save(1, 'edited', column_id='test_a_column_1')['statusCode'] == 200
                rows = pool.execute_with_retries(f'SELECT title FROM {table} WHERE id = "test_a_column_1"')[0].rows
                assert rows[0]['title'] == 'edited'
                assert save(1, 'missing', column_id='missing')['statusCode'] == 404
                for number in range(2, 7):
                    barrier = threading.Barrier(2)
                    def concurrent(title):
                        barrier.wait(timeout=10)
                        return title, save(number, title)['statusCode']
                    with ThreadPoolExecutor(max_workers=2) as executor:
                        results = list(executor.map(concurrent, ['first', 'second']))
                    assert sorted(code for _, code in results) == [200, 409], results
                    winner = next(title for title, code in results if code == 200)
                    rows = pool.execute_with_retries(f'SELECT title FROM {table} WHERE id = "test_a_column_{number}"')[0].rows
                    assert len(rows) == 1 and rows[0]['title'] == winner
                print(json.dumps({'sequentialConflict': 'passed', 'separateDepots': 'passed',
                                  'update': 'passed', 'missingUpdate': 'passed',
                                  'concurrentPairs': 5}))
            finally:
                pool.execute_with_retries(f'DROP TABLE {table}')
                print('Isolated test table removed')


if __name__ == '__main__':
    main()
