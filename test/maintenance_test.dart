import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tchm_app/api.dart';
import 'package:tchm_app/api_backend.dart';
import 'package:tchm_app/main.dart';

void main() {
  for (final role in [UserRole.viewer, UserRole.admin, UserRole.developer]) {
    testWidgets('full maintenance and recovery for ${role.name}', (
      tester,
    ) async {
      var locked = true;
      final client = ApiClient(
        client: MockClient((request) async {
          final lock = {'readsBlocked': locked, 'writesBlocked': locked};
          if (request.url.path == '/lock') {
            return http.Response(jsonEncode(lock), 200);
          }
          if (locked && role != UserRole.developer) {
            return http.Response(
              jsonEncode({
                'error': 'maintenance',
                'code': 'maintenance_full',
                'lock': lock,
              }),
              503,
            );
          }
          return http.Response('{}', 200);
        }),
      );
      final repository = ApiTchmRepository(client);
      await tester.pumpWidget(
        AppDependencies(
          auth: DemoAppAuth(),
          repository: repository,
          firebaseReady: false,
          child: MaterialApp(
            home: ApiMaintenanceGate(
              repository: repository,
              user: AppUser(id: 'test', email: '', displayName: '', role: role),
              child: const Scaffold(body: Text('Рабочие данные')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (role == UserRole.developer) {
        expect(find.text('Рабочие данные'), findsOneWidget);
      } else {
        expect(find.text('Ведутся технические работы'), findsOneWidget);
        expect(find.text('Рабочие данные'), findsNothing);
        locked = false;
        await tester.tap(find.text('Проверить доступ'));
        await tester.pumpAndSettle();
        expect(find.text('Рабочие данные'), findsOneWidget);
      }
    });
  }

  test(
    'read-only allows loading; later full refusal clears cached lists',
    () async {
      var full = false;
      final requests = <String>[];
      final repository = ApiTchmRepository(
        ApiClient(
          client: MockClient((request) async {
            requests.add(request.url.path);
            // Simulate a lock changed between reading /lock and /columns.
            if (request.url.path == '/lock') {
              return http.Response(
                '{"writesBlocked":true,"readsBlocked":false}',
                200,
              );
            }
            if (full) {
              return http.Response(
                jsonEncode({
                  'error': 'maintenance',
                  'code': 'maintenance_full',
                  'lock': {'readsBlocked': true, 'writesBlocked': true},
                }),
                503,
              );
            }
            if (request.url.path == '/columns') {
              return http.Response(
                '{"columns":[{"id":"one","number":1}]}',
                200,
              );
            }
            return http.Response('{}', 200);
          }),
        ),
      );
      await repository.refresh();
      expect(requests.first, '/lock');
      expect((await repository.watchColumns().first).length, 1);
      expect((await repository.watchLock().first).writesBlocked, isTrue);
      full = true;
      await expectLater(repository.refresh(), throwsA(isA<ApiException>()));
      expect(await repository.watchColumns().first, isEmpty);
      expect((await repository.watchLock().first).readsBlocked, isTrue);
    },
  );
}
