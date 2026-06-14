import 'package:flutter_test/flutter_test.dart';
import 'package:tchm_app/main.dart';

void main() {
  testWidgets('shows demo login screen', (tester) async {
    await tester.pumpWidget(const TchmApp(firebaseReady: false));
    await tester.pump();

    expect(find.text('ТЧМ'), findsWidgets);
    expect(find.text('Войти как инструктор'), findsOneWidget);
    expect(find.text('Войти как гость'), findsOneWidget);
    expect(find.text('Пароль доступа'), findsNothing);

    await tester.tap(find.text('Войти как гость'));
    await tester.pump();

    expect(find.text('Пароль доступа'), findsOneWidget);
    expect(find.text('Табельный номер'), findsNothing);

    await tester.tap(find.byTooltip('Назад'));
    await tester.pump();
    await tester.tap(find.text('Войти как инструктор'));
    await tester.pump();

    expect(find.text('Табельный номер'), findsOneWidget);
    expect(find.text('Пароль доступа'), findsOneWidget);
  });
}
