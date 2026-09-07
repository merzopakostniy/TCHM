/// Вход и данные через собственный API вместо Firebase.
///
/// Реализует те же [AppAuth] и [TchmRepository], которыми уже пользуются все
/// экраны, поэтому подмена не требует правок в интерфейсе: меняется только
/// то, откуда берутся данные.
///
/// Живого потока обновлений здесь нет — HTTP так не умеет. Списки
/// перечитываются при открытии экрана, жестом «потянуть вниз» и после
/// каждой правки: КИП правят раз в месяц, а не десять человек разом.
library;

import 'dart:async';

import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'api.dart';
import 'invite_codes.dart';
import 'legal.dart';
import 'main.dart';

/// Вход через собственный API.
class ApiAppAuth implements AppAuth {
  ApiAppAuth(this.api);

  final ApiClient api;

  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _current;
  var _started = false;

  AppUser? get currentUser => _current;

  @override
  Stream<AppUser?> authStateChanges() {
    if (!_started) {
      _started = true;
      // Токен мог остаться с прошлого запуска — проверяем его на сервере,
      // а не верим на слово: за ночь учётную запись могли закрыть.
      unawaited(_restore());
    }
    return _controller.stream;
  }

  Future<void> _restore() async {
    await api.restore();
    if (!api.hasToken) {
      _emit(null);
      return;
    }
    try {
      final body = await api.get('/me');
      _emit(_userFrom(body['user'] as Map<String, dynamic>));
    } on ApiException {
      await api.setToken(null);
      _emit(null);
    }
  }

  void _emit(AppUser? user) {
    _current = user;
    _controller.add(user);
  }

  static AppUser _userFrom(Map<String, dynamic> map) {
    return AppUser(
      id: map['id']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      displayName: map['displayName']?.toString() ?? 'Пользователь',
      role: roleFromString(map['role']),
      depotId: map['depotId']?.toString(),
      status: statusFromString(map['status']),
      personnelNumber: map['personnelNumber']?.toString(),
    );
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      final body = await api.post('/auth/login', {
        'email': email.trim(),
        'password': password,
      });
      await api.setToken(body['token']?.toString());
      _emit(_userFrom(body['user'] as Map<String, dynamic>));
    } on ApiException catch (error) {
      throw AuthException('$error');
    }
  }

  /// Открывает браузер с Яндекс ID и ждёт возврата.
  ///
  /// Возвращает пропуск на регистрацию, если такого человека ещё нет: сервер
  /// не разворачивает незнакомого, а даёт дописать депо, табельный и ключ.
  /// Пустая строка — человек уже вошёл, дописывать нечего.
  Future<String> authenticateWithYandex() async {
    final String callback;
    try {
      callback = await FlutterWebAuth2.authenticate(
        url: '${api.baseUrl}/auth/yandex/start',
        callbackUrlScheme: 'tchm',
      );
    } catch (error) {
      throw const AuthException('Вход через Яндекс отменён.');
    }
    final uri = Uri.parse(callback);
    final error = uri.queryParameters['error'];
    if (error != null && error.isNotEmpty) throw AuthException(error);
    final signup = uri.queryParameters['signup'];
    if (signup != null && signup.isNotEmpty) return signup;
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) {
      throw const AuthException('Яндекс не вернул ответ.');
    }
    await signInWithToken(token);
    return '';
  }

  /// Заканчивает регистрацию по пропуску от Яндекса: пароля нет, почта уже
  /// подтверждена, поэтому человек попадает внутрь сразу.
  Future<void> completeYandexSignUp({
    required String ticket,
    required String depotId,
    required String displayName,
    required String personnelNumber,
    required UserRole role,
    required String inviteCode,
  }) async {
    try {
      final body = await api.post('/auth/yandex/signup', {
        'ticket': ticket,
        'depotId': depotId,
        'displayName': displayName,
        'personnelNumber': personnelNumber,
        'role': role.key,
        'inviteCode': inviteCode,
        'consentVersion': legalDocsVersion,
      });
      await api.setToken(body['token']?.toString());
      _emit(_userFrom(body['user'] as Map<String, dynamic>));
    } on ApiException catch (error) {
      if (error.statusCode == 403) throw InviteException('$error');
      throw AuthException('$error');
    }
  }

  /// Вход по токену, полученному из браузера после Яндекс ID.
  Future<void> signInWithToken(String token) async {
    await api.setToken(token);
    try {
      final body = await api.get('/me');
      _emit(_userFrom(body['user'] as Map<String, dynamic>));
    } on ApiException catch (error) {
      await api.setToken(null);
      throw AuthException('$error');
    }
  }

  @override
  Future<void> register(RegistrationRequest request) async {
    try {
      await api.post('/auth/register', {
        'email': request.email.trim(),
        'password': request.password,
        'displayName': request.displayName,
        'personnelNumber': request.personnelNumber,
        'depotId': request.depotId,
        'role': request.role.key,
        'inviteCode': request.inviteCode,
        'consentVersion': legalDocsVersion,
      });
      // Токена нет намеренно: пока почта не подтверждена, входить нечем.
    } on ApiException catch (error) {
      if (error.statusCode == 403) throw InviteException('$error');
      throw AuthException('$error');
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await api.post('/auth/forgot', {'email': email.trim()});
    } on ApiException catch (error) {
      throw AuthException('$error');
    }
  }

  /// Повторное письмо подтверждения. Пароль нужен, чтобы письмо нельзя было
  /// слать на чужой адрес, зная только адрес.
  Future<void> resendVerificationFor({
    required String email,
    required String password,
  }) async {
    try {
      await api.post('/auth/resend', {
        'email': email.trim(),
        'password': password,
      });
    } on ApiException catch (error) {
      throw AuthException('$error');
    }
  }

  @override
  Future<void> resendVerification() async {
    throw const AuthException(
      'Введите почту и пароль на экране входа, чтобы получить письмо заново.',
    );
  }

  @override
  Future<bool> refreshVerification() async {
    if (!api.hasToken) return false;
    try {
      final body = await api.get('/me');
      final user = _userFrom(body['user'] as Map<String, dynamic>);
      _emit(user);
      return user.status == AccountStatus.active;
    } on ApiException {
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    await api.setToken(null);
    _emit(null);
  }
}

/// Данные через собственный API.
///
/// Потоки здесь искусственные: [watchColumns] и [watchMachinists] отдают
/// последнее, что известно, и перечитывают сервер по [refresh]. Экраны
/// продолжают работать со `StreamBuilder`, как с Firestore, — меняется
/// только момент обновления.
class ApiTchmRepository implements TchmRepository {
  ApiTchmRepository(this.api, {this.depotId});

  final ApiClient api;

  /// Депо для просмотра со стороны разработчика. Обычному человеку депо
  /// навязывает сервер по его профилю, и подменить его отсюда нельзя.
  final String? depotId;

  final _columns = StreamController<List<ColumnGroup>>.broadcast();
  final _machinists = StreamController<List<Machinist>>.broadcast();
  final _users = StreamController<List<AppUser>>.broadcast();
  final _lock = StreamController<AppLock>.broadcast();
  var _lastLock = const AppLock();
  var _lastColumns = const <ColumnGroup>[];
  var _lastMachinists = const <Machinist>[];
  var _lastUsers = const <AppUser>[];
  var _loaded = false;

  Map<String, String>? get _query =>
      depotId == null ? null : {'depotId': depotId!};

  /// Перечитывает всё с сервера. Вызывается при открытии экрана, жестом
  /// «потянуть вниз» и после каждой правки.
  Future<void> refresh() async {
    _lastLock = _lockFrom(await api.get('/lock'));
    _lock.add(_lastLock);
    try {
      await _refreshData();
    } on ApiException catch (error) {
      final lock = error.maintenanceLock;
      if (lock != null) {
        _lastLock = _lockFrom(lock);
        _lock.add(_lastLock);
        if (_lastLock.readsBlocked) {
          _lastColumns = const [];
          _lastMachinists = const [];
          _lastUsers = const [];
          _columns.add(_lastColumns);
          _machinists.add(_lastMachinists);
          _users.add(_lastUsers);
          _loaded = false;
        }
      }
      rethrow;
    }
  }

  Future<void> _refreshData() async {
    final columnsBody = await api.get('/columns', _query);
    final machinistsBody = await api.get('/machinists', _query);
    _lastColumns = [
      for (final item in (columnsBody['columns'] as List? ?? []))
        _columnFrom(item as Map<String, dynamic>),
    ];
    _lastMachinists = [
      for (final item in (machinistsBody['machinists'] as List? ?? []))
        _machinistFrom(item as Map<String, dynamic>),
    ];
    // Учётные записи читают администратор и разработчик; остальным сервер откажет,
    // и это не повод ронять обновление колонн.
    try {
      final usersBody = await api.get('/users', _query);
      _lastUsers = [
        for (final item in (usersBody['users'] as List? ?? []))
          ApiAppAuth._userFrom(item as Map<String, dynamic>),
      ];
    } on ApiException catch (error) {
      if (error.statusCode != 403) rethrow;
      _lastUsers = const <AppUser>[];
    }
    _loaded = true;
    _columns.add(_lastColumns);
    _machinists.add(_lastMachinists);
    _users.add(_lastUsers);
  }

  Future<void>? _loading;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    // Один поход за данными на всех подписчиков: экранов, читающих списки,
    // несколько, и без этого они дёргали бы сервер каждый сам за себя.
    final pending = _loading;
    if (pending != null) return pending;
    final future = refresh().catchError((Object _) {
      // Без сети список останется пустым, но следующая попытка — открытие
      // экрана или жест «потянуть вниз» — уже не заблокируется.
      _loading = null;
    });
    _loading = future;
    await future;
    _loading = null;
  }

  static AppLock _lockFrom(Map<String, dynamic> map) {
    return AppLock(
      writesBlocked: map['writesBlocked'] == true,
      readsBlocked: map['readsBlocked'] == true,
      updatedBy: map['updatedBy']?.toString() ?? '',
    );
  }

  static ColumnGroup _columnFrom(Map<String, dynamic> map) {
    return ColumnGroup(
      id: map['id']?.toString() ?? '',
      depotId: map['depotId']?.toString(),
      number: (map['number'] as num?)?.toInt() ?? 0,
      title: map['title']?.toString() ?? '',
      instructorName: map['instructorName']?.toString() ?? '',
      tchmName: map['tchmName']?.toString() ?? '',
      tchmPersonnelNumber: map['tchmPersonnelNumber']?.toString() ?? '',
    );
  }

  static String _text(Object? value) => value?.toString() ?? '';

  Machinist _machinistFrom(Map<String, dynamic> map) {
    final columnId = _text(map['columnId']);
    final column = _lastColumns.where((c) => c.id == columnId).firstOrNull;
    return Machinist(
      id: _text(map['id']),
      depotId: map['depotId']?.toString(),
      columnId: columnId,
      columnNumber: column?.number ?? 0,
      fullName: _text(map['fullName']),
      classRank: _text(map['classRank']),
      workStart: _text(map['workStart']),
      ticket: _text(map['ticket']),
      kip: _text(map['kip']),
      tra: _text(map['tra']),
      atz: _text(map['atz']),
      coupling: _text(map['coupling']),
      vn: _text(map['vn']),
      tchmName: _text(map['tchmName']),
      notes: _text(map['notes']),
      kipExtensionMonths: (map['kipExtensionMonths'] as num?)?.toInt() ?? 0,
      kipExtensionOrder: _text(map['kipExtensionOrder']),
      updatedAt: DateTime.now(),
      updatedBy: _text(map['updatedBy']),
    );
  }

  @override
  Stream<List<ColumnGroup>> watchColumns() async* {
    unawaited(_ensureLoaded());
    yield _lastColumns;
    yield* _columns.stream;
  }

  @override
  Stream<List<Machinist>> watchMachinists({String? columnId}) async* {
    unawaited(_ensureLoaded());
    List<Machinist> filter(List<Machinist> items) => columnId == null
        ? items
        : items.where((item) => item.columnId == columnId).toList();
    yield filter(_lastMachinists);
    yield* _machinists.stream.map(filter);
  }

  @override
  Stream<List<AppUser>> watchUsers() async* {
    unawaited(_ensureLoaded());
    yield _lastUsers;
    yield* _users.stream;
  }

  @override
  Future<void> createColumn({
    required int number,
    required AppUser user,
  }) async {
    // ТЧМ новой колонны — тот, кто её завёл. Сервер берёт имя строго из
    // тела запроса, поэтому без этих двух полей колонна создавалась с
    // пустым ТЧМ и её приходилось сразу править руками. У Firebase и у
    // демо-репозитория подстановка была, при переезде на API потерялась.
    await api.post('/columns', {
      'number': number,
      'depotId': depotId ?? user.depotId,
      'tchmName': user.displayName,
      'tchmPersonnelNumber': user.personnelNumber ?? '',
    });
    await refresh();
  }

  @override
  Future<void> updateColumn(ColumnGroup column, AppUser user) async {
    await api.put('/columns/${column.id}', {
      'number': column.number,
      'title': column.title,
      'tchmName': column.tchmName,
      'tchmPersonnelNumber': column.tchmPersonnelNumber,
      'instructorName': column.instructorName,
    });
    await refresh();
  }

  @override
  Future<void> deleteColumn(ColumnGroup column, AppUser user) async {
    await api.delete('/columns/${column.id}');
    await refresh();
  }

  @override
  Future<void> saveMachinist(Machinist machinist, AppUser user) async {
    final body = {
      'columnId': machinist.columnId,
      'fullName': machinist.fullName,
      'classRank': machinist.classRank,
      'workStart': machinist.workStart,
      'ticket': machinist.ticket,
      'kip': machinist.kip,
      'tra': machinist.tra,
      'atz': machinist.atz,
      'coupling': machinist.coupling,
      'vn': machinist.vn,
      'notes': machinist.notes,
      'kipExtensionMonths': machinist.kipExtensionMonths,
      'kipExtensionOrder': machinist.kipExtensionOrder,
    };
    if (machinist.id.isEmpty) {
      await api.post('/machinists', body);
    } else {
      await api.put('/machinists/${machinist.id}', body);
    }
    await refresh();
  }

  @override
  Future<void> deleteMachinist(Machinist machinist, AppUser user) async {
    await api.delete('/machinists/${machinist.id}');
    await refresh();
  }

  @override
  Future<void> seedDefaults(AppUser user) async {
    // Шаблонных колонн больше нет: пустое депо так и показывается пустым.
  }

  @override
  Stream<AppLock> watchLock() async* {
    yield _lastLock;
    yield* _lock.stream;
  }

  @override
  Future<void> setLock(AppLock lock, AppUser user) async {
    if (!user.role.canManageDatabaseLock) {
      throw StateError('Режим обслуживания доступен только разработчику.');
    }
    final body = await api.put('/lock', {
      'writesBlocked': lock.writesBlocked,
      'readsBlocked': lock.readsBlocked,
    });
    _lastLock = _lockFrom(body);
    _lock.add(_lastLock);
  }

  @override
  Future<void> setAccountStatus({
    required List<String> userIds,
    required AccountStatus status,
    required AppUser by,
  }) async {
    await api.put('/users/status', {'userIds': userIds, 'status': status.name});
    await refresh();
  }

  @override
  Future<void> deleteAccounts({
    required List<String> userIds,
    required AppUser by,
  }) async {
    await api.post('/users/delete', {'userIds': userIds});
    await refresh();
  }
}
