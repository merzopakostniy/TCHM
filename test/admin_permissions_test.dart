import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tchm_app/api.dart';
import 'package:tchm_app/api_backend.dart';
import 'package:tchm_app/main.dart';

const admin = AppUser(
  id: 'test-admin',
  email: 'admin@example.test',
  displayName: 'Администратор',
  role: UserRole.admin,
);

void main() {
  test('admin can manage all depots but cannot control the database lock', () {
    expect(admin.role.canManageAllDepots, isTrue);
    expect(admin.role.canManageAccounts, isTrue);
    expect(admin.role.canEditAny, isTrue);
    expect(admin.role.canExportData, isTrue);
    expect(admin.role.canManageDatabaseLock, isFalse);
    expect(UserRole.developer.canManageDatabaseLock, isTrue);
    expect(UserRole.tchm.canManageAllDepots, isFalse);
    expect(UserRole.viewer.canManageAccounts, isFalse);
    expect(roleFromString('admin'), UserRole.admin);
  });

  test(
    'repositories reject an admin lock request before making a request',
    () async {
      final local = LocalTchmRepository();
      final remote = ApiTchmRepository(
        ApiClient(baseUrl: 'https://unused.invalid'),
      );
      for (final repository in [local, remote]) {
        await expectLater(
          repository.setLock(const AppLock(readsBlocked: true), admin),
          throwsStateError,
        );
      }
      expect((await local.watchLock().first).isActive, isFalse);
    },
  );

  for (final role in [UserRole.admin, UserRole.developer]) {
    testWidgets('${role.name} overview exposes the correct controls', (
      tester,
    ) async {
      await tester.pumpWidget(
        AppDependencies(
          repository: LocalTchmRepository(),
          auth: DemoAppAuth(),
          child: MaterialApp(
            home: DepotOverviewScreen(
              user: AppUser(
                id: 'test-${role.name}',
                email: '',
                displayName: role.title,
                role: role,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Депо'), findsOneWidget);
      expect(
        find.byTooltip('Режим обслуживания'),
        role == UserRole.developer ? findsOneWidget : findsNothing,
      );
    });
  }
}
