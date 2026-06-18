import 'dart:async';
import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseReady = AppFirebaseOptions.isConfigured;
  if (firebaseReady) {
    await Firebase.initializeApp(options: AppFirebaseOptions.currentPlatform);
  }
  runApp(TchmApp(firebaseReady: firebaseReady));
}

class TchmApp extends StatelessWidget {
  const TchmApp({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    final repository = (firebaseReady && _shotScreen < 0)
        ? FirebaseTchmRepository(FirebaseFirestore.instance)
        : LocalTchmRepository();
    final auth = firebaseReady
        ? FirebaseAppAuth(FirebaseFirestore.instance)
        : DemoAppAuth();

    return AppDependencies(
      repository: repository,
      auth: auth,
      firebaseReady: firebaseReady,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'ТЧМ',
        theme: buildAppTheme(),
        scrollBehavior: const AppScrollBehavior(),
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: _shotScreen < 0
            ? const AuthGate()
            : _ShotHarness(which: _shotScreen),
      ),
    );
  }
}

/// Одинаковая прокрутка на iOS и Android: пружинящий отскок
/// вместо растягивания списка на Android.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

/// Фирменная палитра. Все цвета приложения берутся отсюда,
/// чтобы интерфейс выглядел одинаково на iOS и Android.
abstract final class AppPalette {
  static const seed = Color(0xFF1B5FA8);
  static const deep = Color(0xFF0C2C57);
  static const deepLight = Color(0xFF14467F);
  static const accent = Color(0xFF2F6FBF);
  static const surfaceTint = Color(0xFFEAF1FB);
  static const background = Color(0xFFF4F7FC);
  static const border = Color(0xFFDCE5F1);
  static const textPrimary = Color(0xFF142133);
  static const textSecondary = Color(0xFF59667A);
  static const danger = Color(0xFFD64545);
  static const dangerTint = Color(0xFFFBE9E9);
  static const warning = Color(0xFFC9781A);
  static const warningTint = Color(0xFFFBEFDB);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppPalette.seed,
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppPalette.background,
    // Один и тот же переход между экранами на обеих платформах.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
      },
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppPalette.deep,
      foregroundColor: Colors.white,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: AppPalette.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppPalette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppPalette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppPalette.accent, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
      prefixIconColor: AppPalette.textSecondary,
      labelStyle: const TextStyle(color: AppPalette.textSecondary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppPalette.seed,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppPalette.deep,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppPalette.border, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppPalette.deep),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppPalette.deep,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppPalette.surfaceTint,
      side: BorderSide.none,
      labelStyle: const TextStyle(
        color: AppPalette.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dividerTheme: const DividerThemeData(
      color: AppPalette.border,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppPalette.deep,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppPalette.textSecondary,
      textColor: AppPalette.textPrimary,
    ),
  );
}

class AppDependencies extends InheritedWidget {
  const AppDependencies({
    super.key,
    required this.repository,
    required this.auth,
    required this.firebaseReady,
    required super.child,
  });

  final TchmRepository repository;
  final AppAuth auth;
  final bool firebaseReady;

  static AppDependencies of(BuildContext context) {
    final deps = context.dependOnInheritedWidgetOfExactType<AppDependencies>();
    assert(deps != null, 'AppDependencies not found');
    return deps!;
  }

  @override
  bool updateShouldNotify(AppDependencies oldWidget) {
    return repository != oldWidget.repository ||
        auth != oldWidget.auth ||
        firebaseReady != oldWidget.firebaseReady;
  }
}

enum UserRole { viewer, instructor, tchm, operator, admin, developer }

extension UserRoleLabels on UserRole {
  String get title {
    return switch (this) {
      UserRole.viewer => 'Просмотр',
      UserRole.instructor => 'Инструктор',
      UserRole.tchm => 'ТЧМ',
      UserRole.operator => 'Оператор',
      UserRole.admin => 'Администратор',
      UserRole.developer => 'Разработчик',
    };
  }

  String get key => name;

  bool get canEditAny {
    return this == UserRole.admin ||
        this == UserRole.tchm ||
        this == UserRole.operator ||
        this == UserRole.developer;
  }

  bool get isDeveloper => this == UserRole.developer;
}

UserRole roleFromString(Object? value) {
  return UserRole.values.firstWhere(
    (role) => role.key == value,
    orElse: () => UserRole.viewer,
  );
}

const allowedTchmProfiles = <String, String>{
  '1145': 'Королев М.А.',
  '488': 'Мойсей С.В.',
  '462': 'Кузнецов А.Л.',
  '130': 'Булыгин В.В.',
  '1004': 'Баканов А.А.',
  '384': 'Гаврик С.А.',
  '502': 'Павлов М.А.',
  '322': 'Никифоров А.В.',
  '392': 'Двойцын Н.С.',
  '628': 'Симонов С.В.',
  '342': 'Акиньшин П.В.',
  '169': 'Рынкис А.В.',
  '1134': 'Попов Д.П.',
  '1005': 'Лихачев А.Е.',
  '532': 'Савинкин А.В.',
  '344': 'Алексеев А.В.',
  '1576': 'Логинов Д.Н.',
  '150': 'Зудин И.В.',
  '742': 'Федосков А.И.',
  '1040': 'Нарядчиков К.А.',
  '2680': 'Агапитов В.А.',
  '1984': 'Покрышкин А.Н.',
  '966': 'Архипов А.С.',
  '941': 'Серяпин С.И.',
  '1671': 'Серков Н.А.',
};

// Табельный номер разработчика. Вход под ним даёт роль «Разработчик»
// с полными правами на изменение и редактирование всего.
const developerPersonnelNumber = '1916';

// Отдельный пароль для входа разработчика (вместо общего пароля доступа).
const developerPassword = 'Vladislav';

bool isDeveloperPersonnelNumber(String number) {
  return number.trim() == developerPersonnelNumber;
}

bool isDeveloperPasswordValid(String value) {
  return value.trim().toLowerCase() == developerPassword.toLowerCase();
}

String? tchmNameForPersonnelNumber(String number) {
  if (isDeveloperPersonnelNumber(number)) return 'Разработчик';
  return allowedTchmProfiles[number.trim()];
}

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    this.personnelNumber,
    this.assignedColumnId,
  });

  final String id;
  final String email;
  final String displayName;
  final UserRole role;
  final String? personnelNumber;
  final String? assignedColumnId;

  bool canAddToColumn(String columnId) {
    return role.canEditAny ||
        (role == UserRole.instructor && assignedColumnId == columnId);
  }

  bool canEditMachinist(Machinist machinist) {
    return canAddToColumn(machinist.columnId);
  }

  Map<String, Object?> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'role': role.key,
      'personnelNumber': personnelNumber,
      'assignedColumnId': assignedColumnId,
    };
  }

  static AppUser fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      id: id,
      email: map['email'] as String? ?? '',
      displayName: map['displayName'] as String? ?? 'Пользователь',
      role: roleFromString(map['role']),
      personnelNumber: map['personnelNumber'] as String?,
      assignedColumnId: map['assignedColumnId'] as String?,
    );
  }
}

class ColumnGroup {
  const ColumnGroup({
    required this.id,
    required this.number,
    required this.title,
    required this.instructorName,
    required this.tchmName,
    required this.tchmPersonnelNumber,
  });

  final String id;
  final int number;
  final String title;
  final String instructorName;
  final String tchmName;
  final String tchmPersonnelNumber;

  ColumnGroup copyWith({
    String? title,
    String? instructorName,
    String? tchmName,
    String? tchmPersonnelNumber,
  }) {
    return ColumnGroup(
      id: id,
      number: number,
      title: title ?? this.title,
      instructorName: instructorName ?? this.instructorName,
      tchmName: tchmName ?? this.tchmName,
      tchmPersonnelNumber: tchmPersonnelNumber ?? this.tchmPersonnelNumber,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'number': number,
      'title': title,
      'instructorName': instructorName,
      'tchmName': tchmName,
      'tchmPersonnelNumber': tchmPersonnelNumber,
    };
  }

  static ColumnGroup fromMap(String id, Map<String, dynamic> map) {
    return ColumnGroup(
      id: id,
      number: (map['number'] as num?)?.toInt() ?? 0,
      title: map['title'] as String? ?? 'Колонна',
      instructorName: map['instructorName'] as String? ?? '',
      tchmName: map['tchmName'] as String? ?? '',
      tchmPersonnelNumber: map['tchmPersonnelNumber'] as String? ?? '',
    );
  }
}

class Machinist {
  const Machinist({
    required this.id,
    required this.columnId,
    required this.columnNumber,
    required this.fullName,
    required this.classRank,
    required this.workStart,
    required this.ticket,
    required this.kip,
    required this.tra,
    required this.atz,
    required this.coupling,
    required this.vn,
    required this.tchmName,
    required this.notes,
    required this.kipExtensionMonths,
    required this.kipExtensionOrder,
    required this.updatedAt,
    required this.updatedBy,
  });

  final String id;
  final String columnId;
  final int columnNumber;
  final String fullName;
  final String classRank;
  final String workStart;
  final String ticket;
  final String kip;
  final String tra;
  final String atz;
  final String coupling;
  final String vn;
  final String tchmName;
  final String notes;
  final int kipExtensionMonths;
  final String kipExtensionOrder;
  final DateTime updatedAt;
  final String updatedBy;

  Machinist copyWith({
    String? id,
    String? columnId,
    int? columnNumber,
    String? fullName,
    String? classRank,
    String? workStart,
    String? ticket,
    String? kip,
    String? tra,
    String? atz,
    String? coupling,
    String? vn,
    String? tchmName,
    String? notes,
    int? kipExtensionMonths,
    String? kipExtensionOrder,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return Machinist(
      id: id ?? this.id,
      columnId: columnId ?? this.columnId,
      columnNumber: columnNumber ?? this.columnNumber,
      fullName: fullName ?? this.fullName,
      classRank: classRank ?? this.classRank,
      workStart: workStart ?? this.workStart,
      ticket: ticket ?? this.ticket,
      kip: kip ?? this.kip,
      tra: tra ?? this.tra,
      atz: atz ?? this.atz,
      coupling: coupling ?? this.coupling,
      vn: vn ?? this.vn,
      tchmName: tchmName ?? this.tchmName,
      notes: notes ?? this.notes,
      kipExtensionMonths: kipExtensionMonths ?? this.kipExtensionMonths,
      kipExtensionOrder: kipExtensionOrder ?? this.kipExtensionOrder,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'columnId': columnId,
      'columnNumber': columnNumber,
      'fullName': fullName,
      'classRank': classRank,
      'workStart': workStart,
      'ticket': ticket,
      'kip': kip,
      'tra': tra,
      'atz': atz,
      'coupling': coupling,
      'vn': vn,
      'tchmName': tchmName,
      'notes': notes,
      'kipExtensionMonths': kipExtensionMonths,
      'kipExtensionOrder': kipExtensionOrder,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'updatedBy': updatedBy,
      'searchName': fullName.toLowerCase(),
    };
  }

  static Machinist fromMap(String id, Map<String, dynamic> map) {
    return Machinist(
      id: id,
      columnId: map['columnId'] as String? ?? '',
      columnNumber: (map['columnNumber'] as num?)?.toInt() ?? 0,
      fullName: map['fullName'] as String? ?? '',
      classRank: map['classRank']?.toString() ?? '',
      workStart: map['workStart']?.toString() ?? '',
      ticket: map['ticket']?.toString() ?? '',
      kip: map['kip']?.toString() ?? '',
      tra: map['tra']?.toString() ?? '',
      atz: map['atz']?.toString() ?? '',
      coupling: map['coupling']?.toString() ?? '',
      vn: map['vn']?.toString() ?? '',
      tchmName: map['tchmName']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
      kipExtensionMonths: (map['kipExtensionMonths'] as num?)?.toInt() ?? 0,
      kipExtensionOrder: map['kipExtensionOrder']?.toString() ?? '',
      updatedAt: _dateFromValue(map['updatedAt']),
      updatedBy: map['updatedBy']?.toString() ?? '',
    );
  }
}

DateTime _dateFromValue(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.fromMillisecondsSinceEpoch(0);
}

enum MachinistClass { none, third, second, first }

extension MachinistClassX on MachinistClass {
  /// Значение для хранения в Firestore (совместимо со старыми данными).
  String get rank => switch (this) {
    MachinistClass.none => '',
    MachinistClass.third => '3',
    MachinistClass.second => '2',
    MachinistClass.first => '1',
  };

  String get label => switch (this) {
    MachinistClass.none => 'Без класса (б/к)',
    MachinistClass.third => '3 класс',
    MachinistClass.second => '2 класс',
    MachinistClass.first => '1 класс',
  };
}

MachinistClass machinistClassFromRank(String rank) {
  switch (rank.trim()) {
    case '1':
      return MachinistClass.first;
    case '2':
      return MachinistClass.second;
    case '3':
      return MachinistClass.third;
    default:
      return MachinistClass.none;
  }
}

/// За сколько дней до срока показывать статус «скоро».
const int kCheckSoonThresholdDays = 21;

enum CheckDiscipline { kip, tra, atz, coupling }

extension CheckDisciplineX on CheckDiscipline {
  String get label => switch (this) {
    CheckDiscipline.kip => 'КИП',
    CheckDiscipline.tra => 'ТРА',
    CheckDiscipline.atz => 'АТЗ',
    CheckDiscipline.coupling => 'Сцеп',
  };

  String dateOf(Machinist machinist) => switch (this) {
    CheckDiscipline.kip => machinist.kip,
    CheckDiscipline.tra => machinist.tra,
    CheckDiscipline.atz => machinist.atz,
    CheckDiscipline.coupling => machinist.coupling,
  };

  /// Периодичность в месяцах по классу машиниста.
  int intervalMonths(MachinistClass cls) => switch (this) {
    CheckDiscipline.kip => switch (cls) {
      MachinistClass.none => 2,
      MachinistClass.third => 3,
      MachinistClass.second => 4,
      MachinistClass.first => 4,
    },
    CheckDiscipline.tra => 3,
    CheckDiscipline.atz => cls == MachinistClass.none ? 2 : 3,
    CheckDiscipline.coupling => switch (cls) {
      MachinistClass.none => 12,
      MachinistClass.third => 12,
      MachinistClass.second => 18,
      MachinistClass.first => 18,
    },
  };
}

enum CheckStatus { ok, soon, overdue, noData }

int _statusSeverity(CheckStatus status) => switch (status) {
  CheckStatus.overdue => 3,
  CheckStatus.soon => 2,
  // «Нет данных» (пустая/нераспознанная дата) не считается тревогой:
  // не попадает в счётчики и индикаторы, пока дату не проставят.
  CheckStatus.noData => 0,
  CheckStatus.ok => 0,
};

CheckStatus _worseStatus(CheckStatus a, CheckStatus b) =>
    _statusSeverity(a) >= _statusSeverity(b) ? a : b;

class CheckResult {
  const CheckResult({
    required this.discipline,
    required this.status,
    this.nextDue,
    this.daysLeft,
  });

  final CheckDiscipline discipline;
  final CheckStatus status;
  final DateTime? nextDue;
  final int? daysLeft;
}

DateTime _addMonths(DateTime date, int months) {
  final total = date.month - 1 + months;
  final year = date.year + total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateUtils.getDaysInMonth(year, month);
  final day = date.day <= lastDay ? date.day : lastDay;
  return DateTime(year, month, day);
}

CheckResult evaluateCheck(
  Machinist machinist,
  CheckDiscipline discipline, {
  DateTime? now,
}) {
  final last = _parseDate(discipline.dateOf(machinist));
  if (last == null) {
    return CheckResult(discipline: discipline, status: CheckStatus.noData);
  }
  final cls = machinistClassFromRank(machinist.classRank);
  final extensionMonths = discipline == CheckDiscipline.kip
      ? machinist.kipExtensionMonths
      : 0;
  final due = _addMonths(
    last,
    discipline.intervalMonths(cls) + extensionMonths,
  );
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final daysLeft = due.difference(today).inDays;
  final CheckStatus status;
  if (daysLeft < 0) {
    status = CheckStatus.overdue;
  } else if (daysLeft <= kCheckSoonThresholdDays) {
    status = CheckStatus.soon;
  } else {
    status = CheckStatus.ok;
  }
  return CheckResult(
    discipline: discipline,
    status: status,
    nextDue: due,
    daysLeft: daysLeft,
  );
}

List<CheckResult> evaluateAllChecks(Machinist machinist, {DateTime? now}) {
  return [
    for (final discipline in CheckDiscipline.values)
      evaluateCheck(machinist, discipline, now: now),
  ];
}

CheckStatus machinistOverallStatus(Machinist machinist, {DateTime? now}) {
  var worst = CheckStatus.ok;
  for (final result in evaluateAllChecks(machinist, now: now)) {
    worst = _worseStatus(worst, result.status);
  }
  return worst;
}

bool machinistNeedsAttention(Machinist machinist, {DateTime? now}) =>
    machinistOverallStatus(machinist, now: now) != CheckStatus.ok;

Color checkStatusColor(CheckStatus status) => switch (status) {
  CheckStatus.overdue => AppPalette.danger,
  CheckStatus.soon => AppPalette.warning,
  CheckStatus.noData => AppPalette.textSecondary,
  CheckStatus.ok => AppPalette.textSecondary,
};

IconData? checkStatusIcon(CheckStatus status) => switch (status) {
  CheckStatus.overdue => Icons.error_outline,
  CheckStatus.soon => Icons.warning_amber_rounded,
  CheckStatus.noData => Icons.help_outline,
  CheckStatus.ok => null,
};

abstract class AppAuth {
  Stream<AppUser?> authStateChanges();

  Future<void> signInAsGuest();

  Future<void> signInAsTchm(String personnelNumber);

  Future<void> signOut();
}

class FirebaseAppAuth implements AppAuth {
  FirebaseAppAuth(this.firestore);

  final FirebaseFirestore firestore;

  @override
  Stream<AppUser?> authStateChanges() {
    // asyncExpand здесь не подходит: ref.snapshots() никогда не завершается,
    // поэтому после выхода или ошибки чтения профиля новые события входа
    // не доходили до AuthGate до перезапуска приложения.
    late final StreamController<AppUser?> controller;
    StreamSubscription<fb_auth.User?>? authSub;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? profileSub;

    controller = StreamController<AppUser?>(
      onListen: () {
        authSub = fb_auth.FirebaseAuth.instance.authStateChanges().listen((
          user,
        ) {
          profileSub?.cancel();
          profileSub = null;
          if (user == null) {
            controller.add(null);
            return;
          }
          final ref = firestore.collection('users').doc(user.uid);
          profileSub = ref.snapshots().listen(
            (snapshot) {
              final data = snapshot.data();
              if (data == null) {
                // Документ профиля ещё не записан методом входа — отдаём
                // временный профиль, но не пишем его в Firestore, чтобы
                // не затереть роль, записываемую signInAsTchm/signInAsGuest.
                controller.add(
                  AppUser(
                    id: user.uid,
                    email: user.email ?? '',
                    displayName:
                        user.displayName ?? user.email ?? 'Пользователь',
                    role: UserRole.viewer,
                  ),
                );
                return;
              }
              controller.add(AppUser.fromMap(user.uid, data));
            },
            onError: (Object _) {
              // Ошибка чтения профиля (например, после выхода) не должна
              // останавливать поток авторизации.
            },
          );
        });
      },
      onCancel: () {
        profileSub?.cancel();
        authSub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> signInAsGuest() async {
    final user = await _anonymousUser();
    await firestore
        .collection('users')
        .doc(user.uid)
        .set(
          AppUser(
            id: user.uid,
            email: user.email ?? '',
            displayName: 'Гость',
            role: UserRole.viewer,
          ).toMap(),
          SetOptions(merge: true),
        );
  }

  @override
  Future<void> signInAsTchm(String personnelNumber) async {
    final cleanNumber = personnelNumber.trim();
    if (cleanNumber.isEmpty) {
      throw StateError('Введите табельный номер.');
    }
    final tchmName = tchmNameForPersonnelNumber(cleanNumber);
    if (tchmName == null) {
      throw StateError('Табельный номер не найден в списке ТЧМ.');
    }
    final user = await _anonymousUser();
    await firestore
        .collection('users')
        .doc(user.uid)
        .set(
          AppUser(
            id: user.uid,
            email: user.email ?? '',
            displayName: tchmName,
            role: isDeveloperPersonnelNumber(cleanNumber)
                ? UserRole.developer
                : UserRole.tchm,
            personnelNumber: cleanNumber,
          ).toMap(),
          SetOptions(merge: true),
        );
    await _ensureDefaultColumns();
  }

  Future<void> _ensureDefaultColumns() async {
    final batch = firestore.batch();
    for (final column in SeedData.columns) {
      batch.set(
        firestore.collection('columns').doc(column.id),
        column.toMap(),
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<fb_auth.User> _anonymousUser() async {
    final current = fb_auth.FirebaseAuth.instance.currentUser;
    if (current != null) return current;
    final credential = await fb_auth.FirebaseAuth.instance.signInAnonymously();
    final user = credential.user;
    if (user == null) {
      throw StateError('Не удалось выполнить вход.');
    }
    return user;
  }

  @override
  Future<void> signOut() {
    return fb_auth.FirebaseAuth.instance.signOut();
  }
}

class DemoAppAuth implements AppAuth {
  DemoAppAuth() {
    _controller.add(null);
  }

  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _user;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  Future<void> signInAsGuest() async {
    _user = const AppUser(
      id: 'demo-guest',
      email: '',
      displayName: 'Гость',
      role: UserRole.viewer,
    );
    _controller.add(_user);
  }

  @override
  Future<void> signInAsTchm(String personnelNumber) async {
    final cleanNumber = personnelNumber.trim();
    if (cleanNumber.isEmpty) {
      throw StateError('Введите табельный номер.');
    }
    final tchmName = tchmNameForPersonnelNumber(cleanNumber);
    if (tchmName == null) {
      throw StateError('Табельный номер не найден в списке ТЧМ.');
    }
    _user = AppUser(
      id: 'demo-tchm-$cleanNumber',
      email: '',
      displayName: tchmName,
      role: isDeveloperPersonnelNumber(cleanNumber)
          ? UserRole.developer
          : UserRole.tchm,
      personnelNumber: cleanNumber,
    );
    _controller.add(_user);
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }
}

abstract class TchmRepository {
  Stream<List<ColumnGroup>> watchColumns();

  Stream<List<Machinist>> watchMachinists({String? columnId});

  Future<void> ensureDefaultColumns(AppUser user);

  Future<void> seedDefaults(AppUser user);

  Future<void> saveMachinist(Machinist machinist, AppUser user);

  Future<void> deleteMachinist(Machinist machinist, AppUser user);

  Future<void> updateColumn(ColumnGroup column, AppUser user);
}

class FirebaseTchmRepository implements TchmRepository {
  FirebaseTchmRepository(this.firestore);

  final FirebaseFirestore firestore;

  @override
  Stream<List<ColumnGroup>> watchColumns() {
    return firestore.collection('columns').orderBy('number').snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) => ColumnGroup.fromMap(doc.id, doc.data()))
          .toList();
    });
  }

  @override
  Stream<List<Machinist>> watchMachinists({String? columnId}) {
    Query<Map<String, dynamic>> query = firestore.collection('machinists');
    if (columnId != null) {
      query = query.where('columnId', isEqualTo: columnId);
    }
    return query.snapshots().map((snapshot) {
      final items = snapshot.docs.map(
        (doc) => Machinist.fromMap(doc.id, doc.data()),
      );
      final sorted = items.toList()
        ..sort((a, b) {
          final byColumn = a.columnNumber.compareTo(b.columnNumber);
          if (byColumn != 0) return byColumn;
          return a.fullName.compareTo(b.fullName);
        });
      return sorted;
    });
  }

  @override
  Future<void> ensureDefaultColumns(AppUser user) async {
    if (!user.role.canEditAny) return;
    final batch = firestore.batch();
    for (final column in SeedData.columns) {
      batch.set(
        firestore.collection('columns').doc(column.id),
        column.toMap(),
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  @override
  Future<void> seedDefaults(AppUser user) async {
    if (!user.role.canEditAny) {
      throw StateError('Начальное заполнение доступно только ТЧМ/оператору.');
    }
    final batch = firestore.batch();
    for (final column in SeedData.columns) {
      batch.set(
        firestore.collection('columns').doc(column.id),
        column.toMap(),
        SetOptions(merge: true),
      );
    }
    for (final machinist in SeedData.machinists) {
      batch.set(
        firestore.collection('machinists').doc(machinist.id),
        machinist.toMap(),
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  @override
  Future<void> saveMachinist(Machinist machinist, AppUser user) async {
    if (!user.canEditMachinist(machinist)) {
      throw StateError('Нет прав на изменение этой колонны.');
    }
    final ref = machinist.id.isEmpty
        ? firestore.collection('machinists').doc()
        : firestore.collection('machinists').doc(machinist.id);
    await ref.set(
      machinist
          .copyWith(
            id: ref.id,
            updatedAt: DateTime.now(),
            updatedBy: user.displayName,
          )
          .toMap(),
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> deleteMachinist(Machinist machinist, AppUser user) async {
    if (!user.canEditMachinist(machinist)) {
      throw StateError('Нет прав на удаление из этой колонны.');
    }
    await firestore.collection('machinists').doc(machinist.id).delete();
  }

  @override
  Future<void> updateColumn(ColumnGroup column, AppUser user) async {
    if (!user.role.isDeveloper) {
      throw StateError('Изменять колонну может только разработчик.');
    }
    await firestore
        .collection('columns')
        .doc(column.id)
        .set(column.toMap(), SetOptions(merge: true));
  }
}

class LocalTchmRepository implements TchmRepository {
  LocalTchmRepository()
    : _columns = [...SeedData.columns],
      _machinists = [...SeedData.machinists] {
    scheduleMicrotask(_emit);
  }

  final List<ColumnGroup> _columns;
  final List<Machinist> _machinists;
  final _columnsController = StreamController<List<ColumnGroup>>.broadcast();
  final _machinistsController = StreamController<List<Machinist>>.broadcast();

  void _emit() {
    _columnsController.add(List.unmodifiable(_columns));
    _machinists.sort((a, b) {
      final byColumn = a.columnNumber.compareTo(b.columnNumber);
      if (byColumn != 0) return byColumn;
      return a.fullName.compareTo(b.fullName);
    });
    _machinistsController.add(List.unmodifiable(_machinists));
  }

  @override
  Stream<List<ColumnGroup>> watchColumns() async* {
    yield List.unmodifiable(_columns);
    yield* _columnsController.stream;
  }

  @override
  Stream<List<Machinist>> watchMachinists({String? columnId}) async* {
    List<Machinist> filter(List<Machinist> items) {
      if (columnId == null) return items;
      return items.where((item) => item.columnId == columnId).toList();
    }

    yield filter(List.unmodifiable(_machinists));
    yield* _machinistsController.stream.map(filter);
  }

  @override
  Future<void> ensureDefaultColumns(AppUser user) async {
    if (!user.role.canEditAny) return;
    _columns
      ..clear()
      ..addAll(SeedData.columns);
    _emit();
  }

  @override
  Future<void> seedDefaults(AppUser user) async {
    if (!user.role.canEditAny) {
      throw StateError('Начальное заполнение доступно только ТЧМ/оператору.');
    }
    _columns
      ..clear()
      ..addAll(SeedData.columns);
    _machinists
      ..clear()
      ..addAll(SeedData.machinists);
    _emit();
  }

  @override
  Future<void> saveMachinist(Machinist machinist, AppUser user) async {
    if (!user.canEditMachinist(machinist)) {
      throw StateError('Нет прав на изменение этой колонны.');
    }
    final item = machinist.copyWith(
      id: machinist.id.isEmpty
          ? 'local-${DateTime.now().microsecondsSinceEpoch}'
          : machinist.id,
      updatedAt: DateTime.now(),
      updatedBy: user.displayName,
    );
    final index = _machinists.indexWhere((value) => value.id == item.id);
    if (index == -1) {
      _machinists.add(item);
    } else {
      _machinists[index] = item;
    }
    _emit();
  }

  @override
  Future<void> deleteMachinist(Machinist machinist, AppUser user) async {
    if (!user.canEditMachinist(machinist)) {
      throw StateError('Нет прав на удаление из этой колонны.');
    }
    _machinists.removeWhere((value) => value.id == machinist.id);
    _emit();
  }

  @override
  Future<void> updateColumn(ColumnGroup column, AppUser user) async {
    if (!user.role.isDeveloper) {
      throw StateError('Изменять колонну может только разработчик.');
    }
    final index = _columns.indexWhere((value) => value.id == column.id);
    if (index != -1) {
      _columns[index] = column;
    }
    _emit();
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = AppDependencies.of(context);
    return StreamBuilder<AppUser?>(
      stream: deps.auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) return const LoginScreen();
        return HomeScreen(user: user);
      },
    );
  }
}

// ВРЕМЕННО: режим для скриншотов App Store. Запуск:
// flutter run --dart-define=SHOT=0  (0 — Колонны, 1 — Колонна, 2 — Требуют внимания)
const int _shotScreen = int.fromEnvironment('SHOT', defaultValue: -1);

class _ShotHarness extends StatelessWidget {
  const _ShotHarness({required this.which});

  final int which;

  @override
  Widget build(BuildContext context) {
    const user = AppUser(
      id: 'shot',
      email: '',
      displayName: 'Королев М.А.',
      role: UserRole.tchm,
    );
    final repository = AppDependencies.of(context).repository;
    return StreamBuilder<List<ColumnGroup>>(
      stream: repository.watchColumns(),
      builder: (context, columnsSnapshot) {
        final columns = (columnsSnapshot.data?.isNotEmpty ?? false)
            ? columnsSnapshot.data!
            : SeedData.columns;
        if (which == 1) {
          return StreamBuilder<List<Machinist>>(
            stream: repository.watchMachinists(),
            builder: (context, machinistsSnapshot) {
              final all = machinistsSnapshot.data ?? const <Machinist>[];
              final target = columns.firstWhere(
                (column) => all.any(
                  (m) => m.columnId == column.id && machinistNeedsAttention(m),
                ),
                orElse: () => columns.first,
              );
              return ColumnDetailScreen(
                user: user,
                column: target,
                columns: columns,
              );
            },
          );
        }
        if (which == 2) {
          return AttentionScreen(user: user, columns: columns);
        }
        return HomeScreen(user: user);
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _accessPassword = 'ТЧ-16';

  final _personnelNumber = TextEditingController();
  final _password = TextEditingController();
  var _loading = false;
  _LoginMode? _mode;

  @override
  void dispose() {
    _personnelNumber.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _passwordValid() {
    if (_normalizeAccessPassword(_password.text) ==
        _normalizeAccessPassword(_accessPassword)) {
      return true;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Неверный пароль доступа')));
    return false;
  }

  Future<void> _signInAsGuest() async {
    if (!_passwordValid()) return;
    setState(() => _loading = true);
    final deps = AppDependencies.of(context);
    try {
      await deps.auth.signInAsGuest();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось войти: $error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInAsTchm() async {
    final number = _personnelNumber.text.trim();
    if (number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите табельный номер ТЧМ')),
      );
      return;
    }
    if (isDeveloperPersonnelNumber(number)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Вход разработчика — через шестерёнку в углу.'),
        ),
      );
      return;
    }
    if (!_passwordValid()) return;
    setState(() => _loading = true);
    final deps = AppDependencies.of(context);
    try {
      await deps.auth.signInAsTchm(number);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось войти: $error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDeveloperLogin() async {
    if (_loading) return;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeveloperLoginDialog(),
    );
    if (password == null) return;
    await _signInAsDeveloper(password);
  }

  Future<void> _signInAsDeveloper(String password) async {
    if (!isDeveloperPasswordValid(password)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Неверный пароль разработчика')),
      );
      return;
    }
    setState(() => _loading = true);
    final deps = AppDependencies.of(context);
    try {
      await deps.auth.signInAsTchm(developerPersonnelNumber);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось войти: $error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enteredNumber = _personnelNumber.text.trim();
    final foundTchmName = tchmNameForPersonnelNumber(enteredNumber);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppPalette.deep, AppPalette.deepLight, AppPalette.seed],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  tooltip: 'Вход разработчика',
                  onPressed: _loading ? null : _openDeveloperLogin,
                  icon: Icon(
                    Icons.settings_outlined,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.train_outlined,
                            size: 44,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'ТЧМ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Колонны и машинисты',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  if (_mode != null)
                                    IconButton(
                                      tooltip: 'Назад',
                                      onPressed: _loading
                                          ? null
                                          : () => setState(() {
                                              _mode = null;
                                              _password.clear();
                                            }),
                                      icon: const Icon(Icons.arrow_back),
                                    ),
                                  Expanded(
                                    child: Text(
                                      switch (_mode) {
                                        null => 'Выберите способ входа',
                                        _LoginMode.instructor =>
                                          'Вход для инструктора',
                                        _LoginMode.guest =>
                                          'Вход для просмотра',
                                      },
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: AppPalette.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_mode != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _mode == _LoginMode.instructor
                                      ? 'Введите табельный номер и пароль доступа'
                                      : 'Введите пароль доступа',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppPalette.textSecondary,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              if (_mode == null) ...[
                                FilledButton.icon(
                                  onPressed: () => setState(
                                    () => _mode = _LoginMode.instructor,
                                  ),
                                  icon: const Icon(Icons.edit_note_outlined),
                                  label: const Text('Войти как инструктор'),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      setState(() => _mode = _LoginMode.guest),
                                  icon: const Icon(Icons.visibility_outlined),
                                  label: const Text('Войти как гость'),
                                ),
                              ] else ...[
                                if (_mode == _LoginMode.instructor) ...[
                                  _KeyboardTextField(
                                    controller: _personnelNumber,
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Табельный номер',
                                      prefixIcon: Icon(Icons.badge_outlined),
                                    ),
                                    onChanged: (_) => setState(() {}),
                                    onSubmitted: (_) =>
                                        _loading ? null : _signInAsTchm(),
                                  ),
                                  if (enteredNumber.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Icon(
                                          foundTchmName == null
                                              ? Icons.error_outline
                                              : Icons.check_circle_outline,
                                          size: 18,
                                          color: foundTchmName == null
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.error
                                              : AppPalette.accent,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            foundTchmName ??
                                                'Табельный номер не найден',
                                            style: TextStyle(
                                              color: foundTchmName == null
                                                  ? Theme.of(
                                                      context,
                                                    ).colorScheme.error
                                                  : AppPalette.accent,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                ],
                                _KeyboardTextField(
                                  controller: _password,
                                  obscureText: true,
                                  textInputAction: TextInputAction.done,
                                  decoration: const InputDecoration(
                                    labelText: 'Пароль доступа',
                                    prefixIcon: Icon(Icons.lock_outline),
                                  ),
                                  onSubmitted: (_) {
                                    if (_loading) return;
                                    _mode == _LoginMode.guest
                                        ? _signInAsGuest()
                                        : _signInAsTchm();
                                  },
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: _loading
                                      ? null
                                      : (_mode == _LoginMode.guest
                                            ? _signInAsGuest
                                            : _signInAsTchm),
                                  icon: _loading
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Icon(
                                          _mode == _LoginMode.guest
                                              ? Icons.visibility_outlined
                                              : Icons.login,
                                        ),
                                  label: Text(
                                    _mode == _LoginMode.guest
                                        ? 'Войти как гость'
                                        : 'Войти',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _LoginMode { instructor, guest }

String _normalizeAccessPassword(String value) {
  return value
      .trim()
      .toUpperCase()
      .replaceAll('TCH', 'ТЧ')
      .replaceAll('TC', 'ТЧ')
      .replaceAll(' ', '')
      .replaceAll('−', '-')
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('-', '');
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  var _columnsEnsured = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_columnsEnsured || !widget.user.role.canEditAny) return;
    _columnsEnsured = true;
    unawaited(
      AppDependencies.of(context).repository.ensureDefaultColumns(widget.user),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppDependencies.of(context);
    return StreamBuilder<List<ColumnGroup>>(
      stream: deps.repository.watchColumns(),
      builder: (context, columnsSnapshot) {
        final firestoreColumns = columnsSnapshot.data ?? const <ColumnGroup>[];
        if (columnsSnapshot.connectionState == ConnectionState.waiting &&
            firestoreColumns.isEmpty) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final columns = firestoreColumns.isEmpty
            ? SeedData.columns
            : firestoreColumns;
        return StreamBuilder<List<Machinist>>(
          stream: deps.repository.watchMachinists(),
          builder: (context, machinistsSnapshot) {
            final allMachinists =
                machinistsSnapshot.data ?? const <Machinist>[];
            final query = _search.text.trim().toLowerCase();
            final machinists = query.isEmpty
                ? const <Machinist>[]
                : allMachinists
                      .where(
                        (item) => item.fullName.toLowerCase().contains(query),
                      )
                      .toList();

            final attentionTotal = allMachinists
                .where(machinistNeedsAttention)
                .length;

            return Scaffold(
              appBar: AppBar(
                title: const Text('Колонны'),
                actions: [
                  IconButton(
                    tooltip: 'Требуют внимания',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AttentionScreen(
                          user: widget.user,
                          columns: columns,
                        ),
                      ),
                    ),
                    icon: Badge(
                      isLabelVisible: attentionTotal > 0,
                      backgroundColor: AppPalette.danger,
                      label: Text('$attentionTotal'),
                      child: const Icon(Icons.warning_amber_rounded),
                    ),
                  ),
                  _AppBarPill(
                    icon: Icons.person_outline,
                    text: widget.user.role.title,
                  ),
                  IconButton(
                    tooltip: 'Выйти',
                    onPressed: deps.auth.signOut,
                    icon: const Icon(Icons.logout),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _KeyboardTextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Поиск по фамилии',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Очистить',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (query.isEmpty)
                    _ColumnsPane(
                      user: widget.user,
                      columns: columns,
                      selectedColumnId: null,
                      machinists: allMachinists,
                      onSelected: (id) {
                        final column = columns.firstWhere(
                          (item) => item.id == id,
                        );
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ColumnDetailScreen(
                              user: widget.user,
                              column: column,
                              columns: columns,
                            ),
                          ),
                        );
                      },
                    )
                  else if (machinists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(
                        child: Text(
                          'Никого не нашлось',
                          style: TextStyle(color: AppPalette.textSecondary),
                        ),
                      ),
                    )
                  else
                    ...machinists.map(
                      (machinist) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: MachinistCard(
                          user: widget.user,
                          machinist: machinist,
                          columns: columns,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class EmptyDatabaseScreen extends StatefulWidget {
  const EmptyDatabaseScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<EmptyDatabaseScreen> createState() => _EmptyDatabaseScreenState();
}

class _EmptyDatabaseScreenState extends State<EmptyDatabaseScreen> {
  var _loading = false;

  Future<void> _seed() async {
    setState(() => _loading = true);
    try {
      await AppDependencies.of(context).repository.seedDefaults(widget.user);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать данные: $error')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppDependencies.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Колонны'),
        actions: [
          IconButton(
            tooltip: 'Выйти',
            onPressed: deps.auth.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.dataset_outlined, size: 56),
                const SizedBox(height: 16),
                Text(
                  'База Firestore пока пустая',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.user.role.canEditAny
                      ? 'Можно создать 12 колонн и стартовые записи из приложенных Excel-файлов.'
                      : 'Попросите ТЧМ, оператора или администратора выполнить начальное заполнение.',
                  textAlign: TextAlign.center,
                ),
                if (widget.user.role.canEditAny) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _loading ? null : _seed,
                    icon: _loading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.playlist_add_check),
                    label: const Text('Создать 12 колонн'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

int _attentionSortKey(Machinist machinist) {
  int? soonest;
  for (final result in evaluateAllChecks(machinist)) {
    if ((result.status == CheckStatus.overdue ||
            result.status == CheckStatus.soon) &&
        result.daysLeft != null) {
      soonest = soonest == null
          ? result.daysLeft
          : (result.daysLeft! < soonest ? result.daysLeft! : soonest);
    }
  }
  return soonest ?? 1000000;
}

int _compareAttention(Machinist a, Machinist b) {
  final severityA = _statusSeverity(machinistOverallStatus(a));
  final severityB = _statusSeverity(machinistOverallStatus(b));
  if (severityA != severityB) return severityB.compareTo(severityA);
  final daysA = _attentionSortKey(a);
  final daysB = _attentionSortKey(b);
  if (daysA != daysB) return daysA.compareTo(daysB);
  return a.fullName.compareTo(b.fullName);
}

class AttentionScreen extends StatelessWidget {
  const AttentionScreen({super.key, required this.user, required this.columns});

  final AppUser user;
  final List<ColumnGroup> columns;

  @override
  Widget build(BuildContext context) {
    final repository = AppDependencies.of(context).repository;
    return Scaffold(
      appBar: AppBar(title: const Text('Требуют внимания')),
      body: StreamBuilder<List<Machinist>>(
        stream: repository.watchMachinists(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <Machinist>[];
          if (snapshot.connectionState == ConnectionState.waiting &&
              all.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = all.where(machinistNeedsAttention).toList()
            ..sort(_compareAttention);
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Всё в порядке — приближающихся проверок нет.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppPalette.textSecondary),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) => MachinistCard(
              user: user,
              machinist: items[index],
              columns: columns,
            ),
          );
        },
      ),
    );
  }
}

class ColumnDetailScreen extends StatefulWidget {
  const ColumnDetailScreen({
    super.key,
    required this.user,
    required this.column,
    required this.columns,
  });

  final AppUser user;
  final ColumnGroup column;
  final List<ColumnGroup> columns;

  @override
  State<ColumnDetailScreen> createState() => _ColumnDetailScreenState();
}

class _ColumnDetailScreenState extends State<ColumnDetailScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openEditor() {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MachinistEditorScreen(
          user: widget.user,
          columns: widget.columns,
          initialColumn: widget.column,
        ),
      ),
    );
  }

  Future<void> _handleSaveAndroid(List<Machinist> machinists) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Text('Формируется PDF…'),
            ],
          ),
        ),
      ),
    );
    try {
      final bytes = await _buildColumnPdfBytes(widget.column, machinists);
      final dir = Directory('/storage/emulated/0/Download');
      final fileName =
          '${widget.column.title}_${_formatDate(DateTime.now(), fourDigitYear: false).replaceAll('.', '-')}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Сохранено в Загрузки: $fileName')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    }
  }

  Future<void> _handleShare(List<Machinist> machinists) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Text('Формируется PDF…'),
            ],
          ),
        ),
      ),
    );
    try {
      final bytes = await _buildColumnPdfBytes(widget.column, machinists);
      if (mounted) Navigator.of(context).pop();
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${widget.column.title}.pdf',
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка создания PDF: $e')),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final repository = AppDependencies.of(context).repository;
    return StreamBuilder<List<Machinist>>(
      stream: repository.watchMachinists(columnId: widget.column.id),
      builder: (context, snapshot) {
        final allMachinists = snapshot.data ?? const <Machinist>[];
        final query = _search.text.trim().toLowerCase();
        final machinists = query.isEmpty
            ? allMachinists
            : allMachinists.where((item) {
                return item.fullName.toLowerCase().contains(query) ||
                    item.tchmName.toLowerCase().contains(query);
              }).toList();

        return Scaffold(
          appBar: AppBar(
            title: Text(widget.column.title),
            actions: [
              _AppBarPill(
                icon: Icons.engineering_outlined,
                text: '${allMachinists.length} маш.',
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppPalette.deep, AppPalette.accent],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          '${widget.column.number}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.column.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            if (widget.column.tchmName.isNotEmpty)
                              Text(
                                'ТЧМ: ${widget.column.tchmName}',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                            if (widget.column.instructorName.isNotEmpty)
                              Text(
                                'Инструктор: ${widget.column.instructorName}',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.ios_share,
                          color: Colors.white,
                          size: 22,
                        ),
                        onPressed: () => _handleShare(allMachinists),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      if (Platform.isAndroid)
                        IconButton(
                          icon: const Icon(
                            Icons.download,
                            color: Colors.white,
                            size: 22,
                          ),
                          onPressed: () =>
                              _handleSaveAndroid(allMachinists),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _MachinistsPane(
                    user: widget.user,
                    columns: widget.columns,
                    selectedColumn: widget.column,
                    machinists: machinists,
                    search: _search,
                    onSearchChanged: () => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: widget.user.canAddToColumn(widget.column.id)
              ? FloatingActionButton.extended(
                  onPressed: _openEditor,
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Добавить'),
                )
              : null,
        );
      },
    );
  }
}

class _StatusCountBadge extends StatelessWidget {
  const _StatusCountBadge({required this.status, required this.count});

  final CheckStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = checkStatusColor(status);
    final background = status == CheckStatus.overdue
        ? AppPalette.dangerTint
        : AppPalette.warningTint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(checkStatusIcon(status), size: 14, color: color),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ColumnsPane extends StatelessWidget {
  const _ColumnsPane({
    required this.user,
    required this.columns,
    required this.selectedColumnId,
    required this.machinists,
    required this.onSelected,
  });

  final AppUser user;
  final List<ColumnGroup> columns;
  final String? selectedColumnId;
  final List<Machinist> machinists;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: columns.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final column = columns[index];
                final selected = column.id == selectedColumnId;
                final columnMachinists = machinists
                    .where((item) => item.columnId == column.id)
                    .toList();
                final count = columnMachinists.length;
                final overdueCount = columnMachinists
                    .where(
                      (item) =>
                          machinistOverallStatus(item) == CheckStatus.overdue,
                    )
                    .length;
                final soonCount = columnMachinists
                    .where(
                      (item) =>
                          machinistOverallStatus(item) == CheckStatus.soon,
                    )
                    .length;
                return Material(
                  color: selected ? AppPalette.surfaceTint : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onSelected(column.id),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? AppPalette.accent
                              : AppPalette.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppPalette.deep
                                  : AppPalette.surfaceTint,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${column.number}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: selected
                                    ? Colors.white
                                    : AppPalette.deep,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  column.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: AppPalette.textPrimary,
                                  ),
                                ),
                                if (column.tchmName.isNotEmpty)
                                  Text(
                                    'ТЧМ: ${column.tchmName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppPalette.textSecondary,
                                    ),
                                  ),
                                if (column.instructorName.isNotEmpty)
                                  Text(
                                    'Инструктор: ${column.instructorName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppPalette.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (overdueCount > 0) ...[
                            _StatusCountBadge(
                              status: CheckStatus.overdue,
                              count: overdueCount,
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (soonCount > 0) ...[
                            _StatusCountBadge(
                              status: CheckStatus.soon,
                              count: soonCount,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppPalette.surfaceTint,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: AppPalette.deep,
                              ),
                            ),
                          ),
                          if (user.role.isDeveloper) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Изменить ТЧМ / инструктора',
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              color: AppPalette.deep,
                              onPressed: () => _editColumn(context, column),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editColumn(BuildContext context, ColumnGroup column) async {
    final repository = AppDependencies.of(context).repository;
    final messenger = ScaffoldMessenger.of(context);
    final updated = await showDialog<ColumnGroup>(
      context: context,
      builder: (_) => _ColumnEditorDialog(column: column),
    );
    if (updated == null) return;
    try {
      await repository.updateColumn(updated, user);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось сохранить: $error')),
      );
    }
  }
}

class _DeveloperLoginDialog extends StatefulWidget {
  const _DeveloperLoginDialog();

  @override
  State<_DeveloperLoginDialog> createState() => _DeveloperLoginDialogState();
}

class _DeveloperLoginDialogState extends State<_DeveloperLoginDialog> {
  late final TextEditingController _password;

  @override
  void initState() {
    super.initState();
    _password = TextEditingController();
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Вход разработчика'),
      content: _KeyboardTextField(
        controller: _password,
        obscureText: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Пароль разработчика',
          prefixIcon: Icon(Icons.lock_outline),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_password.text),
          child: const Text('Войти'),
        ),
      ],
    );
  }
}

class _ColumnEditorDialog extends StatefulWidget {
  const _ColumnEditorDialog({required this.column});

  final ColumnGroup column;

  @override
  State<_ColumnEditorDialog> createState() => _ColumnEditorDialogState();
}

class _ColumnEditorDialogState extends State<_ColumnEditorDialog> {
  late final TextEditingController _tchmName;
  late final TextEditingController _tchmNumber;
  late final TextEditingController _instructorName;

  @override
  void initState() {
    super.initState();
    _tchmName = TextEditingController(text: widget.column.tchmName);
    _tchmNumber = TextEditingController(
      text: widget.column.tchmPersonnelNumber,
    );
    _instructorName = TextEditingController(text: widget.column.instructorName);
  }

  @override
  void dispose() {
    _tchmName.dispose();
    _tchmNumber.dispose();
    _instructorName.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      widget.column.copyWith(
        tchmName: _tchmName.text.trim(),
        tchmPersonnelNumber: _tchmNumber.text.trim(),
        instructorName: _instructorName.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Колонна ${widget.column.number}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _tchmName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'ТЧМ (фамилия, инициалы)',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tchmNumber,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Табельный ТЧМ',
                prefixIcon: Icon(Icons.tag),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _instructorName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Инструктор (фамилия, инициалы)',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(onPressed: _save, child: const Text('Сохранить')),
      ],
    );
  }
}

class _MachinistsPane extends StatelessWidget {
  const _MachinistsPane({
    required this.user,
    required this.columns,
    required this.selectedColumn,
    required this.machinists,
    required this.search,
    required this.onSearchChanged,
  });

  final AppUser user;
  final List<ColumnGroup> columns;
  final ColumnGroup? selectedColumn;
  final List<Machinist> machinists;
  final TextEditingController search;
  final VoidCallback onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final title = selectedColumn == null ? 'Все машинисты' : 'Машинисты';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimary,
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  width: 300,
                  child: _KeyboardTextField(
                    controller: search,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => onSearchChanged(),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Поиск',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: machinists.isEmpty
                  ? const _EmptyList()
                  : ListView.separated(
                      itemCount: machinists.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        return MachinistCard(
                          user: user,
                          machinist: machinists[index],
                          columns: columns,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Нет записей. Выберите колонну и добавьте машиниста.'),
    );
  }
}

class MachinistCard extends StatelessWidget {
  const MachinistCard({
    super.key,
    required this.user,
    required this.machinist,
    required this.columns,
  });

  final AppUser user;
  final Machinist machinist;
  final List<ColumnGroup> columns;

  @override
  Widget build(BuildContext context) {
    final canEdit = user.canEditMachinist(machinist);
    final column = columns
        .where((value) => value.id == machinist.columnId)
        .cast<ColumnGroup?>()
        .firstOrNull;
    final statusByDiscipline = {
      for (final result in evaluateAllChecks(machinist))
        result.discipline: result.status,
    };
    final overall = machinistOverallStatus(machinist);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: canEdit
            ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MachinistEditorScreen(
                    user: user,
                    columns: columns,
                    machinist: machinist,
                    initialColumn: column,
                  ),
                ),
              )
            : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppPalette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          machinist.fullName,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          [
                            'Колонна ${machinist.columnNumber}',
                            if (machinist.classRank.isNotEmpty)
                              'Класс ${machinist.classRank}',
                            if (machinist.vn.isNotEmpty) 'В/Н ${machinist.vn}',
                          ].join(' · '),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppPalette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (overall != CheckStatus.ok)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        checkStatusIcon(overall),
                        size: 18,
                        color: checkStatusColor(overall),
                      ),
                    ),
                  if (canEdit)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: AppPalette.textSecondary,
                      ),
                    ),
                ],
              ),
              _WorkMarksPanel(
                marks: [
                  _WorkMark('Начало', machinist.workStart, Icons.event_note),
                  _WorkMark(
                    'Талон',
                    machinist.ticket,
                    Icons.confirmation_number_outlined,
                  ),
                  _WorkMark(
                    'КИП',
                    machinist.kip,
                    Icons.build_circle_outlined,
                    status: statusByDiscipline[CheckDiscipline.kip],
                  ),
                  _WorkMark(
                    'ТРА',
                    machinist.tra,
                    Icons.route_outlined,
                    status: statusByDiscipline[CheckDiscipline.tra],
                  ),
                  _WorkMark(
                    'АТЗ',
                    machinist.atz,
                    Icons.local_gas_station_outlined,
                    status: statusByDiscipline[CheckDiscipline.atz],
                  ),
                  _WorkMark(
                    'Сцеп',
                    _couplingMark(machinist),
                    Icons.link,
                    status: statusByDiscipline[CheckDiscipline.coupling],
                  ),
                ],
              ),
              if (machinist.kipExtensionMonths > 0) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppPalette.surfaceTint,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppPalette.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.gavel_outlined,
                        size: 14,
                        color: AppPalette.deep,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          [
                            'КИП +${machinist.kipExtensionMonths} мес.',
                            if (machinist.kipExtensionOrder.isNotEmpty)
                              machinist.kipExtensionOrder,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppPalette.deep,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (machinist.notes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  machinist.notes,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppPalette.textPrimary,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.history,
                    size: 14,
                    color: AppPalette.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Изменено: ${_formatDateTime(machinist.updatedAt)} · '
                      '${machinist.updatedBy.isEmpty ? 'неизвестно' : machinist.updatedBy}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppPalette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

DateTime? _parseDate(String text) {
  final match = RegExp(
    r'^(\d{1,2})\.(\d{1,2})\.(\d{2}|\d{4})$',
  ).firstMatch(text.trim());
  if (match == null) return null;
  final day = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  var year = int.parse(match.group(3)!);
  if (year < 100) year += 2000;
  try {
    final parsed = DateTime(year, month, day);
    if (parsed.day != day || parsed.month != month) return null;
    return parsed;
  } catch (_) {
    return null;
  }
}

String _formatDate(DateTime date, {required bool fourDigitYear}) {
  final dd = date.day.toString().padLeft(2, '0');
  final mm = date.month.toString().padLeft(2, '0');
  final year = fourDigitYear
      ? date.year.toString()
      : (date.year % 100).toString().padLeft(2, '0');
  return '$dd.$mm.$year';
}

String _formatDateTime(DateTime date) {
  if (date.millisecondsSinceEpoch == 0) return 'нет данных';
  final hh = date.hour.toString().padLeft(2, '0');
  final min = date.minute.toString().padLeft(2, '0');
  return '${_formatDate(date, fourDigitYear: true)} $hh:$min';
}

String _couplingMark(Machinist machinist) {
  return [
    machinist.coupling,
    if (machinist.vn.isNotEmpty) '(${machinist.vn})',
  ].where((part) => part.isNotEmpty).join(' ');
}

Future<Uint8List> _buildColumnPdfBytes(
  ColumnGroup column,
  List<Machinist> machinists,
) async {
  final fontRegular = await PdfGoogleFonts.notoSansRegular();
  final fontBold = await PdfGoogleFonts.notoSansBold();

  final dateStr = _formatDate(DateTime.now(), fourDigitYear: false);

  pw.TextStyle bold([double size = 8]) =>
      pw.TextStyle(font: fontBold, fontSize: size, color: PdfColors.black);

  pw.TextStyle regular([double size = 8]) =>
      pw.TextStyle(font: fontRegular, fontSize: size, color: PdfColors.black);

  pw.TextStyle regularBold([double size = 8]) =>
      pw.TextStyle(font: fontBold, fontSize: size, color: PdfColors.black);

  pw.Widget hCell(String text) => pw.Container(
    color: PdfColors.white,
    alignment: pw.Alignment.center,
    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 4),
    child: pw.Text(text, style: bold(), textAlign: pw.TextAlign.center),
  );

  pw.Widget dCell(String text, {CheckStatus? status}) => pw.Container(
    color: PdfColors.white,
    alignment: pw.Alignment.center,
    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
    child: pw.Text(
      text,
      style: status == CheckStatus.overdue ? regularBold() : regular(),
      textAlign: pw.TextAlign.center,
    ),
  );

  pw.Widget nameCell(String text) => pw.Container(
    color: PdfColors.white,
    alignment: pw.Alignment.centerLeft,
    padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
    child: pw.Text(text, style: regular()),
  );

  final dataRows = <pw.TableRow>[];
  for (int i = 0; i < machinists.length; i++) {
    final m = machinists[i];
    final checks = {
      for (final r in evaluateAllChecks(m)) r.discipline: r.status,
    };
    final couplingText = _couplingMark(m);
    dataRows.add(pw.TableRow(
      children: [
        dCell('${i + 1}'),
        nameCell(m.fullName),
        dCell(m.workStart.isEmpty ? '—' : m.workStart),
        dCell(m.classRank.isEmpty ? '—' : m.classRank),
        dCell(
          m.kip.isEmpty ? '—' : m.kip,
          status: checks[CheckDiscipline.kip],
        ),
        dCell(
          m.atz.isEmpty ? '—' : m.atz,
          status: checks[CheckDiscipline.atz],
        ),
        dCell(
          couplingText.isEmpty ? '—' : couplingText,
          status: checks[CheckDiscipline.coupling],
        ),
        dCell(
          m.tra.isEmpty ? '—' : m.tra,
          status: checks[CheckDiscipline.tra],
        ),
      ],
    ));
  }

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        // Шапка: дата слева, название колонны по центру
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 0.5),
          ),
          child: pw.Row(
            children: [
              pw.Text(dateStr, style: bold(10)),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: pw.Text(
                  '${column.title}'
                  '${column.tchmName.isNotEmpty ? '  ${column.tchmName}' : ''}',
                  style: bold(12),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        // Таблица
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          columnWidths: const {
            0: pw.FixedColumnWidth(20),
            1: pw.FlexColumnWidth(1.6),
            2: pw.FixedColumnWidth(65),
            3: pw.FixedColumnWidth(28),
            4: pw.FlexColumnWidth(1.2),
            5: pw.FlexColumnWidth(1.2),
            6: pw.FlexColumnWidth(1.2),
            7: pw.FlexColumnWidth(1.2),
          },
          children: [
            pw.TableRow(
              children: [
                hCell('№'),
                hCell('Машинисты'),
                hCell('Начало работы'),
                hCell('Класс'),
                hCell('КИП'),
                hCell('АТЗ'),
                hCell('Сцеп'),
                hCell('ТРА'),
              ],
            ),
            ...dataRows,
          ],
        ),
      ],
    ),
  );

  return doc.save();
}

void _showKeyboard(FocusNode focusNode) {
  focusNode.requestFocus();
  SystemChannels.textInput.invokeMethod<void>('TextInput.show');
}

class _KeyboardTextField extends StatefulWidget {
  const _KeyboardTextField({
    required this.controller,
    required this.decoration,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_KeyboardTextField> createState() => _KeyboardTextFieldState();
}

class _KeyboardTextFieldState extends State<_KeyboardTextField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      obscureText: widget.obscureText,
      decoration: widget.decoration,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onTap: () => _showKeyboard(_focusNode),
    );
  }
}

class _KeyboardTextFormField extends StatefulWidget {
  const _KeyboardTextFormField({
    required this.controller,
    required this.decoration,
    this.textInputAction,
    this.validator,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final TextInputAction? textInputAction;
  final FormFieldValidator<String>? validator;
  final int maxLines;

  @override
  State<_KeyboardTextFormField> createState() => _KeyboardTextFormFieldState();
}

class _KeyboardTextFormFieldState extends State<_KeyboardTextFormField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: _focusNode,
      maxLines: widget.maxLines,
      textInputAction: widget.textInputAction,
      decoration: widget.decoration,
      validator: widget.validator,
      onTap: () => _showKeyboard(_focusNode),
    );
  }
}

class _AppBarPill extends StatelessWidget {
  const _AppBarPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkMark {
  const _WorkMark(this.title, this.value, this.icon, {this.status});

  final String title;
  final String value;
  final IconData icon;
  final CheckStatus? status;
}

class _WorkMarksPanel extends StatelessWidget {
  const _WorkMarksPanel({required this.marks});

  final List<_WorkMark> marks;

  @override
  Widget build(BuildContext context) {
    final visibleMarks = marks.where((mark) => mark.value.isNotEmpty).toList();
    if (visibleMarks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 5,
        runSpacing: 5,
        children: visibleMarks.map((mark) {
          final status = mark.status;
          final highlighted =
              status == CheckStatus.overdue || status == CheckStatus.soon;
          final background = switch (status) {
            CheckStatus.overdue => AppPalette.dangerTint,
            CheckStatus.soon => AppPalette.warningTint,
            _ => AppPalette.surfaceTint,
          };
          final titleColor = highlighted
              ? checkStatusColor(status!)
              : AppPalette.deep;
          final valueColor = highlighted
              ? checkStatusColor(status!)
              : AppPalette.textPrimary;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  if (highlighted)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Icon(
                          checkStatusIcon(status!),
                          size: 13,
                          color: titleColor,
                        ),
                      ),
                    ),
                  TextSpan(
                    text: '${mark.title} ',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: titleColor,
                    ),
                  ),
                  TextSpan(
                    text: mark.value,
                    style: TextStyle(fontSize: 12, color: valueColor),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class MachinistEditorScreen extends StatefulWidget {
  const MachinistEditorScreen({
    super.key,
    required this.user,
    required this.columns,
    this.machinist,
    this.initialColumn,
  });

  final AppUser user;
  final List<ColumnGroup> columns;
  final Machinist? machinist;
  final ColumnGroup? initialColumn;

  @override
  State<MachinistEditorScreen> createState() => _MachinistEditorScreenState();
}

class _MachinistEditorScreenState extends State<MachinistEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _columnId;
  late final TextEditingController _fullName;
  late MachinistClass _class;
  late final TextEditingController _workStart;
  late final TextEditingController _ticket;
  late final TextEditingController _kip;
  late final TextEditingController _tra;
  late final TextEditingController _atz;
  late final TextEditingController _coupling;
  late final TextEditingController _notes;
  late final TextEditingController _kipExtensionOrder;
  var _kipExtended = false;
  var _couplingFaulty = false;
  var _couplingAuxiliary = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.machinist;
    _columnId =
        item?.columnId ?? widget.initialColumn?.id ?? widget.columns.first.id;
    _fullName = TextEditingController(text: item?.fullName ?? '');
    _class = machinistClassFromRank(item?.classRank ?? '');
    _workStart = TextEditingController(text: item?.workStart ?? '');
    _ticket = TextEditingController(text: item?.ticket ?? '');
    _kip = TextEditingController(text: item?.kip ?? '');
    _tra = TextEditingController(text: item?.tra ?? '');
    _atz = TextEditingController(text: item?.atz ?? '');
    _coupling = TextEditingController(text: item?.coupling ?? '');
    _notes = TextEditingController(text: item?.notes ?? '');
    _kipExtensionOrder = TextEditingController(
      text: item?.kipExtensionOrder ?? '',
    );
    _kipExtended = (item?.kipExtensionMonths ?? 0) > 0;
    final vn = item?.vn ?? '';
    _couplingAuxiliary = vn.contains('В');
    _couplingFaulty = vn.contains('Н');
  }

  @override
  void dispose() {
    _fullName.dispose();
    _workStart.dispose();
    _ticket.dispose();
    _kip.dispose();
    _tra.dispose();
    _atz.dispose();
    _coupling.dispose();
    _notes.dispose();
    _kipExtensionOrder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final column = widget.columns.firstWhere((value) => value.id == _columnId);
    final repository = AppDependencies.of(context).repository;
    final item = Machinist(
      id: widget.machinist?.id ?? '',
      columnId: column.id,
      columnNumber: column.number,
      fullName: _fullName.text.trim(),
      classRank: _class.rank,
      workStart: _workStart.text.trim(),
      ticket: _ticket.text.trim(),
      kip: _kip.text.trim(),
      tra: _tra.text.trim(),
      atz: _atz.text.trim(),
      coupling: _coupling.text.trim(),
      vn: _couplingState,
      tchmName: column.tchmName,
      notes: _notes.text.trim(),
      kipExtensionMonths: _kipExtended ? 12 : 0,
      kipExtensionOrder: _kipExtended ? _kipExtensionOrder.text.trim() : '',
      updatedAt: DateTime.now(),
      updatedBy: widget.user.displayName,
    );

    if (await _hasDuplicateName(repository, column, item)) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Машинист уже добавлен'),
          content: Text(
            'В колонне №${column.number} уже есть машинист '
            '«${item.fullName}». Всё равно сохранить?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await repository.saveMachinist(item, widget.user);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось сохранить: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _hasDuplicateName(
    TchmRepository repository,
    ColumnGroup column,
    Machinist item,
  ) async {
    final name = item.fullName.toLowerCase();
    if (name.isEmpty) return false;
    try {
      final existing = await repository
          .watchMachinists(columnId: column.id)
          .first;
      final currentId = widget.machinist?.id ?? '';
      return existing.any(
        (other) =>
            other.id != currentId &&
            other.fullName.trim().toLowerCase() == name,
      );
    } catch (_) {
      // Проверка не должна блокировать сохранение при ошибке чтения.
      return false;
    }
  }

  Future<void> _delete() async {
    final item = widget.machinist;
    if (item == null) return;
    final repository = AppDependencies.of(context).repository;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить машиниста?'),
        content: Text(item.fullName),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repository.deleteMachinist(item, widget.user);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось удалить: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canChangeColumn = widget.user.role.canEditAny;
    final canDelete =
        widget.machinist != null &&
        widget.user.canEditMachinist(widget.machinist!);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.machinist == null ? 'Новый машинист' : 'Машинист'),
        actions: [
          if (canDelete)
            IconButton(
              tooltip: 'Удалить',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle('Основное'),
              DropdownButtonFormField<String>(
                initialValue: _columnId,
                decoration: const InputDecoration(
                  labelText: 'Колонна',
                  prefixIcon: Icon(Icons.train_outlined),
                ),
                items: widget.columns.map((column) {
                  return DropdownMenuItem(
                    value: column.id,
                    enabled:
                        canChangeColumn ||
                        widget.user.canAddToColumn(column.id),
                    child: Text(column.title),
                  );
                }).toList(),
                onChanged: canChangeColumn
                    ? (value) {
                        if (value != null) setState(() => _columnId = value);
                      }
                    : null,
              ),
              const SizedBox(height: 12),
              _field(
                _fullName,
                'ФИО машиниста',
                Icons.person_outline,
                required: true,
              ),
              _twoFields(
                _classDropdown(),
                _dateField(
                  _workStart,
                  'Начало работы',
                  Icons.calendar_month_outlined,
                  fourDigitYear: true,
                ),
              ),
              const SizedBox(height: 8),
              _sectionTitle('Отметки о проведенных работах'),
              _twoFields(
                _field(_ticket, 'Талон', Icons.confirmation_number_outlined),
                _dateField(_kip, 'КИП', Icons.build_circle_outlined),
              ),
              _twoFields(
                _dateField(_tra, 'ТРА', Icons.route_outlined),
                _dateField(_atz, 'АТЗ', Icons.local_gas_station_outlined),
              ),
              _dateField(_coupling, 'Сцеп', Icons.link),
              _couplingToggles(),
              const SizedBox(height: 8),
              _sectionTitle('Приказ по КИП'),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                secondary: const Icon(Icons.gavel_outlined),
                title: const Text('Продлить КИП на 12 месяцев'),
                subtitle: const Text(
                  'Только срок КИП будет считаться на год позже',
                ),
                value: _kipExtended,
                onChanged: (value) => setState(() => _kipExtended = value),
              ),
              if (_kipExtended)
                _field(
                  _kipExtensionOrder,
                  'Приказ или распоряжение',
                  Icons.description_outlined,
                ),
              const SizedBox(height: 8),
              _sectionTitle('Дополнительно'),
              _field(_notes, 'Примечание', Icons.notes_outlined, maxLines: 3),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Сохранить'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AppPalette.textSecondary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  String get _couplingState {
    if (_couplingAuxiliary) return 'В';
    if (_couplingFaulty) return 'Н';
    return '';
  }

  Widget _couplingToggles() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            secondary: const Icon(Icons.report_problem_outlined),
            title: const Text('Неисправный (Н)'),
            value: _couplingFaulty,
            onChanged: (value) => setState(() {
              _couplingFaulty = value;
              if (value) _couplingAuxiliary = false;
            }),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            secondary: const Icon(Icons.support_outlined),
            title: const Text('Вспомогательный (В)'),
            value: _couplingAuxiliary,
            onChanged: (value) => setState(() {
              _couplingAuxiliary = value;
              if (value) _couplingFaulty = false;
            }),
          ),
        ],
      ),
    );
  }

  Widget _classDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<MachinistClass>(
        initialValue: _class,
        decoration: const InputDecoration(
          labelText: 'Класс',
          prefixIcon: Icon(Icons.workspace_premium_outlined),
        ),
        items: MachinistClass.values
            .map(
              (value) =>
                  DropdownMenuItem(value: value, child: Text(value.label)),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) setState(() => _class = value);
        },
      ),
    );
  }

  Widget _dateField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool fourDigitYear = false,
  }) {
    final hasValue = controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        onTap: () => _pickDate(controller, fourDigitYear: fourDigitYear),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: hasValue
              ? IconButton(
                  tooltip: 'Очистить',
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => setState(() => controller.text = ''),
                )
              : const Icon(Icons.calendar_today_outlined, size: 18),
        ),
      ),
    );
  }

  Future<void> _pickDate(
    TextEditingController controller, {
    required bool fourDigitYear,
  }) async {
    final initial = _parseDate(controller.text) ?? DateTime.now();
    final picked = await _showAdaptiveDatePicker(initial);
    if (picked == null) return;
    setState(
      () => controller.text = _formatDate(picked, fourDigitYear: fourDigitYear),
    );
  }

  Future<DateTime?> _showAdaptiveDatePicker(DateTime initial) {
    final first = DateTime(1900);
    final last = DateTime(2200);
    final clampedInitial = initial.isBefore(first)
        ? first
        : (initial.isAfter(last) ? last : initial);
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      var selected = clampedInitial;
      return showModalBottomSheet<DateTime>(
        context: context,
        builder: (sheetContext) {
          return SafeArea(
            child: SizedBox(
              height: 300,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CupertinoButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Отмена'),
                      ),
                      CupertinoButton(
                        onPressed: () =>
                            Navigator.of(sheetContext).pop(selected),
                        child: const Text('Готово'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.date,
                      initialDateTime: clampedInitial,
                      minimumDate: first,
                      maximumDate: last,
                      onDateTimeChanged: (value) => selected = value,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
    return showDatePicker(
      context: context,
      initialDate: clampedInitial,
      firstDate: first,
      lastDate: last,
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool required = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _KeyboardTextFormField(
        controller: controller,
        maxLines: maxLines,
        textInputAction: maxLines > 1
            ? TextInputAction.newline
            : TextInputAction.next,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        validator: required
            ? (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Заполните поле';
                }
                return null;
              }
            : null,
      ),
    );
  }

  Widget _twoFields(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(children: [first, second]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class SeedData {
  static const columnTchmNumbers = <int, String>{
    1: '1145',
    2: '488',
    3: '462',
    4: '130',
    5: '1004',
    6: '384',
    7: '502',
    8: '322',
    9: '392',
    10: '628',
    11: '342',
    12: '169',
  };

  static final columns = List<ColumnGroup>.unmodifiable([
    for (var i = 1; i <= 12; i++)
      ColumnGroup(
        id: 'column_$i',
        number: i,
        title: 'Колонна №$i',
        instructorName: '',
        tchmName: tchmNameForPersonnelNumber(columnTchmNumbers[i] ?? '') ?? '',
        tchmPersonnelNumber: columnTchmNumbers[i] ?? '',
      ),
  ]);

  static final machinists = List<Machinist>.unmodifiable([
    _m(
      3,
      'Балашенков А.В.',
      '2',
      '07.12.2008',
      '',
      '17.02.26',
      '10.05.26',
      '10.05.26',
      '46070',
      '',
      '',
    ),
    _m(
      3,
      'Колосов И.В.',
      '2',
      '24.06.2015',
      '',
      '24.05.26',
      '04.05.26',
      '29.05.26',
      '45988',
      '',
      '',
    ),
    _m(
      3,
      'Яценко И.В.',
      '3',
      '09.11.2008',
      '',
      '28.04.26',
      '04.05.26',
      '28.04.26',
      '46016',
      '',
      '',
    ),
    _m(
      3,
      'Сидоренко Р.В.',
      '2',
      '03.06.2006',
      '',
      '24.05.26',
      '04.05.26',
      '08.04.26',
      '46038',
      '',
      '',
    ),
    _m(
      3,
      'Шкребец С.П.',
      '1',
      '09.06.2003',
      '',
      '01.06.26',
      '01.06.26',
      '28.04.26',
      '46016',
      '',
      '',
    ),
    _m(
      3,
      'Ширяев Г.В.',
      '3',
      '',
      '',
      '05.03.26',
      '',
      '21.03.26',
      '46051',
      '',
      '',
    ),
    _m(
      3,
      'Малютин А.Ю.',
      '3',
      '13.11.2016',
      '',
      '27.04.26',
      '01.06.26',
      '10.05.26',
      '46120',
      '',
      '',
    ),
    _m(
      3,
      'Хорохонов А.Б.',
      '2',
      '01.09.2008',
      '',
      '29.04.26',
      '18.05.26',
      '28.04.26',
      '46070',
      '',
      '',
    ),
    _m(
      3,
      'Романов В.А.',
      '1',
      '03.03.2015',
      '',
      '24.05.26',
      '04.05.26',
      '10.05.26',
      '46051',
      '',
      '',
    ),
    _m(
      3,
      'Логинов Д.Н.',
      '1',
      '07.11.2019',
      '',
      '13.01.26',
      '07.04.26',
      '08.04.26',
      '46120',
      '',
      '',
    ),
    _m(
      3,
      'Кузнецов А.А.',
      '1',
      '',
      '',
      '04.03.26',
      '29.05.26',
      '29.05.26',
      '46171',
      '',
      '',
    ),
    _m(
      3,
      'Кирьянов М.И.',
      '1',
      '16.05.2012',
      '',
      '04.03.26',
      '05.05.26',
      '29.05.26',
      '46171',
      '',
      '',
    ),
    _m(
      6,
      'Арабян Д.Д',
      '3',
      '45588',
      '1',
      '46147',
      '46142',
      '46165',
      '45973',
      'Н',
      'Гаврик С.А.',
    ),
    _m(
      6,
      'Будрин А.П.',
      '2',
      '42093',
      '1',
      '46168',
      '46165',
      '46179',
      '46092',
      'В',
      'Гаврик С.А.',
    ),
    _m(
      6,
      'Гордеев О.А.',
      '2',
      '2010',
      '1',
      '46102',
      '46167',
      '46141',
      '45940',
      'Н',
      'Гаврик С.А.',
    ),
    _m(
      6,
      'Борзых В.Д',
      '3',
      '45259',
      '1',
      '46146',
      '46146',
      '46165',
      '45924',
      'Н',
      'Гаврик С.А.',
    ),
    _m(
      6,
      'Денищук А.А.',
      '3',
      '39419',
      '2',
      '46180',
      '46154',
      '46154',
      '46154',
      'Н',
      'Гаврик С.А.',
    ),
    _m(
      6,
      'Исаев А.П.',
      '1',
      '40785',
      '1',
      '46128',
      '46155',
      '46146',
      '46063',
      'В',
      'Гаврик С.А.',
    ),
    _m(
      6,
      'Карлин А.И.',
      '3',
      '41372',
      '1',
      '46114',
      '46119',
      '46119',
      '46078',
      'В',
      'Гаврик С.А.',
    ),
    _m(
      6,
      'Малинов С.В',
      '1',
      '42318',
      '1',
      '46146',
      '46165',
      '46165',
      '46043',
      'Н',
      'Гаврик С.А.',
    ),
    _m(
      6,
      'Самохвалов С.М.',
      '2',
      '2002',
      '1',
      '46142',
      '46128',
      '46154',
      '46154',
      'В',
      'Гаврик С.А.',
    ),
    _m(
      6,
      'Сапего Д.С.',
      '1',
      '2016',
      '1',
      '46176',
      '46176',
      '46175',
      '45678',
      'Н',
      'Гаврик С.А.',
    ),
    _m(
      6,
      'Шляпин А.Г.',
      '2',
      '2006',
      '1',
      '46180',
      '46165',
      '46127',
      '45981',
      'Н',
      'Гаврик С.А.',
    ),
    _m(
      6,
      'Штанин М.В.',
      '2',
      '2008',
      '1',
      '46129',
      '46127',
      '46179',
      '46127',
      'В',
      'Гаврик С.А.',
    ),
    _m(
      6,
      'Павлов И.Н',
      '1',
      '43591',
      '1',
      '46147',
      '46167',
      '46179',
      '46119',
      'В',
      'Гаврик С.А.',
    ),
    _m(
      6,
      'Гамов Т.В.',
      '2',
      '43825',
      '2',
      '46143',
      '46155',
      '46127',
      '45940',
      'В',
      'Гаврик С.А.',
    ),
    _m(
      6,
      'Сыкулев М.О.',
      '2',
      '44376',
      '1',
      '46146',
      '46180',
      '46165',
      '46092',
      'Н',
      'Гаврик С.А.',
    ),
    _m(
      6,
      'Казаков Ю.Ю.',
      '2',
      '2018',
      '1',
      '46180',
      '46169',
      '46179',
      '46119',
      'Н',
      'Гаврик С.А.',
    ),
  ]);

  static Machinist _m(
    int columnNumber,
    String fullName,
    String classRank,
    String workStart,
    String ticket,
    String kip,
    String tra,
    String atz,
    String coupling,
    String vn,
    String tchmName,
  ) {
    return Machinist(
      id: '${columnNumber}_${fullName.toLowerCase().replaceAll(' ', '_').replaceAll('.', '')}',
      columnId: 'column_$columnNumber',
      columnNumber: columnNumber,
      fullName: fullName.trim(),
      classRank: classRank,
      workStart: workStart,
      ticket: ticket,
      kip: kip,
      tra: tra,
      atz: atz,
      coupling: coupling,
      vn: vn.toUpperCase(),
      tchmName: tchmName,
      notes: '',
      kipExtensionMonths: 0,
      kipExtensionOrder: '',
      updatedAt: DateTime(2026, 6, 10, 12),
      updatedBy: 'Импорт из Excel',
    );
  }
}

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) return iterator.current;
    return null;
  }
}
