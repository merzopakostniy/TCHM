import 'dart:async';
import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'column_actions.dart';
import 'api_backend.dart';
import 'depots.dart';
import 'legal.dart';
import 'runtime_config.dart';
import 'invite_codes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TchmApp());
}

class TchmApp extends StatefulWidget {
  const TchmApp({super.key});

  /// Рабочие сборки всегда используют Yandex API; демо возможно только в debug.
  static const useYandexApi = !RuntimeConfig.demo;

  @override
  State<TchmApp> createState() => _TchmAppState();
}

class _TchmAppState extends State<TchmApp> {
  /// Репозиторий и вход создаются один раз за запуск, а не в `build`.
  ///
  /// У Firebase это было неважно: данные шли потоком из базы, и новый
  /// объект подхватывал их сам. Репозиторий нового API держит загруженные
  /// списки в себе, и пересоздание обнуляло их — экран становился пустым на
  /// ровном месте, стоило приложению перерисоваться.
  late final ApiClient _api = ApiClient();
  late final TchmRepository _repository = _createRepository();
  late final AppAuth _auth = _createAuth();

  TchmRepository _createRepository() {
    if (TchmApp.useYandexApi) return ApiTchmRepository(_api);
    return LocalTchmRepository();
  }

  AppAuth _createAuth() {
    if (TchmApp.useYandexApi) return ApiAppAuth(_api);
    return DemoAppAuth();
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    final auth = _auth;

    return AppDependencies(
      repository: repository,
      auth: auth,
      firebaseReady: false,
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

/// Палитра интерфейса. Строится вокруг одного правила: база нейтральная,
/// цвет несёт смысл. Красный — фирменный, из [DepotBrand], и означает
/// «главное действие или принадлежность депо». Всё остальное — оттенки
/// серого, поэтому акцент виден и не спорит сам с собой.
///
/// Раньше база была синей, а акценты красными: два несвязанных цвета
/// делили экран, и интерфейс распадался на куски.
abstract final class AppPalette {
  /// Зерно цветовой схемы Material — фирменный красный.
  static const seed = DepotBrand.redInk;

  /// Тёмный графит: тексты кнопок, всплывающие сообщения, подписи отметок.
  /// Раньше здесь был тёмно-синий, тянувший интерфейс в холод.
  static const deep = Color(0xFF23262B);
  static const deepLight = Color(0xFF3A3F45);

  /// Акцент ввода — тот же фирменный красный, что у кнопок.
  static const accent = DepotBrand.redInk;

  static const surfaceTint = Color(0xFFF1F0EE);
  static const background = Color(0xFFF5F4F2);
  static const border = Color(0xFFE4E2DE);
  static const textPrimary = Color(0xFF1B1D20);
  static const textSecondary = Color(0xFF6C7075);

  /// Статусы. Красный тревоги ярче фирменного: он должен выделяться
  /// на фоне красной шапки, а не сливаться с ней.
  static const danger = Color(0xFFC0272D);
  static const dangerTint = Color(0xFFFBE8E8);
  static const warning = Color(0xFF9A6410);
  static const warningTint = Color(0xFFFAEFDC);
}

/// Пиктограммы отметок подбираются по смыслу, а не по названию поля.
abstract final class MachinistIcons {
  static const classRank = Icons.star_outline;
  static const kip = Icons.fact_check_outlined;
  static const tra = Icons.article_outlined;
  static const atz = Icons.health_and_safety_outlined;
  static const coupling = Icons.merge_type;
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
      backgroundColor: DepotBrand.redInk,
      foregroundColor: Colors.white,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      // На тёмной шапке значки статус-бара должны быть светлыми,
      // иначе на красном их не видно.
      systemOverlayStyle: SystemUiOverlayStyle.light,
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
      backgroundColor: DepotBrand.redInk,
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

/// Состояние учётной записи. До подтверждения почты и до одобрения
/// руководителем человек внутрь не попадает — видит экран ожидания.
enum AccountStatus { pending, active, disabled }

AccountStatus statusFromString(Object? value) {
  return AccountStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => AccountStatus.active,
  );
}

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

  bool get canManageAllDepots => this == UserRole.admin || isDeveloper;

  bool get canManageAccounts => canManageAllDepots;

  bool get canManageDatabaseLock => isDeveloper;

  /// Право вынести данные из приложения: PDF колонны. Гостю закрыто —
  /// он смотрит, а не забирает. Инструктору оставлено: он ведёт свою
  /// колонну, и печатная форма ему нужна в работе.
  bool get canExportData => this != UserRole.viewer;
}

UserRole roleFromString(Object? value) {
  return UserRole.values.firstWhere(
    (role) => role.key == value,
    orElse: () => UserRole.viewer,
  );
}

// Уволившиеся из списка убираются: справочник подставляет ФИО ТЧМ и
// попадает в реестр, а реестр при регистрации главнее выбора роли.
// Агапитов В.А. (таб. 2680) убран 01.09.2026 — больше не работает.
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
  '1984': 'Покрышкин А.Н.',
  '966': 'Архипов А.С.',
  '941': 'Серяпин С.И.',
  '1671': 'Серков Н.А.',
  '505': 'Пауткин В.А.',
};

// Табельный номер разработчика. Вход под ним даёт роль «Разработчик»
// с полными правами на изменение и редактирование всего.
const developerPersonnelNumber = '1916';

bool isDeveloperPersonnelNumber(String number) {
  return number.trim() == developerPersonnelNumber;
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
    this.depotId,
    this.status = AccountStatus.active,
    this.personnelNumber,
    this.assignedColumnId,
    this.accessBlocked = false,
  });

  final String id;
  final String email;
  final String displayName;
  final UserRole role;

  /// Депо, к которому привязан человек: `tch16`. Пока данные лежат в общих
  /// коллекциях, поле только показывается в интерфейсе — разделять по нему
  /// доступ будем на фазе мультидепо.
  final String? depotId;

  final AccountStatus status;
  final String? personnelNumber;
  final String? assignedColumnId;

  /// Временный признак: пользователь вошёл, но правила запретили чтение его
  /// профиля (включена полная блокировка, а роль — не разработчик). В базу не
  /// пишется, живёт только в потоке авторизации.
  final bool accessBlocked;

  bool canAddToColumn(String columnId) {
    return role.canEditAny ||
        (role == UserRole.instructor && assignedColumnId == columnId);
  }

  bool canEditMachinist(Machinist machinist) {
    return canAddToColumn(machinist.columnId);
  }

  /// Название депо для шапки и профиля.
  String get depotTitle => MoscowDepots.titleFor(depotId);

  /// Разработчик работает поверх всех депо, поэтому ожидание подтверждения
  /// его не касается — иначе снять блокировку будет некому.
  bool get awaitingApproval =>
      status == AccountStatus.pending && role != UserRole.developer;

  bool get disabled => status == AccountStatus.disabled;

  Map<String, Object?> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'role': role.key,
      'depotId': depotId,
      'status': status.name,
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
      depotId: map['depotId'] as String?,
      status: statusFromString(map['status']),
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
    this.depotId,
  });

  final String id;

  /// Депо, которому принадлежит колонна. У записей, созданных до перехода
  /// на мультидепо, пусто — их проставляет скрипт миграции.
  final String? depotId;

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
      depotId: depotId,
      number: number,
      title: title ?? this.title,
      instructorName: instructorName ?? this.instructorName,
      tchmName: tchmName ?? this.tchmName,
      tchmPersonnelNumber: tchmPersonnelNumber ?? this.tchmPersonnelNumber,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'depotId': depotId,
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
      depotId: map['depotId'] as String?,
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
    this.depotId,
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

  /// Депо машиниста. Пусто у записей, созданных до мультидепо.
  final String? depotId;

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
    String? depotId,
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
      depotId: depotId ?? this.depotId,
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
      'depotId': depotId,
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
      depotId: map['depotId'] as String?,
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
    CheckDiscipline.atz => 'АЗЗ',
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

/// Данные, которые человек заполняет при регистрации.
class RegistrationRequest {
  const RegistrationRequest({
    required this.depotId,
    required this.displayName,
    required this.personnelNumber,
    required this.email,
    required this.password,
    required this.inviteCode,
    required this.role,
  });

  final String depotId;
  final String displayName;
  final String personnelNumber;
  final String email;
  final String password;
  final String inviteCode;

  /// Роль, которую человек выбрал сам. Работает только как запрос: если он
  /// есть в реестре депо, роль возьмётся оттуда — реестр главнее выбора.
  final UserRole role;
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Запись реестра сотрудников депо: кому какая роль полагается.
///
/// Реестр — второй замок регистрации. Ключ подтверждает депо, реестр
/// подтверждает человека: без записи в нём ключ даёт только просмотр.
/// Заодно это способ не потерять роли при переходе на вход по почте —
/// реестр ТЧ-16 наполняется из уже существующих профилей.
/// Домены почты, с которых разрешена регистрация.
///
/// Пустой список — принимается любой адрес. Если в депо есть служебные ящики,
/// вписать сюда их домены: это бесплатный второй замок, ключ руководителя
/// перестаёт работать с посторонней почтой. Проверка идёт на устройстве, так
/// что это заслон от ошибки и от случайного человека, а не от подделки —
/// всерьёз домен проверит только сервер.
const allowedEmailDomains = <String>[];

bool emailDomainAllowed(String email) {
  if (allowedEmailDomains.isEmpty) return true;
  final at = email.lastIndexOf('@');
  if (at < 0) return false;
  final domain = email.substring(at + 1).toLowerCase();
  return allowedEmailDomains.any((allowed) => domain == allowed.toLowerCase());
}

class RosterEntry {
  const RosterEntry({required this.role, this.assignedColumnId, this.fullName});

  final UserRole role;
  final String? assignedColumnId;
  final String? fullName;

  static RosterEntry fromMap(Map<String, dynamic> map) {
    return RosterEntry(
      role: roleFromString(map['role']),
      assignedColumnId: map['assignedColumnId'] as String?,
      fullName: map['fullName'] as String?,
    );
  }

  /// Идентификатор записи: депо и табельный номер вместе, потому что
  /// табельные в разных депо повторяются.
  static String idFor(String depotId, String personnelNumber) {
    return '${depotId}_$personnelNumber';
  }
}

abstract class AppAuth {
  Stream<AppUser?> authStateChanges();

  Future<void> signIn({required String email, required String password});

  Future<void> register(RegistrationRequest request);

  Future<void> sendPasswordReset(String email);

  /// Повторная отправка письма с подтверждением адреса.
  Future<void> resendVerification();

  /// Перечитывает состояние подтверждения почты с сервера: пользователь
  /// переходит по ссылке в почтовом клиенте, а приложение об этом само
  /// не узнает. Возвращает true, если адрес уже подтверждён.
  Future<bool> refreshVerification();

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
              // Чтение профиля отклонено. Штатно так бывает при включённой
              // полной блокировке для не-разработчика — показываем экран
              // техработ, а не бесконечную загрузку. Роль разработчика
              // читается правилами всегда, поэтому сюда он не попадает.
              controller.add(
                AppUser(
                  id: user.uid,
                  email: user.email ?? '',
                  displayName: user.displayName ?? 'Пользователь',
                  role: UserRole.viewer,
                  accessBlocked: true,
                ),
              );
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

  /// Что реестр депо говорит про этот табельный номер.
  Future<RosterEntry?> _rosterEntry(
    String depotId,
    String personnelNumber,
  ) async {
    try {
      final snapshot = await firestore
          .collection('roster')
          .doc(RosterEntry.idFor(depotId, personnelNumber))
          .get();
      final data = snapshot.data();
      if (data == null) return null;
      return RosterEntry.fromMap(data);
    } catch (_) {
      // Реестр недоступен — не повод ронять регистрацию. Человек получит
      // просмотр, роль ему поднимет руководитель.
      return null;
    }
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await fb_auth.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on fb_auth.FirebaseAuthException catch (error) {
      throw AuthException(_messageFor(error));
    }
  }

  @override
  Future<void> register(RegistrationRequest request) async {
    // Ключ проверяется до создания учётной записи: иначе при неверном ключе
    // в Firebase Auth останется висеть пользователь без профиля.
    final grant = await const LocalInviteVerifier().verify(
      depotId: request.depotId,
      code: request.inviteCode,
    );

    final fb_auth.UserCredential credential;
    try {
      credential = await fb_auth.FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: request.email.trim(),
            password: request.password,
          );
    } on fb_auth.FirebaseAuthException catch (error) {
      throw AuthException(_messageFor(error));
    }

    final user = credential.user;
    if (user == null) {
      throw const AuthException('Не удалось создать учётную запись.');
    }

    // Реестр главнее выбора: если человек в нём есть, роль берём оттуда, а
    // выбранную в форме игнорируем. Нет записи — остаётся выбор, и тогда
    // единственным барьером работает ключ.
    final roster = request.personnelNumber.trim().isEmpty
        ? null
        : await _rosterEntry(grant.depotId, request.personnelNumber.trim());
    final role = roster?.role ?? request.role;

    await user.updateDisplayName(request.displayName);
    await firestore
        .collection('users')
        .doc(user.uid)
        .set(
          AppUser(
            id: user.uid,
            email: request.email.trim(),
            displayName: request.displayName,
            role: role,
            depotId: grant.depotId,
            // Инструктор без своей колонны бесполезен, поэтому привязка
            // переезжает из реестра — так роли переживают переход со
            // старого входа по табельному на вход по почте.
            assignedColumnId: roster?.assignedColumnId,
            // Права выданы, но до подтверждения почты внутрь не пускаем.
            status: AccountStatus.pending,
            personnelNumber: request.personnelNumber.trim(),
          ).toMap()
            // Галочка, которую никто не записал, ничего не доказывает.
            // Храним версию документов и время: через год иначе не
            // установить, с каким именно текстом человек соглашался.
            ..['consentVersion'] = legalDocsVersion
            ..['consentAt'] = FieldValue.serverTimestamp(),
          SetOptions(merge: true),
        );
    await user.sendEmailVerification();
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await fb_auth.FirebaseAuth.instance.sendPasswordResetEmail(
        email: email.trim(),
      );
    } on fb_auth.FirebaseAuthException catch (error) {
      throw AuthException(_messageFor(error));
    }
  }

  @override
  Future<void> resendVerification() async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await user.sendEmailVerification();
  }

  @override
  Future<bool> refreshVerification() async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    await user.reload();
    final refreshed = fb_auth.FirebaseAuth.instance.currentUser;
    final verified = refreshed?.emailVerified ?? false;
    if (verified) {
      // Почта подтверждена — снимаем ожидание, чтобы AuthGate пропустил
      // человека дальше. Проверять подтверждение правилами Firestore нельзя,
      // поэтому статус хранится в профиле.
      await firestore.collection('users').doc(refreshed!.uid).set({
        'status': AccountStatus.active.name,
      }, SetOptions(merge: true));
    }
    return verified;
  }



  String _messageFor(fb_auth.FirebaseAuthException error) {
    return switch (error.code) {
      'invalid-email' => 'Адрес почты введён неверно.',
      'user-disabled' => 'Доступ для этой учётной записи закрыт.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' => 'Неверная почта или пароль.',
      'email-already-in-use' =>
        'На эту почту уже есть учётная запись. Войдите или восстановите пароль.',
      'weak-password' => 'Пароль слишком простой — нужно не меньше 8 знаков.',
      'network-request-failed' => 'Нет связи с сервером. Проверьте интернет.',
      'too-many-requests' =>
        'Слишком много попыток подряд. Попробуйте через несколько минут.',
      _ => 'Не удалось выполнить вход: ${error.message ?? error.code}',
    };
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
  final _registered = <String, AppUser>{};
  AppUser? _user;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    final address = email.trim();
    if (address.isEmpty || password.isEmpty) {
      throw const AuthException('Введите почту и пароль.');
    }
    // Демо-режим работает без сервера: пароль не проверяется, вход открывает
    // тот профиль, который был создан регистрацией в этом же запуске.
    _user =
        _registered[address.toLowerCase()] ??
        AppUser(
          id: 'demo-$address',
          email: address,
          displayName: address,
          role: UserRole.tchm,
          depotId: MoscowDepots.all.first.id,
        );
    _controller.add(_user);
  }

  @override
  Future<void> register(RegistrationRequest request) async {
    final grant = await const LocalInviteVerifier().verify(
      depotId: request.depotId,
      code: request.inviteCode,
    );
    final address = request.email.trim();
    final user = AppUser(
      id: 'demo-$address',
      email: address,
      displayName: request.displayName,
      role: request.role,
      depotId: grant.depotId,
      personnelNumber: request.personnelNumber,
      status: AccountStatus.pending,
    );
    _registered[address.toLowerCase()] = user;
    _user = user;
    _controller.add(_user);
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> resendVerification() async {}

  @override
  Future<bool> refreshVerification() async {
    final current = _user;
    if (current == null) return false;
    // Почтового ящика в демо-режиме нет, поэтому подтверждение считается
    // полученным сразу — иначе экран ожидания не пройти.
    _user = AppUser(
      id: current.id,
      email: current.email,
      displayName: current.displayName,
      role: current.role,
      depotId: current.depotId,
      status: AccountStatus.active,
      personnelNumber: current.personnelNumber,
      assignedColumnId: current.assignedColumnId,
    );
    _registered[current.email.toLowerCase()] = _user!;
    _controller.add(_user);
    return true;
  }



  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }
}

/// Флаг обслуживания: лежит в Firestore по пути `config/app` и проверяется
/// правилами безопасности на сервере. Меняется кнопкой из аккаунта
/// разработчика, поэтому не требует ни деплоя правил, ни обновления сборок
/// у пользователей.
class AppLock {
  const AppLock({
    this.writesBlocked = false,
    this.readsBlocked = false,
    this.updatedBy = '',
  });

  final bool writesBlocked;
  final bool readsBlocked;
  final String updatedBy;

  bool get isActive => writesBlocked || readsBlocked;

  AppLock copyWith({bool? writesBlocked, bool? readsBlocked}) {
    return AppLock(
      writesBlocked: writesBlocked ?? this.writesBlocked,
      readsBlocked: readsBlocked ?? this.readsBlocked,
      updatedBy: updatedBy,
    );
  }

  Map<String, Object?> toMap(String author) {
    return {
      'writesBlocked': writesBlocked,
      'readsBlocked': readsBlocked,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
      'updatedBy': author,
    };
  }

  static AppLock fromMap(Map<String, dynamic>? map) {
    if (map == null) return const AppLock();
    return AppLock(
      writesBlocked: map['writesBlocked'] as bool? ?? false,
      readsBlocked: map['readsBlocked'] as bool? ?? false,
      updatedBy: map['updatedBy']?.toString() ?? '',
    );
  }
}

abstract class TchmRepository {
  Stream<List<ColumnGroup>> watchColumns();

  Stream<List<Machinist>> watchMachinists({String? columnId});

  /// Учётные записи. Нужны одному экрану — сводке по депо у разработчика,
  /// — поэтому обычный репозиторий отдаёт только свою: запрос ограничен
  /// депо ровно так же, как колонны и машинисты.
  Stream<List<AppUser>> watchUsers();

  /// Открывает или закрывает доступ учётным записям. Список, а не одна
  /// запись: у старого входа по табельному один человек нередко имеет
  /// несколько профилей, и закрыть надо все сразу — иначе он войдёт под
  /// оставшимся.
  Future<void> setAccountStatus({
    required List<String> userIds,
    required AccountStatus status,
    required AppUser by,
  });

  /// Удаляет профили из базы. Насовсем: отменить нельзя, и учётную запись в
  /// Firebase Auth это не трогает — вход по ней остаётся, просто профиля у
  /// него больше нет.
  Future<void> deleteAccounts({
    required List<String> userIds,
    required AppUser by,
  });

  /// Заводит колонну с указанным номером. ТЧМ в ней — тот, кто её создал:
  /// его фамилию и табельный берём из профиля, спрашивать нечего.
  Future<void> createColumn({required int number, required AppUser user});

  Future<void> seedDefaults(AppUser user);

  Future<void> saveMachinist(Machinist machinist, AppUser user);

  Future<void> deleteMachinist(Machinist machinist, AppUser user);

  Future<void> updateColumn(ColumnGroup column, AppUser user);

  Future<void> deleteColumn(ColumnGroup column, AppUser user);

  Stream<AppLock> watchLock();

  Future<void> setLock(AppLock lock, AppUser user);
}

class FirebaseTchmRepository implements TchmRepository {
  FirebaseTchmRepository(this.firestore, {this.depotId});

  final FirebaseFirestore firestore;

  /// Депо, данными которого работает этот репозиторий. Все запросы
  /// ограничены им, поэтому чужие колонны и машинисты не приходят даже в
  /// память приложения. Пусто только у разработчика — он работает поверх
  /// всех депо, и правила это ему разрешают.
  final String? depotId;

  /// Ограничивает запрос своим депо. Правила Firestore устроены так, что
  /// запрос без этого фильтра будет отклонён сервером целиком, а не
  /// отфильтрован — то есть забыть его нельзя незаметно.
  Query<Map<String, dynamic>> _scoped(String collection) {
    final Query<Map<String, dynamic>> query = firestore.collection(collection);
    if (depotId == null) return query;
    return query.where('depotId', isEqualTo: depotId);
  }

  @override
  Stream<List<ColumnGroup>> watchColumns() {
    return _scoped('columns').snapshots().map((snapshot) {
      final columns = snapshot.docs
          .map((doc) => ColumnGroup.fromMap(doc.id, doc.data()))
          .toList();
      // Сортируем на клиенте: с фильтром по депо серверная сортировка
      // потребовала бы составного индекса ради десятка документов.
      columns.sort((a, b) => a.number.compareTo(b.number));
      return columns;
    });
  }

  @override
  Stream<List<AppUser>> watchUsers() {
    return _scoped('users').snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => AppUser.fromMap(doc.id, doc.data()))
          .toList(),
    );
  }

  @override
  Future<void> setAccountStatus({
    required List<String> userIds,
    required AccountStatus status,
    required AppUser by,
  }) async {
    if (!by.role.canManageAccounts) {
      throw StateError('Закрывать доступ может администратор или разработчик.');
    }
    final batch = firestore.batch();
    for (final id in userIds) {
      batch.set(firestore.collection('users').doc(id), {
        'status': status.name,
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  @override
  Future<void> deleteAccounts({
    required List<String> userIds,
    required AppUser by,
  }) async {
    if (!by.role.canManageAccounts) {
      throw StateError('Удалять учётные записи может администратор или разработчик.');
    }
    final batch = firestore.batch();
    for (final id in userIds) {
      batch.delete(firestore.collection('users').doc(id));
    }
    await batch.commit();
  }

  @override
  Stream<List<Machinist>> watchMachinists({String? columnId}) {
    Query<Map<String, dynamic>> query = _scoped('machinists');
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

  /// Идентификатор документа колонны с префиксом депо: у каждого депо свои
  /// колонны с одинаковыми номерами, и без префикса они затирали бы друг
  /// друга. У ТЧ-16 записи созданы до мультидепо и сохраняют прежние `id` —
  /// их не трогаем, иначе потеряется связь с машинистами.
  String _columnDocId(ColumnGroup column) {
    return depotId == null ? column.id : '${depotId}_${column.id}';
  }

  @override
  Future<void> createColumn({
    required int number,
    required AppUser user,
  }) async {
    if (!user.role.canEditAny) {
      throw StateError('Создавать колонны может ТЧМ, оператор или админ.');
    }
    final depot = depotId ?? user.depotId;
    if (depot == null) {
      throw StateError('Не удалось определить депо.');
    }
    // Номер уникален внутри депо, поэтому он же и идентификатор документа:
    // так две одновременные попытки завести колонну №5 не создадут дубль.
    final ref = firestore.collection('columns').doc('${depot}_column_$number');
    final existing = await ref.get();
    if (existing.exists) {
      throw StateError('Колонна №$number в депо уже есть.');
    }
    await ref.set(
      ColumnGroup(
        id: ref.id,
        depotId: depot,
        number: number,
        title: 'Колонна №$number',
        instructorName: '',
        tchmName: user.displayName,
        tchmPersonnelNumber: user.personnelNumber ?? '',
      ).toMap(),
    );
  }

  @override
  Future<void> seedDefaults(AppUser user) async {
    if (!user.role.canEditAny) {
      throw StateError('Начальное заполнение доступно только ТЧМ/оператору.');
    }
    final batch = firestore.batch();
    for (final column in SeedData.columns) {
      batch.set(
        firestore.collection('columns').doc(_columnDocId(column)),
        column.toMap()..['depotId'] = depotId,
        SetOptions(merge: true),
      );
    }
    for (final machinist in SeedData.machinists) {
      batch.set(
        firestore.collection('machinists').doc(machinist.id),
        machinist.toMap()..['depotId'] = depotId,
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
            // Депо проставляем всегда: иначе новая запись останется без
            // привязки и выпадет из выборки собственного депо.
            depotId: machinist.depotId ?? depotId ?? user.depotId,
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
    // Раньше правка была только у разработчика, и когда ТЧМ увольнялся,
    // колонну оставалось либо заводить заново, либо ждать его. Менять там
    // нужно фамилию ведущего, а это работа самих ТЧМ депо.
    if (!user.role.canEditAny) {
      throw StateError('Изменять колонну может ТЧМ, оператор или админ.');
    }
    // Чужое депо не правим даже с правами: у разработчика репозиторий без
    // фильтра, и промах по колонне соседнего депо ничем бы не остановился.
    final target = column.depotId ?? depotId;
    if (!user.role.canManageAllDepots && target != null && target != user.depotId) {
      throw StateError('Колонна принадлежит другому депо.');
    }
    await firestore
        .collection('columns')
        .doc(column.id)
        .set(
          column.toMap()..['depotId'] = target,
          SetOptions(merge: true),
        );
  }

  @override
  Future<void> deleteColumn(ColumnGroup column, AppUser user) async {
    throw UnsupportedError('Удаление колонн доступно через основной API.');
  }

  DocumentReference<Map<String, dynamic>> get _lockDoc =>
      firestore.collection('config').doc('app');

  @override
  Stream<AppLock> watchLock() {
    return _lockDoc
        .snapshots()
        .map((doc) => AppLock.fromMap(doc.data()))
        .handleError((Object _) {});
  }

  @override
  Future<void> setLock(AppLock lock, AppUser user) async {
    if (!user.role.canManageDatabaseLock) {
      throw StateError('Режим обслуживания доступен только разработчику.');
    }
    await _lockDoc.set(lock.toMap(user.displayName), SetOptions(merge: true));
  }
}

/// Демо-репозиторий: депо не разделяет, всё живёт в памяти одного запуска.
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
  final _lockController = StreamController<AppLock>.broadcast();
  var _lock = const AppLock();

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
  Stream<List<AppUser>> watchUsers() async* {
    // В демо-режиме учётных записей нет: вход в него не создаёт профилей.
    yield const <AppUser>[];
  }

  @override
  Future<void> setAccountStatus({
    required List<String> userIds,
    required AccountStatus status,
    required AppUser by,
  }) async {
    // В демо-режиме учётных записей нет, закрывать нечего.
  }

  @override
  Future<void> deleteAccounts({
    required List<String> userIds,
    required AppUser by,
  }) async {
    // В демо-режиме учётных записей нет, удалять нечего.
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
  Future<void> createColumn({
    required int number,
    required AppUser user,
  }) async {
    if (_columns.any((column) => column.number == number)) {
      throw StateError('Колонна №$number в депо уже есть.');
    }
    _columns
      ..add(
        ColumnGroup(
          id: 'column_$number',
          depotId: user.depotId,
          number: number,
          title: 'Колонна №$number',
          instructorName: '',
          tchmName: user.displayName,
          tchmPersonnelNumber: user.personnelNumber ?? '',
        ),
      )
      ..sort((a, b) => a.number.compareTo(b.number));
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
    if (!user.role.canEditAny) {
      throw StateError('Изменять колонну может ТЧМ, оператор или админ.');
    }
    final index = _columns.indexWhere((value) => value.id == column.id);
    if (index != -1) {
      _columns[index] = column;
    }
    _emit();
  }

  @override
  Future<void> deleteColumn(ColumnGroup column, AppUser user) async {
    if (!user.role.canEditAny ||
        (!user.role.canManageAllDepots && column.depotId != user.depotId)) {
      throw StateError('Нет прав на удаление этой колонны.');
    }
    if (_lock.writesBlocked || _lock.readsBlocked) {
      throw StateError('Идут технические работы.');
    }
    if (_machinists.any((item) => item.columnId == column.id)) {
      throw StateError('Сначала перенесите машинистов в другую колонну.');
    }
    _columns.removeWhere((item) => item.id == column.id);
    _emit();
  }

  @override
  Stream<AppLock> watchLock() async* {
    yield _lock;
    yield* _lockController.stream;
  }

  @override
  Future<void> setLock(AppLock lock, AppUser user) async {
    if (!user.role.canManageDatabaseLock) {
      throw StateError('Режим обслуживания доступен только разработчику.');
    }
    _lock = lock;
    _lockController.add(lock);
  }
}

/// Экран, который видит обычный пользователь при включённой полной
/// блокировке. Данные в базе целы — закрыт только доступ из приложения.
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final deps = AppDependencies.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.engineering_outlined,
                size: 72,
                color: AppPalette.textSecondary,
              ),
              const SizedBox(height: 20),
              const Text(
                'Ведутся технические работы',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                'Доступ к приложению временно приостановлен '
                'разработчиком. Данные сохранены. Попробуйте позже.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppPalette.textSecondary),
              ),
              const SizedBox(height: 24),
              if (onRetry != null)
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Проверить доступ'),
                ),
              OutlinedButton.icon(
                onPressed: deps.auth.signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Выйти'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Проверяет режим сервера при входе и слушает последующие обновления.
class ApiMaintenanceGate extends StatefulWidget {
  const ApiMaintenanceGate({
    super.key,
    required this.repository,
    required this.user,
    required this.child,
  });

  final ApiTchmRepository repository;
  final AppUser user;
  final Widget child;

  @override
  State<ApiMaintenanceGate> createState() => _ApiMaintenanceGateState();
}

class _ApiMaintenanceGateState extends State<ApiMaintenanceGate> {
  late final Stream<AppLock> _lock = widget.repository.watchLock();
  bool _checking = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await widget.repository.refresh();
    } catch (error) {
      if (error is! ApiException || error.maintenanceLock == null) {
        _error = error;
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppLock>(
      stream: _lock,
      builder: (context, snapshot) {
        if (_checking) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (_error != null) {
          return Scaffold(
            body: Center(
              child: OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Не удалось проверить доступ. Повторить'),
              ),
            ),
          );
        }
        if (snapshot.data?.readsBlocked == true &&
            !widget.user.role.canManageDatabaseLock) {
          return MaintenanceScreen(onRetry: _refresh);
        }
        return widget.child;
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  TchmRepository? _depotRepository;
  String? _depotRepositoryFor;

  /// Репозиторий, привязанный к депо вошедшего человека: и просмотр, и
  /// правка идут только по своему депо. Держим его между перестроениями —
  /// иначе на каждый кадр пересоздавались бы подписки на Firestore.
  TchmRepository _repositoryFor(AppUser user, AppDependencies deps) {
    final base = deps.repository;
    // Разработчик работает поверх всех депо, демо-режим живёт в памяти, а у
    // нового API депо навязывает сервер по профилю — им подмена не нужна.
    if (user.role.canManageAllDepots || base is! FirebaseTchmRepository) return base;
    if (_depotRepository != null && _depotRepositoryFor == user.depotId) {
      return _depotRepository!;
    }
    _depotRepositoryFor = user.depotId;
    return _depotRepository = FirebaseTchmRepository(
      base.firestore,
      depotId: user.depotId,
    );
  }

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
        if (user != null && user.accessBlocked) {
          return const MaintenanceScreen();
        }
        if (user == null) return const LoginScreen();
        if (user.disabled) return const LoginScreen();
        if (user.awaitingApproval) {
          return AwaitingApprovalScreen(user: user);
        }
        // Профиль без депо — это либо учётная запись, созданная до перехода
        // на мультидепо, либо сбой регистрации. Показываем причину, а не
        // пустой список: данные чужого депо ему всё равно не покажут.
        if (user.depotId == null && !user.role.canManageAllDepots) {
          return DepotMissingScreen(user: user);
        }
        // Ниже по дереву все экраны получают репозиторий своего депо:
        // ближайший AppDependencies перекрывает корневой.
        final screen = user.role.canManageAllDepots
            ? DepotOverviewScreen(user: user)
            : HomeScreen(user: user);
        final repository = _repositoryFor(user, deps);
        return AppDependencies(
          repository: repository,
          auth: deps.auth,
          firebaseReady: deps.firebaseReady,
          // Разработчик работает поверх всех депо, поэтому список колонн для
          // него бессмыслен: в него сваливаются колонны всех депо разом, без
          // подписи, чьи они. Ему первым экраном — депо, колонны внутри.
          child: repository is ApiTchmRepository
              ? ApiMaintenanceGate(
                  key: ValueKey(user.id),
                  repository: repository,
                  user: user,
                  child: screen,
                )
              : screen,
        );
      },
    );
  }
}

// ВРЕМЕННО: режим для скриншотов App Store. Запуск:
// flutter run --dart-define=SHOT=0  (0 — Колонны, 1 — Колонна, 2 — Требуют внимания)
const int _shotScreen = RuntimeConfig.shot;

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

/// Фирменные цвета приложения. Палитра используется во всех депо — в шапках,
/// кнопках, номерах колонн и новом общем знаке ТЧМ.
abstract final class DepotBrand {
  /// Фон эмблемы. Экран входа заливается ровно этим цветом, поэтому края
  /// картинки не видны — она будто напечатана на самом фоне.
  static const field = Color(0xFF000713);

  /// Красный с эмблемы. Яркий, поэтому только на тонких акцентах:
  /// черта под логотипом и свечение вокруг него.
  static const red = Color(0xFFD80F10);

  /// Рабочий красный крупных поверхностей: шапки, плашки колонны, номеров
  /// и кнопок. Фирменный на всю ширину экрана слепит, поэтому взят глубже.
  static const redInk = Color(0xFFA0141A);

  /// Края градиента на номерах колонн: светлый верх, тёмный низ.
  /// Светлый край взят не с эмблемы, а глуше — иначе квадрат светится.
  static const redLight = Color(0xFFC3282F);
  static const redDeep = Color(0xFF770E13);

  static const silver = Color(0xFFE9EAEC);
  static const silverMuted = Color(0xFFBDC1CA);
  static const ok = Color(0xFF1B7F4D);
}

/// Главная кнопка фирменных экранов — в красном депо.
ButtonStyle depotPrimaryButtonStyle() => FilledButton.styleFrom(
  backgroundColor: DepotBrand.redInk,
  foregroundColor: Colors.white,
  disabledBackgroundColor: DepotBrand.redInk.withValues(alpha: 0.45),
  disabledForegroundColor: Colors.white70,
);

/// Единый знак ТЧМ для всех депо: маршрут, сходящийся в одной точке.
class _AppMark extends StatelessWidget {
  const _AppMark({this.size = 150});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset(
          'assets/brand/app_icon_1024.png',
          fit: BoxFit.cover,
          semanticLabel: 'Нормативы ТЧМ',
        ),
      ),
    );
  }
}

/// Тёмная подложка экранов входа: общий фон, знак и карточка.
class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    required this.title,
    required this.child,
    this.subtitle,
    this.onBack,
    this.showMark = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback? onBack;

  /// На регистрации знак не показываем: форма длинная, и он только
  /// отодвигает поля за край экрана.
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Экран стал светлым, поэтому значки статус-бара должны быть тёмными:
      // светлые на светлом фоне не видны.
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppPalette.background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppPalette.background,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showMark) ...[
                          const Center(child: _AppMark()),
                          const SizedBox(height: 16),
                        ],
                        const Text(
                          'ТЧМ · НОРМАТИВЫ · МАШИНИСТЫ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 2.2,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 26),
                        Container(
                          padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: AppPalette.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  if (onBack != null)
                                    IconButton(
                                      tooltip: 'Назад',
                                      onPressed: onBack,
                                      icon: const Icon(Icons.arrow_back),
                                    ),
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: AppPalette.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitle!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.4,
                                    color: AppPalette.textSecondary,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              child,
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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _loading = false;
  var _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _showError(Object error) {
    if (!mounted) return;
    final text = error is AuthException || error is InviteException
        ? '$error'
        : 'Не удалось войти: $error';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _signIn() async {
    if (_loading) return;
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      _showError(const AuthException('Введите почту и пароль.'));
      return;
    }
    setState(() => _loading = true);
    final deps = AppDependencies.of(context);
    try {
      await deps.auth.signIn(email: email, password: _password.text);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRegistration() async {
    if (_loading) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RegisterScreen()));
  }

  /// Вход через Яндекс ID.
  ///
  /// Незнакомого человека сервер не разворачивает, а выдаёт пропуск на
  /// короткую форму: почта и пароль уже не нужны, но депо, табельный и ключ
  /// спрашиваются так же, как при обычной регистрации.
  Future<void> _signInWithYandex() async {
    final auth = AppDependencies.of(context).auth;
    if (auth is! ApiAppAuth) return;
    setState(() => _loading = true);
    try {
      final ticket = await auth.authenticateWithYandex();
      if (!mounted) return;
      if (ticket.isEmpty) return; // вошёл, экран сменит AuthGate
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => YandexSignUpScreen(ticket: ticket),
        ),
      );
    } on AuthException catch (error) {
      _showError('$error');
    } catch (error) {
      _showError('Не удалось войти через Яндекс: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _showError(
        const AuthException(
          'Введите почту — на неё придёт ссылка для смены пароля.',
        ),
      );
      return;
    }
    setState(() => _loading = true);
    final deps = AppDependencies.of(context);
    try {
      await deps.auth.sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Письмо для смены пароля отправлено на $email')),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _AuthScaffold(
          title: 'Вход',
          subtitle:
              'Войдите по почте, на которую регистрировались. Если '
              'учётной записи ещё нет — зарегистрируйтесь по ключу от '
              'руководителя.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KeyboardTextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Почта',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
              ),
              const SizedBox(height: 12),
              _KeyboardTextField(
                controller: _password,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Пароль',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Показать пароль' : 'Скрыть пароль',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                onSubmitted: (_) => _signIn(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading ? null : _resetPassword,
                  child: const Text('Забыли пароль?'),
                ),
              ),
              const SizedBox(height: 4),
              FilledButton.icon(
                style: depotPrimaryButtonStyle(),
                onPressed: _loading ? null : _signIn,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.login),
                label: const Text('Войти'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _loading ? null : _openRegistration,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Зарегистрироваться'),
              ),
              // Кнопка есть только на новом сервере: у Firebase входа через
              // Яндекс нет и быть не может.
              if (AppDependencies.of(context).auth is ApiAppAuth) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _signInWithYandex,
                  icon: const Text(
                    'Я',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFFC3F1D),
                    ),
                  ),
                  label: const Text('Войти с Яндекс ID'),
                ),
              ],
            ],
          ),
        ),

        // В API обычный вход остаётся доступен и при техработах:
        // разработчик входит по почте, сервер проверяет его роль.
        StreamBuilder<AppLock>(
          stream: AppDependencies.of(context).repository.watchLock(),
          builder: (context, lockSnapshot) {
            final lock = lockSnapshot.data ?? const AppLock();
            if (AppDependencies.of(context).auth is ApiAppAuth ||
                !lock.readsBlocked) {
              return const SizedBox.shrink();
            }
            return Positioned.fill(
              child: Container(
                color: AppPalette.background,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _AppMark(size: 120),
                    const SizedBox(height: 20),
                    const Text(
                      'Ведутся технические работы',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppPalette.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Доступ к приложению временно приостановлен '
                      'разработчиком. Данные сохранены. Попробуйте позже.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.45,
                        color: AppPalette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),

                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Экран для профиля без депо: работать не с чем, но и ошибку показывать
/// незачем — человеку нужно понятное объяснение и выход.
class DepotMissingScreen extends StatelessWidget {
  const DepotMissingScreen({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final deps = AppDependencies.of(context);
    return _AuthScaffold(
      title: 'Депо не указано',
      subtitle:
          'Учётная запись есть, но она не привязана к депо, поэтому '
          'данные не открываются.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppPalette.surfaceTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppPalette.border),
            ),
            child: const Text(
              'Так бывает у записей, созданных до разделения по депо. '
              'Обратитесь к руководителю подразделения — он привяжет вас '
              'к депо, либо зарегистрируйтесь заново по ключу.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppPalette.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: depotPrimaryButtonStyle(),
            onPressed: () => deps.auth.signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}

/// Цвета линий метрополитена. В списке депо это единственное, что отличает
/// строки друг от друга с одного взгляда: линии люди помнят по цветам схемы,
/// а не по названиям.
abstract final class MetroLineColors {
  static const _byLine = <String, Color>{
    'Сокольническая': Color(0xFFEF161E),
    'Замоскворецкая': Color(0xFF2DBE2C),
    'Арбатско-Покровская': Color(0xFF0078BE),
    'Кольцевая': Color(0xFF894E35),
    'Калужско-Рижская': Color(0xFFF58631),
    'Таганско-Краснопресненская': Color(0xFF943D8F),
    'Серпуховско-Тимирязевская': Color(0xFF9A9A9A),
    'Бутовская': Color(0xFFBAC8E8),
    'Филёвская': Color(0xFF00BFFF),
    'Калининская': Color(0xFFFFCB31),
    'Солнцевская': Color(0xFFFFCB31),
    'Люблинско-Дмитровская': Color(0xFF9ACD32),
    'Некрасовская': Color(0xFFDE64A1),
    'Большая кольцевая': Color(0xFF82C0C0),
    'Троицкая': Color(0xFF1C8C4C),
    // Графитовый — цвет, выбранный голосованием на «Активном гражданине».
    // Взят темнее серого Серпуховско-Тимирязевской, иначе две серые полосы
    // в списке не различить.
    'Рублёво-Архангельская': Color(0xFF4B5157),
  };

  /// Депо с неуточнённой линией получает нейтральный серый: пустое место в
  /// колонке полос сломало бы строй списка.
  static Color of(String line) => _byLine[line] ?? DepotBrand.silverMuted;
}

/// Открывает список депо отдельным листом и возвращает выбранное.
///
/// Раньше выбор жил в выпадающем списке: белое меню поверх белой карточки,
/// строки в два этажа и никакого поиска по двум десяткам депо. Лист даёт
/// поиск, цветные полосы линий и место под нормальные строки.
Future<Depot?> showDepotPicker(BuildContext context, Depot? selected) {
  return showModalBottomSheet<Depot>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (_) => _DepotPickerSheet(selected: selected),
  );
}

class _DepotPickerSheet extends StatefulWidget {
  const _DepotPickerSheet({this.selected});

  final Depot? selected;

  @override
  State<_DepotPickerSheet> createState() => _DepotPickerSheetState();
}

class _DepotPickerSheetState extends State<_DepotPickerSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<Depot> get _visible {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return MoscowDepots.byName;
    return [
      for (final depot in MoscowDepots.byName)
        if (depot.searchText.contains(query)) depot,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final visible = _visible;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        // Лист не занимает экран целиком: полоска фона сверху показывает,
        // что под ним осталась форма регистрации.
        constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
        child: Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  decoration: BoxDecoration(
                    color: AppPalette.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Выберите депо',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Московский метрополитен · '
                            '${MoscowDepots.all.length} штатов',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppPalette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      color: AppPalette.textSecondary,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: _KeyboardTextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Название, номер ТЧ или линия',
                    hintStyle: const TextStyle(
                      color: AppPalette.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 21),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Очистить',
                            icon: const Icon(Icons.close, size: 18),
                            color: AppPalette.textSecondary,
                            onPressed: () {
                              _query.clear();
                              setState(() {});
                            },
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: AppPalette.surfaceTint,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: _searchBorder(AppPalette.surfaceTint),
                    enabledBorder: _searchBorder(AppPalette.surfaceTint),
                    focusedBorder: _searchBorder(AppPalette.accent),
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 1, color: AppPalette.border),
              Flexible(
                child: visible.isEmpty
                    ? const _DepotPickerEmpty()
                    : ListView.separated(
                        shrinkWrap: true,
                        // Жест-панель Android перекрывает низ листа: без её
                        // высоты последнее депо в списке наполовину под ней.
                        padding: EdgeInsets.only(
                          bottom: 12 + media.padding.bottom,
                        ),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          thickness: 1,
                          // Разделитель начинается там же, где название:
                          // колонка полос остаётся сплошной.
                          indent: 34,
                          endIndent: 16,
                          color: AppPalette.border,
                        ),
                        itemBuilder: (context, index) {
                          final depot = visible[index];
                          return _DepotPickerTile(
                            depot: depot,
                            selected: depot.id == widget.selected?.id,
                            onTap: () => Navigator.of(context).pop(depot),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static OutlineInputBorder _searchBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(
      color: color,
      width: color == AppPalette.accent ? 1.6 : 1,
    ),
  );
}

class _DepotPickerEmpty extends StatelessWidget {
  const _DepotPickerEmpty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 34, 24, 42),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 34, color: DepotBrand.silverMuted),
          SizedBox(height: 10),
          Text(
            'Такого депо нет',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppPalette.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Проверьте название или номер ТЧ.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppPalette.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Строка списка: полоса линии, номер ТЧ, название, линия.
class _DepotPickerTile extends StatelessWidget {
  const _DepotPickerTile({
    required this.depot,
    required this.selected,
    required this.onTap,
  });

  final Depot depot;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected
            ? DepotBrand.redInk.withValues(alpha: 0.05)
            : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 38,
              decoration: BoxDecoration(
                color: MetroLineColors.of(depot.line),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    depot.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? DepotBrand.redInk
                          : AppPalette.textPrimary,
                    ),
                  ),
                  // У депо без уточнённой линии второй строки быть не должно —
                  // иначе в списке висит одинокое «линия».
                  if (depot.line.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${depot.line} линия',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppPalette.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.check_circle,
                  size: 21,
                  color: DepotBrand.redInk,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Поле выбора депо в форме: показывает выбранное и открывает лист.
class _DepotField extends StatelessWidget {
  const _DepotField({
    required this.depot,
    required this.onChanged,
    this.enabled = true,
  });

  final Depot? depot;
  final ValueChanged<Depot> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final depot = this.depot;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled
            ? () async {
                final picked = await showDepotPicker(context, depot);
                if (picked != null) onChanged(picked);
              }
            : null,
        child: InputDecorator(
          isEmpty: depot == null,
          decoration: InputDecoration(
            labelText: 'Депо',
            hintText: 'Выберите депо',
            prefixIcon: const Icon(Icons.train_outlined),
            suffixIcon: const Icon(
              Icons.expand_more,
              color: AppPalette.textSecondary,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: depot == null
              ? const SizedBox(height: 22)
              : Row(
                  children: [
                    Container(
                      width: 4,
                      height: 20,
                      decoration: BoxDecoration(
                        color: MetroLineColors.of(depot.line),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        depot.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.textPrimary,
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

/// Галочка согласия под формой регистрации.
///
/// Названия документов — не просто текст, а ссылки: согласие, которое
/// невозможно прочитать, согласием не является.
class _ConsentCheckbox extends StatelessWidget {
  const _ConsentCheckbox({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  void _open(BuildContext context, String title, String body) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalTextScreen(title: title, body: body),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const linkStyle = TextStyle(
      fontSize: 12.5,
      height: 1.4,
      color: DepotBrand.redInk,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: DepotBrand.redInk,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 26,
          height: 26,
          child: Checkbox(
            value: value,
            activeColor: DepotBrand.redInk,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: enabled ? (next) => onChanged(next ?? false) : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppPalette.textSecondary,
                ),
                children: [
                  const TextSpan(text: 'Прочитал, '),
                  TextSpan(
                    text: 'какие данные хранит приложение',
                    style: linkStyle,
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _open(
                        context,
                        personalDataConsentTitle,
                        personalDataConsentText,
                      ),
                  ),
                  const TextSpan(text: ' и '),
                  TextSpan(
                    text: 'кто их видит',
                    style: linkStyle,
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _open(
                        context,
                        privacyPolicyTitle,
                        privacyPolicyText,
                      ),
                  ),
                  const TextSpan(text: '. Согласен на их обработку.'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Экран с текстом документа. Отдельной страницей, а не всплывающим окном:
/// текст длинный, и его должно быть удобно листать и читать целиком.
class LegalTextScreen extends StatelessWidget {
  const LegalTextScreen({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Обычный Text, а не SelectableText: на выделяемом тексте палец
            // начинает выделение вместо прокрутки, и страница уезжает вверх
            // вслед за ним — читать длинный текст становится невозможно.
            Text(
              body.trim(),
              style: const TextStyle(
                fontSize: 14,
                height: 1.55,
                color: AppPalette.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Редакция от $legalDocsVersion',
              style: const TextStyle(
                fontSize: 12,
                color: AppPalette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Короткая форма регистрации после входа через Яндекс ID.
///
/// Почты и пароля здесь нет: их заменил Яндекс, и он же подтвердил адрес.
/// Осталось то, что Яндекс знать не может, — депо, фамилия, табельный и
/// ключ руководителя. Послаблений нет: без ключа внутрь не пускают так же,
/// как и при обычной регистрации.
class YandexSignUpScreen extends StatefulWidget {
  const YandexSignUpScreen({super.key, required this.ticket});

  /// Пропуск от сервера, живёт десять минут.
  final String ticket;

  @override
  State<YandexSignUpScreen> createState() => _YandexSignUpScreenState();
}

class _YandexSignUpScreenState extends State<YandexSignUpScreen> {
  final _displayName = TextEditingController();
  final _personnelNumber = TextEditingController();
  final _inviteCode = TextEditingController();

  Depot? _depot;
  var _role = UserRole.tchm;
  var _loading = false;
  var _consent = false;

  bool get _needsPersonnelNumber => _role != UserRole.viewer;

  @override
  void dispose() {
    _displayName.dispose();
    _personnelNumber.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_depot == null) return 'Выберите депо.';
    if (_displayName.text.trim().length < 3) {
      return 'Укажите фамилию и инициалы — например, Королев М.А.';
    }
    if (_needsPersonnelNumber && _personnelNumber.text.trim().isEmpty) {
      return 'Введите табельный номер.';
    }
    if (_inviteCode.text.trim().isEmpty) {
      return 'Введите ключ, выданный руководителем подразделения.';
    }
    if (!_consent) {
      return 'Отметьте согласие на обработку данных — без него '
          'зарегистрировать нельзя.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_loading) return;
    final problem = _validate();
    if (problem != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    final auth = AppDependencies.of(context).auth;
    if (auth is! ApiAppAuth) return;
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await auth.completeYandexSignUp(
        ticket: widget.ticket,
        depotId: _depot!.id,
        displayName: _displayName.text.trim(),
        personnelNumber: _needsPersonnelNumber
            ? _personnelNumber.text.trim()
            : '',
        role: _role,
        inviteCode: _inviteCode.text,
      );
      // Дальше человека ведёт AuthGate: он уже вошёл, письма ждать не надо.
      navigator.pop();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Ещё немного',
      subtitle: 'Почту подтвердил Яндекс. Осталось указать, кто вы и в каком '
          'депо — и ввести ключ руководителя.',
      showMark: false,
      onBack: _loading ? null : () => Navigator.of(context).pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<UserRole>(
            segments: const [
              ButtonSegment(
                value: UserRole.tchm,
                label: Text('ТЧМ'),
                icon: Icon(Icons.edit_note_outlined),
              ),
              ButtonSegment(
                value: UserRole.viewer,
                label: Text('Гость'),
                icon: Icon(Icons.visibility_outlined),
              ),
            ],
            selected: {_role},
            showSelectedIcon: false,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? DepotBrand.redInk
                    : null,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white
                    : AppPalette.textPrimary,
              ),
            ),
            onSelectionChanged: _loading
                ? null
                : (selection) => setState(() => _role = selection.first),
          ),
          const SizedBox(height: 14),
          _DepotField(
            depot: _depot,
            enabled: !_loading,
            onChanged: (depot) => setState(() => _depot = depot),
          ),
          const SizedBox(height: 12),
          _KeyboardTextField(
            controller: _displayName,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Фамилия И.О.',
              hintText: 'Королев М.А.',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          if (_needsPersonnelNumber) ...[
            const SizedBox(height: 12),
            _KeyboardTextField(
              controller: _personnelNumber,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Табельный номер',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _KeyboardTextField(
            controller: _inviteCode,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
              letterSpacing: 1.1,
            ),
            decoration: const InputDecoration(
              labelText: 'Ключ',
              hintText: 'TCH16-XXXX-XXXX-XXXX',
              prefixIcon: Icon(Icons.vpn_key_outlined),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          _ConsentCheckbox(
            value: _consent,
            enabled: !_loading,
            onChanged: (value) => setState(() => _consent = value),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: depotPrimaryButtonStyle(),
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check),
            label: const Text('Готово'),
          ),
        ],
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _displayName = TextEditingController();
  final _personnelNumber = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordRepeat = TextEditingController();
  final _inviteCode = TextEditingController();

  Depot? _depot;
  var _role = UserRole.tchm;
  var _loading = false;
  var _obscure = true;

  /// Согласие на обработку персональных данных. Отдельным действием, а не
  /// «продолжая, вы соглашаетесь»: согласие должно быть активным, и без
  /// него регистрация не идёт.
  var _consent = false;

  /// Гостю табельный номер ни к чему: он ничего не редактирует.
  bool get _needsPersonnelNumber => _role != UserRole.viewer;

  /// Показываем расхождение сразу, а не после нажатия кнопки — но молчим,
  /// пока человек не начал вводить повтор.
  String? get _repeatError {
    if (_passwordRepeat.text.isEmpty) return null;
    if (_passwordRepeat.text == _password.text) return null;
    return 'Пароли не совпадают';
  }

  @override
  void dispose() {
    _displayName.dispose();
    _personnelNumber.dispose();
    _email.dispose();
    _password.dispose();
    _passwordRepeat.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Возвращает текст ошибки или null, если всё заполнено.
  String? _validate() {
    if (_depot == null) return 'Выберите депо.';
    if (_displayName.text.trim().length < 3) {
      return 'Укажите фамилию и инициалы — например, Королев М.А.';
    }
    if (_needsPersonnelNumber && _personnelNumber.text.trim().isEmpty) {
      return 'Введите табельный номер.';
    }
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      return 'Проверьте адрес почты.';
    }
    if (!emailDomainAllowed(email)) {
      return 'Регистрация только со служебной почты '
          '(${allowedEmailDomains.join(', ')}).';
    }
    if (_password.text.length < 8) {
      return 'Пароль должен быть не короче 8 знаков.';
    }
    if (_passwordRepeat.text != _password.text) {
      return 'Пароли не совпадают — проверьте оба поля.';
    }
    if (_inviteCode.text.trim().isEmpty) {
      return 'Введите ключ, выданный руководителем подразделения.';
    }
    if (!_consent) {
      return 'Отметьте согласие на обработку данных — без него '
          'зарегистрировать нельзя.';
    }
    return null;
  }

  Future<void> _register() async {
    if (_loading) return;
    final problem = _validate();
    if (problem != null) {
      _showError(problem);
      return;
    }
    setState(() => _loading = true);
    final deps = AppDependencies.of(context);
    final navigator = Navigator.of(context);
    try {
      await deps.auth.register(
        RegistrationRequest(
          depotId: _depot!.id,
          displayName: _displayName.text.trim(),
          personnelNumber: _needsPersonnelNumber
              ? _personnelNumber.text.trim()
              : '',
          email: _email.text.trim(),
          password: _password.text,
          inviteCode: _inviteCode.text,
          role: _role,
        ),
      );
      if (deps.auth is ApiAppAuth) {
        // На новом сервере регистрация не пускает внутрь: пока человек не
        // откроет ссылку из письма, входить нечем. Молча возвращать его на
        // экран входа — значит оставить в недоумении.
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Проверьте почту'),
            content: Text(
              'Отправили письмо на ${_email.text.trim()}. Откройте ссылку '
              'из него — после этого можно войти.\n\n'
              'Письмо идёт минуту-другую. Если не пришло — посмотрите в '
              'спаме или попросите его заново на экране входа.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Понятно'),
              ),
            ],
          ),
        );
      }
      // Дальше человека ведёт AuthGate: профиль создан со статусом
      // «ожидает», поэтому откроется экран подтверждения почты.
      navigator.pop();
    } on InviteException catch (error) {
      _showError('$error');
    } on AuthException catch (error) {
      _showError('$error');
    } catch (error) {
      _showError('Не удалось зарегистрироваться: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Регистрация',
      showMark: false,
      onBack: _loading ? null : () => Navigator.of(context).pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Кем регистрируетесь',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: AppPalette.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<UserRole>(
            segments: const [
              ButtonSegment(
                value: UserRole.tchm,
                label: Text('ТЧМ'),
                icon: Icon(Icons.edit_note_outlined),
              ),
              ButtonSegment(
                value: UserRole.viewer,
                label: Text('Гость'),
                icon: Icon(Icons.visibility_outlined),
              ),
            ],
            selected: {_role},
            showSelectedIcon: false,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? DepotBrand.redInk
                    : null,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white
                    : AppPalette.textPrimary,
              ),
            ),
            onSelectionChanged: _loading
                ? null
                : (selection) => setState(() => _role = selection.first),
          ),
          const SizedBox(height: 6),
          Text(
            _role == UserRole.viewer
                ? 'Гость только просматривает данные.'
                : 'ТЧМ ведёт данные машинистов своих колонн.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.3,
              color: AppPalette.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          _DepotField(
            depot: _depot,
            enabled: !_loading,
            onChanged: (depot) => setState(() => _depot = depot),
          ),
          const SizedBox(height: 12),
          _KeyboardTextField(
            controller: _displayName,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Фамилия И.О.',
              hintText: 'Королев М.А.',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          if (_needsPersonnelNumber) ...[
            const SizedBox(height: 12),
            _KeyboardTextField(
              controller: _personnelNumber,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Табельный номер',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _KeyboardTextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Почта',
              prefixIcon: Icon(Icons.alternate_email),
            ),
          ),
          const SizedBox(height: 12),
          _KeyboardTextField(
            controller: _password,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Пароль',
              helperText: 'Не короче 8 знаков',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Показать пароль' : 'Скрыть пароль',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _KeyboardTextField(
            controller: _passwordRepeat,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Повторите пароль',
              errorText: _repeatError,
              prefixIcon: const Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 12),
          _KeyboardTextField(
            controller: _inviteCode,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
              letterSpacing: 1.1,
            ),
            decoration: const InputDecoration(
              labelText: 'Ключ',
              hintText: 'TCH16-XXXX-XXXX-XXXX',
              prefixIcon: Icon(Icons.vpn_key_outlined),
            ),
            onSubmitted: (_) => _register(),
          ),
          const SizedBox(height: 16),
          _ConsentCheckbox(
            value: _consent,
            enabled: !_loading,
            onChanged: (value) => setState(() => _consent = value),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: depotPrimaryButtonStyle(),
            onPressed: _loading ? null : _register,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.person_add_alt),
            label: const Text('Зарегистрироваться'),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 15,
                color: AppPalette.textSecondary,
              ),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Ключ выдаёт руководитель подразделения.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppPalette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Экран между регистрацией и работой: ждём подтверждения почты.
class AwaitingApprovalScreen extends StatefulWidget {
  const AwaitingApprovalScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<AwaitingApprovalScreen> createState() => _AwaitingApprovalScreenState();
}

class _AwaitingApprovalScreenState extends State<AwaitingApprovalScreen> {
  var _loading = false;

  Future<void> _check() async {
    setState(() => _loading = true);
    final deps = AppDependencies.of(context);
    try {
      final verified = await deps.auth.refreshVerification();
      if (!mounted) return;
      if (!verified) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Почта пока не подтверждена. Проверьте письмо.'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    final deps = AppDependencies.of(context);
    try {
      await deps.auth.resendVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Письмо отправлено на ${widget.user.email}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppDependencies.of(context);
    return _AuthScaffold(
      title: 'Подтвердите почту',
      subtitle:
          'Мы отправили письмо на ${widget.user.email}. Перейдите по '
          'ссылке из письма и вернитесь сюда.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppPalette.surfaceTint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppPalette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryRow(label: 'Депо', value: widget.user.depotTitle),
                _SummaryRow(label: 'ФИО', value: widget.user.displayName),
                _SummaryRow(
                  label: 'Табельный',
                  value: widget.user.personnelNumber ?? '—',
                ),
                _SummaryRow(label: 'Роль', value: widget.user.role.title),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: depotPrimaryButtonStyle(),
            onPressed: _loading ? null : _check,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
            label: const Text('Я подтвердил почту'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loading ? null : _resend,
            icon: const Icon(Icons.mail_outline),
            label: const Text('Отправить письмо ещё раз'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => deps.auth.signOut(),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}

/// Депо без колонн: объясняем, что делать, и даём кнопку тому, кто может.
class _EmptyColumnsCard extends StatelessWidget {
  const _EmptyColumnsCard({required this.canCreate, required this.onCreate});

  final bool canCreate;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          const Icon(
            Icons.view_column_outlined,
            size: 52,
            color: AppPalette.textSecondary,
          ),
          const SizedBox(height: 14),
          Text(
            'В депо ещё нет колонн',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              canCreate
                  ? 'Создайте свою колонну — укажите её номер, ТЧМ подставится '
                        'из вашего профиля.'
                  : 'Колонны заводит ТЧМ. Как только он их создаст, они '
                        'появятся здесь.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                height: 1.4,
                color: AppPalette.textSecondary,
              ),
            ),
          ),
          if (canCreate) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              style: depotPrimaryButtonStyle(),
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Создать колонну'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Создание колонны: номер вводит ТЧМ, всё остальное подставляется само.
class _CreateColumnDialog extends StatefulWidget {
  const _CreateColumnDialog({required this.takenNumbers});

  final Set<int> takenNumbers;

  @override
  State<_CreateColumnDialog> createState() => _CreateColumnDialogState();
}

class _CreateColumnDialogState extends State<_CreateColumnDialog> {
  final _number = TextEditingController();

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  String? get _error {
    final text = _number.text.trim();
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    if (value == null) return 'Номер — это число';
    if (value < 1 || value > 99) return 'Номер от 1 до 99';
    if (widget.takenNumbers.contains(value)) {
      return 'Колонна №$value уже есть';
    }
    return null;
  }

  bool get _canSubmit {
    final value = int.tryParse(_number.text.trim());
    return value != null && _error == null;
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(int.parse(_number.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новая колонна'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KeyboardTextField(
            controller: _number,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Номер колонны',
              errorText: _error,
              prefixIcon: const Icon(Icons.tag),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'ТЧМ колонны — вы. Подпись подставится из вашего профиля.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppPalette.textSecondary,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          style: depotPrimaryButtonStyle(),
          onPressed: _canSubmit ? _submit : null,
          child: const Text('Создать'),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppPalette.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppPalette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Сводка по всем депо. Экран только для разработчика: он один работает
/// поверх депо, у остальных репозиторий отфильтрован своим и все числа здесь
/// сошлись бы к одной строке.
///
/// Раньше данные всех депо приходили разработчику одним плоским списком
/// колонн, отсортированным по номеру: колонна №1 Митина и №1 Сокола стояли
/// рядом и ничем не отличались. Здесь они наконец разложены по депо.
class DepotOverviewScreen extends StatelessWidget {
  const DepotOverviewScreen({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final deps = AppDependencies.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Депо'),
        actions: [
          if (user.role.canManageDatabaseLock)
            StreamBuilder<AppLock>(
              stream: deps.repository.watchLock(),
              builder: (context, lockSnapshot) {
                final lock = lockSnapshot.data ?? const AppLock();
                return IconButton(
                  tooltip: 'Режим обслуживания',
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ServiceLockDialog(user: user, lock: lock),
                  ),
                  icon: Icon(
                    lock.isActive ? Icons.lock_outline : Icons.lock_open_outlined,
                    color: lock.isActive ? const Color(0xFFFFD166) : null,
                  ),
                );
              },
            ),
          IconButton(
            tooltip: 'Выйти',
            onPressed: deps.auth.signOut,
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: StreamBuilder<List<ColumnGroup>>(
        stream: deps.repository.watchColumns(),
        builder: (context, columnsSnapshot) {
          return StreamBuilder<List<Machinist>>(
            stream: deps.repository.watchMachinists(),
            builder: (context, machinistsSnapshot) {
              return StreamBuilder<List<AppUser>>(
                stream: deps.repository.watchUsers(),
                builder: (context, usersSnapshot) {
                  final waiting =
                      columnsSnapshot.connectionState ==
                          ConnectionState.waiting ||
                      machinistsSnapshot.connectionState ==
                          ConnectionState.waiting ||
                      usersSnapshot.connectionState == ConnectionState.waiting;
                  if (waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rows = _DepotStats.build(
                    columns: columnsSnapshot.data ?? const <ColumnGroup>[],
                    machinists: machinistsSnapshot.data ?? const <Machinist>[],
                    users: usersSnapshot.data ?? const <AppUser>[],
                  );
                  return _DepotOverviewList(rows: rows, user: user);
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Числа по одному депо.
class _DepotStats {
  const _DepotStats({
    required this.depotId,
    required this.title,
    required this.line,
    required this.columns,
    required this.tchm,
    required this.machinists,
    this.orphan = false,
  });

  final String depotId;
  final String title;
  final String line;
  final int columns;
  final int tchm;
  final int machinists;

  /// Строка-сборник для записей без депо: у них `depotId` пустой или чужой.
  /// Такие остались от времён до разделения по депо — их проставляет скрипт
  /// миграции, и пока он не отработал, их надо видеть.
  final bool orphan;

  bool get isEmpty => columns == 0 && tchm == 0 && machinists == 0;

  /// Собирает строки: сперва все известные депо, затем — сборная строка для
  /// записей, чьё депо в справочнике не значится.
  static List<_DepotStats> build({
    required List<ColumnGroup> columns,
    required List<Machinist> machinists,
    required List<AppUser> users,
  }) {
    final known = {for (final depot in MoscowDepots.all) depot.id};
    String key(String? id) =>
        (id != null && known.contains(id)) ? id : _orphanKey;

    final columnsBy = <String, int>{};
    for (final column in columns) {
      final id = key(column.depotId);
      columnsBy[id] = (columnsBy[id] ?? 0) + 1;
    }
    final machinistsBy = <String, int>{};
    for (final machinist in machinists) {
      final id = key(machinist.depotId);
      machinistsBy[id] = (machinistsBy[id] ?? 0) + 1;
    }
    final tchmBy = <String, int>{};
    for (final account in users) {
      if (account.role != UserRole.tchm) continue;
      final id = key(account.depotId);
      tchmBy[id] = (tchmBy[id] ?? 0) + 1;
    }

    final rows = [
      for (final depot in MoscowDepots.byName)
        _DepotStats(
          depotId: depot.id,
          title: depot.title,
          line: depot.line,
          columns: columnsBy[depot.id] ?? 0,
          tchm: tchmBy[depot.id] ?? 0,
          machinists: machinistsBy[depot.id] ?? 0,
        ),
    ];
    // Депо с данными наверх, и чем больше машинистов, тем выше: разработчик
    // приходит сюда смотреть, где что происходит, а не читать алфавит.
    rows.sort((a, b) {
      final byMachinists = b.machinists.compareTo(a.machinists);
      if (byMachinists != 0) return byMachinists;
      final byColumns = b.columns.compareTo(a.columns);
      if (byColumns != 0) return byColumns;
      return a.title.compareTo(b.title);
    });

    final orphan = _DepotStats(
      depotId: _orphanKey,
      title: 'Без депо',
      line: '',
      columns: columnsBy[_orphanKey] ?? 0,
      tchm: tchmBy[_orphanKey] ?? 0,
      machinists: machinistsBy[_orphanKey] ?? 0,
      orphan: true,
    );
    return [if (!orphan.isEmpty) orphan, ...rows];
  }

  static const _orphanKey = '';
}

class _DepotOverviewList extends StatelessWidget {
  const _DepotOverviewList({required this.rows, required this.user});

  final List<_DepotStats> rows;
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final filled = rows.where((row) => !row.isEmpty).toList();
    final empty = rows.where((row) => row.isEmpty).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        _DepotTotals(rows: rows),
        const SizedBox(height: 14),
        for (final row in filled) ...[
          _DepotStatsTile(
            stats: row,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DepotColumnsScreen(
                  user: user,
                  depotId: row.orphan ? null : row.depotId,
                  title: row.title,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (empty.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                'ПУСТО',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(child: Divider(color: AppPalette.border)),
            ],
          ),
          const SizedBox(height: 10),
          for (final row in empty) ...[
            _DepotStatsTile(stats: row, onTap: () {}),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

/// Шапка сводки: сколько депо уже работает и сколько всего записей.
class _DepotTotals extends StatelessWidget {
  const _DepotTotals({required this.rows});

  final List<_DepotStats> rows;

  @override
  Widget build(BuildContext context) {
    var columns = 0;
    var tchm = 0;
    var machinists = 0;
    var working = 0;
    for (final row in rows) {
      columns += row.columns;
      tchm += row.tchm;
      machinists += row.machinists;
      if (!row.isEmpty && !row.orphan) working += 1;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppPalette.deep,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Штаты с данными: $working из ${MoscowDepots.all.length}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _TotalCell(
                value: columns,
                label: pluralRu(columns, 'колонна', 'колонны', 'колонн'),
              ),
              // ТЧМ не склоняется: это сокращение, а не слово.
              _TotalCell(value: tchm, label: 'ТЧМ'),
              _TotalCell(
                value: machinists,
                label: pluralRu(
                  machinists,
                  'машинист',
                  'машиниста',
                  'машинистов',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalCell extends StatelessWidget {
  const _TotalCell({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: DepotBrand.silverMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _DepotStatsTile extends StatelessWidget {
  const _DepotStatsTile({required this.stats, required this.onTap});

  final _DepotStats stats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = stats.isEmpty;
    final tile = Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: stats.orphan ? AppPalette.warning : AppPalette.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 38,
            decoration: BoxDecoration(
              color: stats.orphan
                  ? AppPalette.warning
                  : MetroLineColors.of(stats.line),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stats.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: muted
                        ? AppPalette.textSecondary
                        : AppPalette.textPrimary,
                  ),
                ),
                if (stats.line.isNotEmpty || stats.orphan) ...[
                  const SizedBox(height: 2),
                  Text(
                    stats.orphan
                        ? 'записи без привязки к депо'
                        : '${stats.line} линия',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppPalette.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _StatCell(value: stats.columns, label: 'кол.', muted: muted),
          _StatCell(value: stats.tchm, label: 'ТЧМ', muted: muted),
          _StatCell(value: stats.machinists, label: 'маш.', muted: muted),
          // У пустой строки стрелки нет: она никуда не ведёт, и обещать
          // переход нечем.
          Icon(
            Icons.chevron_right,
            size: 20,
            color: muted ? Colors.transparent : DepotBrand.silverMuted,
          ),
        ],
      ),
    );
    // Пустое депо открывать незачем — смотреть там нечего, и нажатие
    // впустую выглядит как поломка.
    if (muted) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: tile,
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.value,
    required this.label,
    required this.muted,
  });

  final int value;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: muted ? DepotBrand.silverMuted : AppPalette.textPrimary,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppPalette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Одно депо изнутри — вид разработчика из сводки: колонны и учётные записи
/// двумя вкладками.
///
/// Репозиторий у него не отфильтрован, поэтому отбираем депо здесь же, на
/// клиенте: заводить ради просмотра второй, суженный репозиторий значило бы
/// поднимать вторую подписку на те же документы.
class DepotColumnsScreen extends StatelessWidget {
  const DepotColumnsScreen({
    super.key,
    required this.user,
    required this.depotId,
    required this.title,
  });

  final AppUser user;

  /// Депо, чьи колонны показываем. Пусто — сборная строка «Без депо»:
  /// записи, которым депо ещё не проставили.
  final String? depotId;

  final String title;

  bool _mine(String? id) {
    if (depotId != null) return id == depotId;
    return id == null || !MoscowDepots.all.any((depot) => depot.id == id);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Колонны'),
              Tab(text: 'Учётные записи'),
            ],
          ),
        ),
        body: TabBarView(
          // TabBarView может удалить неактивную вкладку и создать её заново.
          // Создаём StreamBuilder вместе с вкладкой: поток async* допускает
          // только одну подписку и не может переиспользоваться после удаления.
          children: [
            Builder(builder: _columns),
            Builder(builder: _accounts),
          ],
        ),
      ),
    );
  }

  Widget _columns(BuildContext context) {
    final deps = AppDependencies.of(context);
    return StreamBuilder<List<ColumnGroup>>(
      stream: deps.repository.watchColumns(),
      builder: (context, columnsSnapshot) {
        return StreamBuilder<List<Machinist>>(
          stream: deps.repository.watchMachinists(),
          builder: (context, machinistsSnapshot) {
            final waiting =
                columnsSnapshot.connectionState == ConnectionState.waiting ||
                machinistsSnapshot.connectionState == ConnectionState.waiting;
            if (waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final columns = [
              for (final column in columnsSnapshot.data ?? const <ColumnGroup>[])
                if (_mine(column.depotId)) column,
            ];
            final machinists = [
              for (final machinist
                  in machinistsSnapshot.data ?? const <Machinist>[])
                if (_mine(machinist.depotId)) machinist,
            ];
            if (columns.isEmpty) {
              return _DepotColumnsEmpty(machinists: machinists.length);
            }
            return RefreshIndicator(
              color: DepotBrand.redInk,
              onRefresh: () async {
                if (deps.repository is ApiTchmRepository) {
                  await (deps.repository as ApiTchmRepository).refresh();
                }
              },
              child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _ColumnsPane(
                  user: user,
                  columns: columns,
                  selectedColumnId: null,
                  machinists: machinists,
                  onSelected: (id) {
                    final column = columns.firstWhere((item) => item.id == id);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ColumnDetailScreen(
                          user: user,
                          column: column,
                          columns: columns,
                        ),
                      ),
                    );
                  },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Учётные записи выбранного депо.
  Widget _accounts(BuildContext context) {
    final deps = AppDependencies.of(context);
    return StreamBuilder<List<AppUser>>(
      stream: deps.repository.watchUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final accounts = [
          for (final account in snapshot.data ?? const <AppUser>[])
            if (_mine(account.depotId)) account,
        ]..sort((a, b) => a.displayName.compareTo(b.displayName));
        if (accounts.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Учётных записей нет',
                style: TextStyle(color: AppPalette.textSecondary),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: accounts.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            return _AccountTile(
              account: accounts[index],
              all: accounts,
              by: user,
            );
          },
        );
      },
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.all,
    required this.by,
  });

  final AppUser account;

  /// Все записи депо: нужны, чтобы найти двойников по табельному номеру.
  final List<AppUser> all;

  /// Кто закрывает доступ. Кнопка есть только у разработчика.
  final AppUser by;

  /// Профили того же человека: один табельный номер — один человек, сколько
  /// бы анонимных входов ни наплодил старый вход.
  List<AppUser> get _sames {
    final personnel = account.personnelNumber ?? '';
    if (personnel.isEmpty) return [account];
    return [
      for (final other in all)
        if ((other.personnelNumber ?? '') == personnel) other,
    ];
  }

  Future<void> _toggle(BuildContext context) async {
    final sames = _sames;
    final closing = !account.disabled;
    final deps = AppDependencies.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(closing ? 'Закрыть доступ?' : 'Открыть доступ?'),
        content: Text(
          closing
              ? '${account.displayName}: доступ закроется '
                    '${sames.length > 1 ? 'у всех ${sames.length} записей '
                          'с этим табельным номером' : 'к этой записи'}. '
                    'Войти станет нельзя, данные останутся на месте.'
              : '${account.displayName}: доступ откроется снова '
                    '${sames.length > 1 ? 'у всех ${sames.length} записей'
                          : 'к этой записи'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: closing
                ? FilledButton.styleFrom(backgroundColor: AppPalette.danger)
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(closing ? 'Закрыть' : 'Открыть'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await deps.repository.setAccountStatus(
        userIds: [for (final item in sames) item.id],
        status: closing ? AccountStatus.disabled : AccountStatus.active,
        by: by,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            closing
                ? 'Доступ закрыт: ${account.displayName}'
                : 'Доступ открыт: ${account.displayName}',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не получилось: $error')),
      );
    }
  }

  /// Удаление профилей. Отдельным подтверждением, где прямо сказано, чего
  /// оно НЕ делает: учётная запись в Firebase Auth остаётся, и человек с ней
  /// сможет войти снова — просто без профиля.
  Future<void> _delete(BuildContext context) async {
    final sames = _sames;
    final deps = AppDependencies.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить из базы?'),
        content: Text(
          '${account.displayName}: будет удалено '
          '${sames.length > 1 ? '${sames.length} записей' : '1 запись'} '
          'из коллекции users. Отменить нельзя.\n\n'
          'Учётная запись входа при этом остаётся — если человек войдёт '
          'снова, профиль создастся заново. Чтобы закрыть доступ насовсем, '
          'надёжнее не удалять, а закрыть доступ: закрытая запись помнит, '
          'что она закрыта, а удалённая — нет.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.danger,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await deps.repository.deleteAccounts(
        userIds: [for (final item in sames) item.id],
        by: by,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Удалено: ${account.displayName}')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Не получилось: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  account.displayName.isEmpty
                      ? 'Без имени'
                      : account.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary,
                  ),
                ),
              ),
              _AccountBadge(
                text: account.role.title,
                color: account.role.canEditAny
                    ? DepotBrand.redInk
                    : AppPalette.textSecondary,
              ),
              if (by.role.canManageAccounts &&
                  by.id != account.id &&
                  !account.role.isDeveloper) ...[
                IconButton(
                  tooltip: account.disabled
                      ? 'Открыть доступ'
                      : 'Закрыть доступ',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _toggle(context),
                  icon: Icon(
                    account.disabled ? Icons.lock_open_outlined : Icons.block,
                    size: 20,
                    color: account.disabled
                        ? DepotBrand.ok
                        : AppPalette.danger,
                  ),
                ),
                IconButton(
                  tooltip: 'Удалить из базы',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _delete(context),
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppPalette.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          _AccountBadge(
            text: account.status == AccountStatus.pending
                ? 'ждёт подтверждения'
                : account.status == AccountStatus.disabled
                ? 'отключена'
                : 'активна',
            color: account.status == AccountStatus.active
                ? DepotBrand.ok
                : AppPalette.warning,
          ),
        ],
      ),
    );
  }
}

class _AccountBadge extends StatelessWidget {
  const _AccountBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Колонн нет, но машинисты быть могут: у записи проставлено депо, а колонна
/// потерялась. Молчать об этом нельзя — это и есть поломка, которую
/// разработчик сюда пришёл искать.
class _DepotColumnsEmpty extends StatelessWidget {
  const _DepotColumnsEmpty({required this.machinists});

  final int machinists;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.dashboard_outlined,
              size: 36,
              color: DepotBrand.silverMuted,
            ),
            const SizedBox(height: 12),
            const Text(
              'Колонн нет',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppPalette.textPrimary,
              ),
            ),
            if (machinists > 0) ...[
              const SizedBox(height: 6),
              Text(
                'При этом машинистов здесь $machinists: они привязаны к '
                'колоннам, которых в этом депо нет.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: AppPalette.warning,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();

  /// Заводит колонну: спрашиваем только номер, остальное известно — депо и
  /// ТЧМ берём из профиля того, кто её создаёт.
  Future<void> _createColumn(List<ColumnGroup> columns) async {
    final taken = columns.map((column) => column.number).toSet();
    final number = await showDialog<int>(
      context: context,
      builder: (_) => _CreateColumnDialog(takenNumbers: taken),
    );
    if (number == null || !mounted) return;
    final deps = AppDependencies.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await deps.repository.createColumn(number: number, user: widget.user);
      messenger.showSnackBar(
        SnackBar(content: Text('Колонна №$number создана')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось создать колонну: $error')),
      );
    }
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
        // Раньше при пустой базе подставлялись 12 колонн из SeedData — это
        // колонны ТЧ-16 с их фамилиями, и в любом другом депо они чужие.
        // Пустое депо теперь так и показывается пустым.
        final columns = firestoreColumns;
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
                      // На красной шапке красная плашка не читается —
                      // выворачиваем цвета.
                      backgroundColor: Colors.white,
                      textColor: DepotBrand.redInk,
                      label: Text('$attentionTotal'),
                      child: const Icon(Icons.warning_amber_rounded),
                    ),
                  ),
                  if (widget.user.role.canManageDatabaseLock)
                    StreamBuilder<AppLock>(
                      stream: deps.repository.watchLock(),
                      builder: (context, lockSnapshot) {
                        final lock = lockSnapshot.data ?? const AppLock();
                        return IconButton(
                          tooltip: 'Режим обслуживания',
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => ServiceLockDialog(
                              user: widget.user,
                              lock: lock,
                            ),
                          ),
                          icon: Icon(
                            lock.isActive
                                ? Icons.lock_outline
                                : Icons.lock_open_outlined,
                            color: lock.isActive
                                ? const Color(0xFFFFD166)
                                : null,
                          ),
                        );
                      },
                    ),
                  if (widget.user.role.canEditAny && columns.isNotEmpty)
                    IconButton(
                      tooltip: 'Создать колонну',
                      onPressed: () => _createColumn(columns),
                      icon: const Icon(Icons.add),
                    ),
                  IconButton(
                    tooltip: 'Выйти',
                    onPressed: deps.auth.signOut,
                    icon: const Icon(Icons.logout),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              body: RefreshIndicator(
                color: DepotBrand.redInk,
                // Живого потока на новом сервере нет: список читается при
                // открытии экрана и вот этим жестом.
                onRefresh: () async {
                  final repository = deps.repository;
                  if (repository is ApiTchmRepository) {
                    await repository.refresh();
                  }
                },
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  children: [
                    const MaintenanceBanner(),
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
                  // Пустое депо: колонн ещё нет, их заводит ТЧМ вручную.
                  // Шаблонные 12 колонн больше не создаются — они были с
                  // фамилиями ТЧ-16 и в другом депо оказывались чужими.
                  if (query.isEmpty && columns.isEmpty)
                    _EmptyColumnsCard(
                      canCreate: widget.user.role.canEditAny,
                      onCreate: () => _createColumn(columns),
                    )
                  else if (query.isEmpty)
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
              ),
            );
          },
        );
      },
    );
  }
}

/// Переключатель режима обслуживания. Пишет флаг в `config/app`; запрет
/// применяют правила Firestore на сервере, поэтому действует на все уже
/// установленные сборки без обновления.
class ServiceLockDialog extends StatefulWidget {
  const ServiceLockDialog({super.key, required this.user, required this.lock});

  final AppUser user;
  final AppLock lock;

  @override
  State<ServiceLockDialog> createState() => _ServiceLockDialogState();
}

class _ServiceLockDialogState extends State<ServiceLockDialog> {
  late AppLock _lock = widget.lock;
  var _saving = false;

  Future<void> _apply(AppLock next) async {
    if (!mounted) return;
    setState(() {
      _lock = next;
      _saving = true;
    });
    try {
      await AppDependencies.of(context).repository.setLock(next, widget.user);
    } catch (error) {
      if (!mounted) return;
      setState(() => _lock = widget.lock);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить режим: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmBlackout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Скрыть данные у всех?'),
        content: const Text(
          'Приложение перестанет открываться у всех пользователей, включая '
          'тех, кто сейчас на смене. Данные в базе останутся целы.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Скрыть'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Режим обслуживания'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _lock.writesBlocked,
            onChanged: _saving
                ? null
                : (value) => _apply(_lock.copyWith(writesBlocked: value)),
            title: const Text('Только просмотр'),
            subtitle: const Text(
              'Данные видны, но изменения по машинистам не сохраняются.',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _lock.readsBlocked,
            onChanged: _saving
                ? null
                : (value) async {
                    if (value && !await _confirmBlackout()) return;
                    await _apply(_lock.copyWith(readsBlocked: value));
                  },
            title: const Text('Полная блокировка'),
            subtitle: const Text(
              'Приложение не открывается ни у кого, кроме разработчика.',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _lock.isActive
                ? 'Режим обслуживания включён. Данные в базе не тронуты.'
                : 'Приложение работает в обычном режиме.',
            style: TextStyle(
              color: _lock.isActive
                  ? AppPalette.danger
                  : AppPalette.textSecondary,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка создания PDF: $e')));
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
                _ColumnActionBar(
                  column: widget.column,
                  canExport: widget.user.role.canExportData,
                  onShare: () => _handleShare(allMachinists),
                  onSave: Platform.isAndroid
                      ? () => _handleSaveAndroid(allMachinists)
                      : null,
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
              // Только значок: подпись повторяла очевидное и занимала
              // треть ширины экрана. Смысл действия остаётся в подсказке
              // по долгому нажатию и в озвучке для скринридера.
              ? FloatingActionButton(
                  onPressed: _openEditor,
                  tooltip: 'Добавить машиниста',
                  child: const Icon(Icons.person_add_alt),
                )
              : null,
        );
      },
    );
  }
}

/// Компактная плашка колонны: номер, название и выгрузка в PDF.
///
/// ТЧМ и инструктор здесь не повторяются — они уже видны в списке колонн,
/// а плашка нужна прежде всего ради кнопок выгрузки.
///
/// Гостю кнопок не показываем: «только просмотр» не должно означать
/// «просмотр и вынести колонну наружу одним файлом».
class _ColumnActionBar extends StatelessWidget {
  const _ColumnActionBar({
    required this.column,
    required this.canExport,
    required this.onShare,
    this.onSave,
  });

  final ColumnGroup column;
  final bool canExport;
  final VoidCallback onShare;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: DepotBrand.redInk,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: DepotBrand.redInk.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: Text(
              '${column.number}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              column.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          if (canExport) ...[
            _PdfAction(
              icon: Icons.ios_share,
              tooltip: 'Поделиться PDF',
              onPressed: onShare,
            ),
            if (onSave != null) ...[
              const SizedBox(width: 6),
              _PdfAction(
                icon: Icons.download_rounded,
                tooltip: 'Сохранить PDF',
                onPressed: onSave!,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Кнопка выгрузки на красной плашке: своя подложка, чтобы читалась
/// как кнопка, а не как значок на фоне.
class _PdfAction extends StatelessWidget {
  const _PdfAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(child: Icon(icon, size: 19, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

class _StatusCountBadge extends StatelessWidget {
  const _StatusCountBadge({required this.status, required this.count});

  final CheckStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    // В карточке колонны статусы должны читаться как спокойные счётчики,
    // а не как ещё одна яркая кнопка рядом с номером колонны.
    final (foreground, background) = switch (status) {
      CheckStatus.overdue => (const Color(0xFFC65A61), const Color(0xFFFCEDEF)),
      CheckStatus.soon => (const Color(0xFFD09A24), const Color(0xFFFFF6DE)),
      _ => (AppPalette.textSecondary, AppPalette.surfaceTint),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(checkStatusIcon(status), size: 12, color: foreground),
          const SizedBox(width: 2),
          Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// Полоса режима обслуживания для прокручиваемого списка.
///
/// Поток создаётся в состоянии, а не в `build` родителя: список выбрасывает
/// уехавший за край элемент и потом собирает его заново из того же виджета,
/// а повторная подписка на однократный поток роняет экран.
class MaintenanceBanner extends StatefulWidget {
  const MaintenanceBanner({super.key});

  @override
  State<MaintenanceBanner> createState() => _MaintenanceBannerState();
}

class _MaintenanceBannerState extends State<MaintenanceBanner> {
  Stream<AppLock>? _lock;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lock ??= AppDependencies.of(context).repository.watchLock();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppLock>(
      stream: _lock,
      builder: (context, snapshot) {
        final lock = snapshot.data ?? const AppLock();
        if (!lock.writesBlocked) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppPalette.danger.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppPalette.danger.withValues(alpha: 0.4)),
          ),
          child: const Row(
            children: [
              Icon(Icons.build_circle_outlined, color: AppPalette.danger),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Идут технические работы. Изменение данных '
                  'временно недоступно, доступен только просмотр.',
                  style: TextStyle(color: AppPalette.danger),
                ),
              ),
            ],
          ),
        );
      },
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
    // Список без общей обёртки: карточка внутри карточки давала двойную
    // рамку и лишнее поле по краям. Каждая строка лежит на фоне сама.
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: columns.length,
      // Зазор минимальный: тени карточек не должны наезжать друг на друга,
      // но список читается как список, а не как отдельно летящие плитки.
      separatorBuilder: (_, _) => const SizedBox(height: 5),
      itemBuilder: (context, index) {
        final column = columns[index];
        final selected = column.id == selectedColumnId;
        final columnMachinists = machinists
            .where((item) => item.columnId == column.id)
            .toList();
        final count = columnMachinists.length;
        final overdueCount = columnMachinists
            .where(
              (item) => machinistOverallStatus(item) == CheckStatus.overdue,
            )
            .length;
        final soonCount = columnMachinists
            .where((item) => machinistOverallStatus(item) == CheckStatus.soon)
            .length;
        // Радиус общий с подложкой свайп-действий, см. [kColumnCardRadius].
        final radius = BorderRadius.circular(kColumnCardRadius);
        final card = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F1B1D20),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: selected ? AppPalette.surfaceTint : Colors.white,
            borderRadius: radius,
            child: InkWell(
              borderRadius: radius,
              onTap: () => onSelected(column.id),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 20, 10),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: selected ? AppPalette.accent : AppPalette.border,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [DepotBrand.redLight, DepotBrand.redDeep],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${column.number}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
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
                    const SizedBox(width: 6),
                    if (overdueCount > 0) ...[
                      _StatusCountBadge(
                        status: CheckStatus.overdue,
                        count: overdueCount,
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (soonCount > 0) ...[
                      _StatusCountBadge(
                        status: CheckStatus.soon,
                        count: soonCount,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.surfaceTint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: AppPalette.deep,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        // Инструктору правка колонны не нужна: он ведёт машинистов своей,
        // а кто её ведёт — решают ТЧМ.
        if (!user.role.canEditAny) return card;
        return ColumnActions(
          key: ValueKey('column-edit-${column.id}'),
          onEdit: () => _editColumn(context, column),
          onDelete: () => _deleteColumn(context, column, count),
          child: card,
        );
      },
    );
  }

  Future<void> _deleteColumn(
    BuildContext context,
    ColumnGroup column,
    int machinistCount,
  ) async {
    final repository = AppDependencies.of(context).repository;
    final messenger = ScaffoldMessenger.of(context);
    if (machinistCount > 0) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Сначала перенесите машинистов в другую колонну.'),
      ));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить «${column.title}»?'),
        content: const Text('Пустая колонна будет удалена. Отменить это действие нельзя.'),
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
      await repository.deleteColumn(column, user);
      messenger.showSnackBar(SnackBar(content: Text('${column.title} удалена')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось удалить: $error')));
    }
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

class _ColumnEditorDialog extends StatefulWidget {
  const _ColumnEditorDialog({required this.column});

  final ColumnGroup column;

  @override
  State<_ColumnEditorDialog> createState() => _ColumnEditorDialogState();
}

class _ColumnEditorDialogState extends State<_ColumnEditorDialog> {
  late final TextEditingController _tchmName;
  late final TextEditingController _tchmNumber;

  @override
  void initState() {
    super.initState();
    _tchmName = TextEditingController(text: widget.column.tchmName);
    _tchmNumber = TextEditingController(
      text: widget.column.tchmPersonnelNumber,
    );
  }

  @override
  void dispose() {
    _tchmName.dispose();
    _tchmNumber.dispose();
    super.dispose();
  }

  /// Инструктора здесь нет намеренно. Это свободный текст, который ни на
  /// что не влияет: права инструктора живут в его профиле, в
  /// `assignedColumnId`, а не в этой строке. Править колонну — значит
  /// указать, кто её ведёт; уже записанный текст сохраняется как есть.
  void _save() {
    Navigator.of(context).pop(
      widget.column.copyWith(
        tchmName: _tchmName.text.trim(),
        tchmPersonnelNumber: _tchmNumber.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Dialog сам добавляет viewInsets клавиатуры к insetPadding.
    // Повторный учёт сжимает область полей и обрезает кнопки на iPhone.
    return Dialog(
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ColumnEditorHeader(column: widget.column),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _field(
                      label: 'ТЧМ',
                      hint: 'Фамилия и инициалы',
                      icon: Icons.badge_outlined,
                      controller: _tchmName,
                      action: TextInputAction.next,
                      capitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 14),
                    _field(
                      label: 'Табельный ТЧМ',
                      hint: 'Только цифры',
                      icon: Icons.tag,
                      controller: _tchmNumber,
                      action: TextInputAction.done,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('Сохранить'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    required TextInputAction action,
    TextInputType? keyboardType,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppPalette.textSecondary,
            ),
          ),
        ),
        _KeyboardTextField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: action,
          textCapitalization: capitalization,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppPalette.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              fontWeight: FontWeight.w400,
              color: DepotBrand.silverMuted,
            ),
            prefixIcon: Icon(icon, size: 20),
            isDense: true,
            fillColor: AppPalette.surfaceTint,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }
}

/// Шапка редактора колонны: номер в фирменной плашке, название и крестик.
class _ColumnEditorHeader extends StatelessWidget {
  const _ColumnEditorHeader({required this.column});

  final ColumnGroup column;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DepotBrand.redLight, DepotBrand.redDeep],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0x2EFFFFFF),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${column.number}',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  column.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Кто ведёт колонну',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Закрыть',
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
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

    // Без общей карточки: список машинистов сам состоит из карточек,
    // и обёртка давала рамку в рамке. Поиск и заголовок лежат на фоне.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _KeyboardTextField(
          controller: search,
          textInputAction: TextInputAction.search,
          onChanged: (_) => onSearchChanged(),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Поиск по фамилии',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: search.text.trim().isEmpty
                ? null
                : IconButton(
                    tooltip: 'Очистить',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      search.clear();
                      onSearchChanged();
                    },
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '${machinists.length}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppPalette.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: machinists.isEmpty
              ? const _EmptyList()
              // Нижний отступ оставляет место под плавающую кнопку.
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: machinists.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
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

class MachinistCard extends StatefulWidget {
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
  State<MachinistCard> createState() => _MachinistCardState();
}

class _MachinistCardState extends State<MachinistCard>
    with SingleTickerProviderStateMixin {
  /// Насколько карточка уезжает влево, открывая кнопку правки.
  static const double _actionWidth = 88;

  /// Открытой может быть только одна карточка во всём приложении. Когда
  /// следующая карточка забирает это состояние, предыдущая закрывается.
  static final ValueNotifier<String?> _openCardId = ValueNotifier(null);

  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void initState() {
    super.initState();
    _openCardId.addListener(_closeWhenAnotherCardOpens);
  }

  @override
  void dispose() {
    _openCardId.removeListener(_closeWhenAnotherCardOpens);
    if (_openCardId.value == widget.machinist.id) {
      _openCardId.value = null;
    }
    _slide.dispose();
    super.dispose();
  }

  bool get _isOpen => _slide.value > 0;

  void _closeWhenAnotherCardOpens() {
    if (_openCardId.value != widget.machinist.id && _isOpen) {
      _close(releaseActiveCard: false);
    }
  }

  void _claimOpenState() {
    if (_openCardId.value != widget.machinist.id) {
      _openCardId.value = widget.machinist.id;
    }
  }

  void _releaseOpenState() {
    if (_openCardId.value == widget.machinist.id) {
      _openCardId.value = null;
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    final nextValue = _slide.value - delta / _actionWidth;
    if (nextValue > _slide.value) _claimOpenState();
    _slide.value = nextValue;
  }

  void _onDragEnd(DragEndDetails details) {
    // Быстрый рывок докидывает карточку до края, медленный — притягивает
    // к ближайшему положению.
    final velocity = -details.velocity.pixelsPerSecond.dx / _actionWidth;
    if (velocity.abs() > 1.5) {
      if (velocity > 0) {
        _claimOpenState();
      } else {
        _releaseOpenState();
      }
      _slide.fling(velocity: velocity);
    } else {
      if (_slide.value > 0.5) {
        _claimOpenState();
        _slide.animateTo(1, curve: Curves.easeOut);
      } else {
        _close();
      }
    }
  }

  void _close({bool releaseActiveCard = true}) {
    _slide.animateTo(0, curve: Curves.easeOut);
    if (releaseActiveCard) _releaseOpenState();
  }

  Future<void> _openEditor(ColumnGroup? column) async {
    _releaseOpenState();
    await _slide.animateTo(0, duration: const Duration(milliseconds: 140));
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MachinistEditorScreen(
          user: widget.user,
          columns: widget.columns,
          machinist: widget.machinist,
          initialColumn: column,
        ),
      ),
    );
  }

  Future<void> _copyMachinist(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      ClipboardData(text: _machinistClipboardText(widget.machinist)),
    );
    messenger.showSnackBar(
      const SnackBar(content: Text('Скопировано в буфер обмена')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final machinist = widget.machinist;
    final columns = widget.columns;
    final canEdit = widget.user.canEditMachinist(machinist);
    final column = columns
        .where((value) => value.id == machinist.columnId)
        .cast<ColumnGroup?>()
        .firstOrNull;
    final statusByDiscipline = {
      for (final result in evaluateAllChecks(machinist))
        result.discipline: result.status,
    };
    final overall = machinistOverallStatus(machinist);

    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F1B1D20),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
                            ?machinistExperienceLabel(machinist.workStart),
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
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      color: AppPalette.textSecondary,
                      tooltip: 'Копировать',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () => _copyMachinist(context),
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
                    MachinistIcons.kip,
                    status: statusByDiscipline[CheckDiscipline.kip],
                  ),
                  _WorkMark(
                    'ТРА',
                    machinist.tra,
                    MachinistIcons.tra,
                    status: statusByDiscipline[CheckDiscipline.tra],
                  ),
                  _WorkMark(
                    'АЗЗ',
                    machinist.atz,
                    MachinistIcons.atz,
                    status: statusByDiscipline[CheckDiscipline.atz],
                  ),
                  _WorkMark(
                    'Сцеп',
                    _couplingMark(machinist),
                    MachinistIcons.coupling,
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

    if (!canEdit) return card;

    // Правка вызывается свайпом влево: карточка сдвигается и открывает
    // кнопку. Тап по карточке редактор больше не открывает — он только
    // закрывает уже выехавшую кнопку.
    return Stack(
      children: [
        Positioned.fill(child: _editAction(column)),
        AnimatedBuilder(
          animation: _slide,
          builder: (context, child) => Transform.translate(
            offset: Offset(-_slide.value * _actionWidth, 0),
            child: child,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onTap: () {
              if (_isOpen) _close();
            },
            child: card,
          ),
        ),
      ],
    );
  }

  /// Кнопка правки, лежащая под карточкой у правого края.
  Widget _editAction(ColumnGroup? column) {
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: _actionWidth,
          height: constraints.maxHeight,
          child: Material(
            color: DepotBrand.redInk,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openEditor(column),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.edit_outlined, color: Colors.white, size: 22),
                  SizedBox(height: 3),
                  Text(
                    'Редактировать',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
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

/// Полных лет и месяцев с даты начала работы. Дата расчёта берётся при
/// построении карточки, поэтому стаж автоматически меняется каждый месяц.
String? machinistExperienceLabel(String workStart, {DateTime? onDate}) {
  final start = _parseDate(workStart);
  final today = onDate ?? DateTime.now();
  final currentDate = DateTime(today.year, today.month, today.day);
  if (start == null || start.isAfter(currentDate)) return null;

  var totalMonths =
      (currentDate.year - start.year) * 12 + currentDate.month - start.month;
  final lastDayOfCurrentMonth = DateTime(
    currentDate.year,
    currentDate.month + 1,
    0,
  ).day;
  final anniversaryDay = start.day > lastDayOfCurrentMonth
      ? lastDayOfCurrentMonth
      : start.day;
  if (currentDate.day < anniversaryDay) totalMonths -= 1;

  final years = totalMonths ~/ 12;
  final months = totalMonths % 12;
  if (years == 0) return 'Стаж: $months ${_monthsWord(months)}';

  final parts = ['Стаж: $years ${_yearsWord(years)}'];
  if (months > 0) parts.add('$months ${_monthsWord(months)}');

  return parts.join(' ');
}

/// Склоняет слово по числу: 1 колонна, 2 колонны, 5 колонн. Числа в сводке
/// стоят рядом с подписью, и «24 колонн» читается как опечатка.
String pluralRu(int value, String one, String few, String many) {
  final lastTwoDigits = value % 100;
  if (lastTwoDigits >= 11 && lastTwoDigits <= 14) return many;

  return switch (value % 10) {
    1 => one,
    2 || 3 || 4 => few,
    _ => many,
  };
}

String _yearsWord(int value) {
  final lastTwoDigits = value % 100;
  if (lastTwoDigits >= 11 && lastTwoDigits <= 14) return 'лет';

  return switch (value % 10) {
    1 => 'год',
    2 || 3 || 4 => 'года',
    _ => 'лет',
  };
}

String _monthsWord(int value) {
  final lastTwoDigits = value % 100;
  if (lastTwoDigits >= 11 && lastTwoDigits <= 14) return 'месяцев';

  return switch (value % 10) {
    1 => 'месяц',
    2 || 3 || 4 => 'месяца',
    _ => 'месяцев',
  };
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

/// Текстовое представление машиниста для копирования в буфер обмена.
/// Доступно всем ролям (инструктор, разработчик, гость).
String _machinistClipboardText(Machinist machinist) {
  String value(String text) => text.trim().isEmpty ? '—' : text.trim();

  return <String>[
    machinist.fullName,
    'начало работы: ${value(machinist.workStart)}',
    'Класс: ${value(machinist.classRank)}',
    'КИП: ${value(machinist.kip)}',
    'АЗЗ: ${value(machinist.atz)}',
    'Сцеп: ${value(machinist.coupling)}',
    'ТРА: ${value(machinist.tra)}',
  ].join('\n');
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
    dataRows.add(
      pw.TableRow(
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
      ),
    );
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
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
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
                hCell('АЗЗ'),
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
    this.textCapitalization = TextCapitalization.none,
    this.style,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization textCapitalization;
  final TextStyle? style;

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
      textCapitalization: widget.textCapitalization,
      obscureText: widget.obscureText,
      style: widget.style,
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
                isExpanded: true,
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
                    child: Text(
                      column.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
              _field(_ticket, 'Талон', Icons.confirmation_number_outlined),
              _dateField(_kip, 'КИП', MachinistIcons.kip),
              _kipExtensionToggle(),
              if (_kipExtended)
                _field(
                  _kipExtensionOrder,
                  'Приказ или распоряжение',
                  Icons.description_outlined,
                ),
              _twoFields(
                _dateField(_tra, 'ТРА', MachinistIcons.tra),
                _dateField(_atz, 'АЗЗ', MachinistIcons.atz),
              ),
              _dateField(_coupling, 'Сцеп', MachinistIcons.coupling),
              _couplingToggles(),
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

  Widget _kipExtensionToggle() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppPalette.surfaceTint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppPalette.border),
        ),
        child: SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          dense: true,
          secondary: const Icon(Icons.gavel_outlined),
          title: const Text('КИП на год по приказу'),
          value: _kipExtended,
          onChanged: (value) => setState(() => _kipExtended = value),
        ),
      ),
    );
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
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Класс',
          prefixIcon: Icon(MachinistIcons.classRank),
        ),
        items: MachinistClass.values
            .map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text(
                  value.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
