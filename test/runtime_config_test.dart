import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tchm_app/api_backend.dart';
import 'package:tchm_app/api.dart';
import 'package:tchm_app/main.dart';
import 'package:tchm_app/runtime_config.dart';

void main() {
  testWidgets('default app uses API without initializing Firebase', (tester) async {
    SharedPreferences.setMockInitialValues({});
    expect(RuntimeConfig.demo, isFalse);
    expect(RuntimeConfig.shot, -1);
    expect(TchmApp.useYandexApi, isTrue);
    await tester.pumpWidget(const TchmApp());
    await tester.pumpAndSettle();
    final deps = AppDependencies.of(tester.element(find.byType(LoginScreen)));
    expect(deps.auth, isA<ApiAppAuth>());
    expect(deps.repository, isA<ApiTchmRepository>());
    expect(find.byTooltip('Вход разработчика'), findsNothing);
  });

  testWidgets('API email login remains visible with a cached full lock', (tester) async {
    final repository = LocalTchmRepository();
    await repository.setLock(const AppLock(readsBlocked: true), const AppUser(
      id: 'developer', email: '', displayName: '', role: UserRole.developer,
    ));
    await tester.pumpWidget(AppDependencies(
      repository: repository,
      auth: ApiAppAuth(ApiClient()),
      child: const MaterialApp(home: LoginScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ведутся технические работы'), findsNothing);
    expect(find.text('Войти'), findsOneWidget);
  });

}
