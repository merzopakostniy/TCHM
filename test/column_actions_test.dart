import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tchm_app/column_actions.dart';
import 'package:tchm_app/main.dart';

const _developer = AppUser(
  id: 'developer',
  email: '',
  displayName: 'Разработчик',
  role: UserRole.developer,
  depotId: 'test',
);

class _Repository extends LocalTchmRepository {
  @override
  Stream<List<ColumnGroup>> watchColumns() => super.watchColumns().map(
    (items) => items.where((item) => item.number >= 42).toList(),
  );
}

void main() {
  testWidgets(
    'short swipe reveals actions and deletion requires confirmation',
    (tester) async {
      final repository = _Repository();
      await repository.createColumn(number: 42, user: _developer);
      await tester.pumpWidget(
        AppDependencies(
          repository: repository,
          auth: DemoAppAuth(),
          firebaseReady: false,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const HomeScreen(user: _developer),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byType(ColumnActions);
      await tester.drag(card, const Offset(-65, 0));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Изменить').hitTestable(), findsOneWidget);
      expect(find.text('Удалить').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Изменить').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Кто ведёт колонну'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      await tester.drag(card, const Offset(-65, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Удалить «Колонна №42»?'), findsOneWidget);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect((await repository.watchColumns().first), hasLength(1));
      await tester.drag(card, const Offset(-65, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();
      expect(await repository.watchColumns().first, isEmpty);
      expect(card, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opening another card closes the previous actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: List.generate(
              2,
              (index) => ColumnActions(
                onEdit: () {},
                onDelete: () {},
                child: Container(
                  height: 80,
                  color: Colors.white,
                  child: Text('Колонна $index'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final cards = find.byType(ColumnActions);
    await tester.drag(cards.at(0), const Offset(-65, 0));
    await tester.pumpAndSettle();
    await tester.drag(cards.at(1), const Offset(-65, 0));
    await tester.pumpAndSettle();
    expect(
      find
          .descendant(of: cards.at(0), matching: find.text('Удалить'))
          .hitTestable(),
      findsNothing,
    );
    expect(
      find
          .descendant(of: cards.at(1), matching: find.text('Удалить'))
          .hitTestable(),
      findsOneWidget,
    );
  });

  test('nonempty columns cannot be deleted', () async {
    final repository = LocalTchmRepository();
    final machinist = (await repository.watchMachinists().first).first;
    final column = (await repository.watchColumns().first).firstWhere(
      (item) => item.id == machinist.columnId,
    );
    await expectLater(
      repository.deleteColumn(column, _developer),
      throwsStateError,
    );
    expect(
      (await repository.watchColumns().first).any(
        (item) => item.id == column.id,
      ),
      isTrue,
    );
  });
}
