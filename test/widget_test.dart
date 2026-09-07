import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tchm_app/depots.dart';
import 'package:tchm_app/invite_codes.dart';
import 'package:tchm_app/main.dart';

void main() {
  test('calculates work experience with the Russian year declension', () {
    final today = DateTime(2026, 8, 25);

    expect(
      machinistExperienceLabel('25.08.2025', onDate: today),
      'Стаж: 1 год',
    );
    expect(
      machinistExperienceLabel('25.08.2024', onDate: today),
      'Стаж: 2 года',
    );
    expect(
      machinistExperienceLabel('25.08.2021', onDate: today),
      'Стаж: 5 лет',
    );
    expect(
      machinistExperienceLabel('25.08.2015', onDate: today),
      'Стаж: 11 лет',
    );
    expect(
      machinistExperienceLabel('25.05.2024', onDate: today),
      'Стаж: 2 года 3 месяца',
    );
    expect(
      machinistExperienceLabel('26.08.2025', onDate: today),
      'Стаж: 11 месяцев',
    );
    expect(machinistExperienceLabel('26.08.2026', onDate: today), isNull);
  });

  testWidgets('shows email login and opens registration', (tester) async {
    await tester.pumpWidget(_demoApp());
    await tester.pump();

    expect(find.text('ТЧМ · НОРМАТИВЫ · МАШИНИСТЫ'), findsOneWidget);
    expect(find.text('Почта'), findsOneWidget);
    expect(find.text('Пароль'), findsOneWidget);
    expect(find.text('Забыли пароль?'), findsOneWidget);

    await tester.ensureVisible(find.text('Зарегистрироваться'));
    await tester.pump();
    await tester.tap(find.text('Зарегистрироваться'));
    await tester.pumpAndSettle();

    expect(find.text('Регистрация'), findsOneWidget);
    expect(find.text('Кем регистрируетесь'), findsOneWidget);
    expect(find.text('ТЧМ'), findsOneWidget);
    expect(find.text('Гость'), findsOneWidget);
    expect(find.text('Депо'), findsOneWidget);
    expect(find.text('Фамилия И.О.'), findsOneWidget);
    expect(find.text('Табельный номер'), findsOneWidget);
    expect(find.text('Повторите пароль'), findsOneWidget);
    expect(find.text('Ключ'), findsOneWidget);
    expect(
      find.textContaining('Ключ выдаёт руководитель подразделения'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();

    expect(find.text('Вход'), findsOneWidget);
  });

  testWidgets('registration lists Moscow depots', (tester) async {
    await tester.pumpWidget(_demoApp());
    await tester.pump();

    await tester.ensureVisible(find.text('Зарегистрироваться'));
    await tester.pump();
    await tester.tap(find.text('Зарегистрироваться'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Выберите депо'));
    await tester.pumpAndSettle();

    // В списке 25 штатов по алфавиту; на экране помещается только начало —
    // полноту справочника проверяет отдельный тест ниже.
    expect(find.text('Аминьевское'), findsWidgets);
    expect(find.text('Варшавское — БЛ'), findsWidgets);

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Название, номер ТЧ или линия',
      ),
      'Варшавское',
    );
    await tester.pumpAndSettle();
    expect(find.text('Варшавское — СТЛ'), findsOneWidget);
    expect(find.text('Варшавское — БЛ'), findsOneWidget);
    await tester.tap(find.text('Варшавское — БЛ'));
    await tester.pumpAndSettle();
    expect(find.text('Варшавское — БЛ'), findsOneWidget);
    expect(find.text('Варшавское — СТЛ'), findsNothing);
  });

  testWidgets('guest registration hides the personnel number', (tester) async {
    await tester.pumpWidget(_demoApp());
    await tester.pump();

    await tester.ensureVisible(find.text('Зарегистрироваться'));
    await tester.pump();
    await tester.tap(find.text('Зарегистрироваться'));
    await tester.pumpAndSettle();

    expect(find.text('Табельный номер'), findsOneWidget);

    await tester.tap(find.text('Гость'));
    await tester.pumpAndSettle();

    expect(find.text('Табельный номер'), findsNothing);
    expect(find.text('Гость только просматривает данные.'), findsOneWidget);
  });

  test('created column is signed by its author', () async {
    final repository = LocalTchmRepository();
    const user = AppUser(
      id: 'u1',
      email: 'tchm@example.com',
      displayName: 'Королев М.А.',
      role: UserRole.tchm,
      depotId: 'tch16',
      personnelNumber: '1145',
    );

    await repository.createColumn(number: 42, user: user);
    final columns = await repository.watchColumns().first;
    final created = columns.firstWhere((column) => column.number == 42);

    // Подпись ТЧМ берётся из профиля создателя — спрашивать её незачем.
    expect(created.tchmName, 'Королев М.А.');
    expect(created.tchmPersonnelNumber, '1145');
    expect(created.depotId, 'tch16');
    expect(created.title, 'Колонна №42');

    // Второй раз тот же номер завести нельзя.
    await expectLater(
      repository.createColumn(number: 42, user: user),
      throwsStateError,
    );
  });

  test('invite code normalisation accepts sloppy input', () {
    expect(normalizeInviteCode('tch16 tcgc rqzn ghkg'), 'TCH16-TCGC-RQZN-GHKG');
    expect(normalizeInviteCode('TCH16-TCGC-RQZN-GHKG'), 'TCH16-TCGC-RQZN-GHKG');
  });

  test('machinist keeps its depot through edits', () {
    final machinist = Machinist(
      id: 'm1',
      depotId: 'tch16',
      columnId: 'column_3',
      columnNumber: 3,
      fullName: 'Иванов И.И.',
      classRank: '2',
      workStart: '01.01.2020',
      ticket: '',
      kip: '',
      tra: '',
      atz: '',
      coupling: '',
      vn: '',
      tchmName: '',
      notes: '',
      kipExtensionMonths: 0,
      kipExtensionOrder: '',
      updatedAt: DateTime(2026, 8, 28),
      updatedBy: 'тест',
    );

    // Депо обязано попадать в запись и переживать правку: без него документ
    // выпадет из выборки своего депо и станет невидимым.
    expect(machinist.toMap()['depotId'], 'tch16');
    expect(machinist.copyWith(fullName: 'Петров П.П.').depotId, 'tch16');

    final restored = Machinist.fromMap('m1', {
      'depotId': 'tch16',
      'columnId': 'column_3',
      'fullName': 'Иванов И.И.',
    });
    expect(restored.depotId, 'tch16');
  });

  test('column carries its depot', () {
    const column = ColumnGroup(
      id: 'column_1',
      depotId: 'tch16',
      number: 1,
      title: 'Колонна №1',
      instructorName: '',
      tchmName: '',
      tchmPersonnelNumber: '',
    );
    expect(column.toMap()['depotId'], 'tch16');
    expect(column.copyWith(title: 'Другое').depotId, 'tch16');
  });

  test('depot directory matches the metro roster', () {
    final ids = MoscowDepots.all.map((depot) => depot.id).toSet();
    expect(ids.length, MoscowDepots.all.length);
    expect(MoscowDepots.byId('нет такого'), isNull);

    // Позиции, на которых я ошибался при первой сборке справочника.
    expect(MoscowDepots.byId('tch11')?.name, 'Выхино');
    expect(MoscowDepots.byId('tch14')?.name, 'Владыкино');
    expect(MoscowDepots.byId('tch15')?.name, 'Печатники');
    expect(MoscowDepots.byId('tch17')?.name, 'Южное');

    // Линия должна быть у каждого действующего депо: пустая строка в
    // списке читается как недоделка.
    expect(MoscowDepots.all.where((depot) => depot.line.isEmpty), isEmpty);
    expect(MoscowDepots.byId('tch21')?.name, 'Нижегородское');
    expect(MoscowDepots.byId('tch22')?.name, 'Аминьевское');
    expect(MoscowDepots.byId('tch23')?.name, 'Столбово');
    expect(MoscowDepots.byId('novorizhskoe')?.name, 'Ильинское');
    expect(MoscowDepots.byId('novorizhskoe')?.number, 24);

    expect(MoscowDepots.titleFor('tch16'), 'Митино');

    // Братеево — это то же ТЧ-17, что и «Южное», отдельной записи быть не
    // должно: иначе люди одного депо регистрировались бы в разные.
    expect(MoscowDepots.byId('brateevo'), isNull);
    final repeatedNumbers = {
      for (final depot in MoscowDepots.all)
        if (MoscowDepots.all.where((d) => d.number == depot.number).length > 1)
          depot.number,
    };
    expect(repeatedNumbers, {8}, reason: 'ТЧ-8 имеет два отдельных штата');
  });

  test('Varshavskoye lines have separate staff scopes', () {
    final stl = MoscowDepots.byId('tch08')!;
    final bl = MoscowDepots.byId('tch08_bl')!;
    expect(stl.number, bl.number);
    expect(stl.id, isNot(bl.id));
    expect(stl.title, 'Варшавское — СТЛ');
    expect(bl.title, 'Варшавское — БЛ');
    expect(stl.line, 'Серпуховско-Тимирязевская');
    expect(bl.line, 'Бутовская');
    expect(stl.searchText, contains('стл'));
    expect(bl.searchText, contains('бл'));
    expect(MoscowDepots.all.where((d) => d.number == 8), hasLength(2));
  });

  testWidgets('opens machinist editor only from the left-swipe action', (
    tester,
  ) async {
    const column = ColumnGroup(
      id: 'column-1',
      number: 1,
      title: 'Колонна №1',
      instructorName: '',
      tchmName: '',
      tchmPersonnelNumber: '',
    );
    final machinist = Machinist(
      id: 'machinist-1',
      columnId: column.id,
      columnNumber: column.number,
      fullName: 'Иванов Иван Иванович',
      classRank: '',
      workStart: '',
      ticket: '',
      kip: '',
      tra: '',
      atz: '',
      coupling: '',
      vn: '',
      tchmName: '',
      notes: '',
      kipExtensionMonths: 0,
      kipExtensionOrder: '',
      updatedAt: DateTime(2026),
      updatedBy: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: MachinistCard(
              user: const AppUser(
                id: 'admin',
                email: '',
                displayName: 'Администратор',
                role: UserRole.admin,
              ),
              machinist: machinist,
              columns: const [column],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text(machinist.fullName));
    await tester.pumpAndSettle();
    expect(find.byType(MachinistEditorScreen), findsNothing);

    await tester.drag(find.byType(MachinistCard), const Offset(-160, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Редактировать'));
    await tester.pumpAndSettle();

    expect(find.byType(MachinistEditorScreen), findsOneWidget);
    expect(find.text('КИП на год по приказу'), findsOneWidget);
    expect(find.text('Приказ по КИП'), findsNothing);
  });

  testWidgets('closes the previous edit action when another card is swiped', (
    tester,
  ) async {
    const column = ColumnGroup(
      id: 'column-1',
      number: 1,
      title: 'Колонна №1',
      instructorName: '',
      tchmName: '',
      tchmPersonnelNumber: '',
    );
    Machinist machinist(String id, String fullName) => Machinist(
      id: id,
      columnId: column.id,
      columnNumber: column.number,
      fullName: fullName,
      classRank: '',
      workStart: '',
      ticket: '',
      kip: '',
      tra: '',
      atz: '',
      coupling: '',
      vn: '',
      tchmName: '',
      notes: '',
      kipExtensionMonths: 0,
      kipExtensionOrder: '',
      updatedAt: DateTime(2026),
      updatedBy: '',
    );
    const user = AppUser(
      id: 'admin',
      email: '',
      displayName: 'Администратор',
      role: UserRole.admin,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              MachinistCard(
                user: user,
                machinist: machinist('machinist-1', 'Иванов И.И.'),
                columns: const [column],
              ),
              MachinistCard(
                user: user,
                machinist: machinist('machinist-2', 'Петров П.П.'),
                columns: const [column],
              ),
            ],
          ),
        ),
      ),
    );

    final cards = find.byType(MachinistCard);
    await tester.drag(cards.at(0), const Offset(-160, 0));
    await tester.pumpAndSettle();
    await tester.drag(cards.at(1), const Offset(-160, 0));
    await tester.pumpAndSettle();

    final firstCardTransform = tester.widget<Transform>(
      find.descendant(of: cards.at(0), matching: find.byType(Transform)),
    );
    final secondCardTransform = tester.widget<Transform>(
      find.descendant(of: cards.at(1), matching: find.byType(Transform)),
    );
    expect(firstCardTransform.transform.getTranslation().x, 0);
    expect(secondCardTransform.transform.getTranslation().x, lessThan(0));
  });
}

Widget _demoApp() => AppDependencies(
  repository: LocalTchmRepository(),
  auth: DemoAppAuth(),
  firebaseReady: false,
  child: MaterialApp(theme: buildAppTheme(), home: const AuthGate()),
);
