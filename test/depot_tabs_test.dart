import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tchm_app/main.dart';

const _developer = AppUser(
  id: 'developer',
  email: '',
  displayName: 'Разработчик',
  role: UserRole.developer,
);

class _DepotRepository extends LocalTchmRepository {
  String? depotId;

  @override
  Stream<List<AppUser>> watchUsers() async* {
    yield [
      AppUser(
        id: 'tchm-test',
        email: 'tchm@example.test',
        displayName: 'Петров П.П.',
        role: UserRole.tchm,
        depotId: depotId,
      ),
    ];
  }
}

void main() {
  testWidgets('depot tabs can reopen streams and show current data', (
    tester,
  ) async {
    final repository = _DepotRepository();
    final column = (await repository.watchColumns().first).first;
    repository.depotId = column.depotId;

    await tester.pumpWidget(
      AppDependencies(
        repository: repository,
        auth: DemoAppAuth(),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: DepotColumnsScreen(
            user: _developer,
            depotId: column.depotId,
            title: 'Тестовое депо',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(column.title).hitTestable(), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Учётные записи'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Петров П.П.').hitTestable(), findsOneWidget);

      // Updates while a tab is unmounted must appear when returning to it.
      await repository.updateColumn(
        column.copyWith(tchmName: 'Обновление $i'),
        _developer,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Колонны'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('ТЧМ: Обновление $i').hitTestable(), findsOneWidget);
    }

    // Start in the list padding so the column's edit swipe does not consume it.
    final tabOrigin = tester.getTopLeft(find.byType(TabBarView));
    await tester.dragFrom(
      tabOrigin + const Offset(750, 4),
      const Offset(-700, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Петров П.П.').hitTestable(), findsOneWidget);
    await tester.dragFrom(
      tabOrigin + const Offset(50, 4),
      const Offset(700, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('ТЧМ: Обновление 2').hitTestable(), findsOneWidget);
  });
}
