import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tchm_app/main.dart';

void main() {
  for (final screen in [const Size(440, 956), const Size(375, 667)]) {
    testWidgets('column editor stays usable with keyboard at $screen', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = screen;
      final safeTop = screen.height < 700 ? 20.0 : 59.0;
      final keyboardHeight = screen.height < 700 ? 291.0 : 346.0;
      tester.view.padding = FakeViewPadding(top: safeTop, bottom: 34);
      addTearDown(tester.view.reset);

      final repository = LocalTchmRepository();
      final column = (await repository.watchColumns().first).first;
      await tester.pumpWidget(
        AppDependencies(
          repository: repository,
          auth: DemoAppAuth(),
          firebaseReady: false,
          child: MaterialApp(
            theme: buildAppTheme().copyWith(platform: TargetPlatform.iOS),
            home: const HomeScreen(
              user: AppUser(
                id: 'developer-test',
                email: '',
                displayName: 'Разработчик',
                role: UserRole.developer,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(ValueKey('column-edit-${column.id}')),
        Offset(-screen.width * 0.7, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Изменить').hitTestable());
      await tester.pumpAndSettle();

      final dialog = find.byType(Dialog);
      final fields = find.descendant(
        of: dialog,
        matching: find.byType(TextField),
      );
      expect(fields, findsNWidgets(2));
      await tester.tap(fields.first);
      tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
      tester.view.padding = FakeViewPadding(top: safeTop);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final keyboardTop = screen.height - keyboardHeight;
      final scrollView = find.descendant(
        of: dialog,
        matching: find.byType(SingleChildScrollView),
      );
      // A field must fit inside the visible scrolling area, not just remain
      // mounted behind the dialog's clip when the keyboard opens.
      expect(
        tester.getSize(scrollView).height,
        greaterThanOrEqualTo(tester.getSize(fields.first).height),
      );
      for (var i = 0; i < 2; i++) {
        await tester.showKeyboard(fields.at(i));
        await tester.pumpAndSettle();
        await tester.ensureVisible(fields.at(i));
        await tester.pumpAndSettle();
        final fieldRect = tester.getRect(fields.at(i));
        final viewport = tester.getRect(scrollView);
        expect(fieldRect.top, greaterThanOrEqualTo(viewport.top - 1));
        expect(fieldRect.bottom, lessThanOrEqualTo(viewport.bottom + 1));
        expect(fieldRect.bottom, lessThan(keyboardTop));
        expect(fields.at(i).hitTestable(), findsOneWidget);
        await tester.enterText(fields.at(i), i == 0 ? 'Петров П.П.' : '1234');
      }
      for (final label in ['Отмена', 'Сохранить']) {
        final button = find.widgetWithText(
          label == 'Отмена' ? OutlinedButton : FilledButton,
          label,
        );
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.getRect(button).bottom, lessThan(keyboardTop));
      }
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(tester.takeException(), isNull);
      final saved = (await repository.watchColumns().first).firstWhere(
        (item) => item.id == column.id,
      );
      expect(saved.tchmName, 'Петров П.П.');
      expect(saved.tchmPersonnelNumber, '1234');
    });
  }
}
