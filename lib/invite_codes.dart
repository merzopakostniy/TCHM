/// Проверка ключа руководителя при регистрации.
///
/// ВРЕМЕННОЕ РЕШЕНИЕ. Здесь лежат отпечатки ключей, а не сами ключи, но
/// проверка всё равно идёт на устройстве — значит, отпечатки и соль уезжают
/// вместе с установочным пакетом. Подобрать по ним ключ вычислительно
/// невозможно (60 бит на ключ), однако устройство остаётся не тем местом,
/// где стоит принимать решение о выдаче прав.
///
/// Когда появится сервер, [LocalInviteVerifier] заменяется на реализацию,
/// которая ходит на бэкенд, а этот файл удаляется целиком. Экраны входа
/// работают через [InviteVerifier] и о подмене не узнают.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Что ключ даёт предъявителю.
class InviteGrant {
  const InviteGrant({required this.depotId, required this.role});

  final String depotId;

  /// Роль строкой, чтобы файл не зависел от перечисления ролей в main.dart.
  final String role;
}

class InviteException implements Exception {
  const InviteException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class InviteVerifier {
  /// Возвращает права по ключу либо бросает [InviteException] с текстом,
  /// который можно показать человеку.
  Future<InviteGrant> verify({required String depotId, required String code});
}

/// Приводит ключ к виду, в котором он сравнивается: верхний регистр,
/// латиница, дефисы на своих местах. Человек вводит ключ с бумажки, и
/// придираться к регистру или лишним пробелам смысла нет.
String normalizeInviteCode(String value) {
  final cleaned = value.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
  if (cleaned.length != 17) return cleaned;
  return '${cleaned.substring(0, 5)}-${cleaned.substring(5, 9)}-'
      '${cleaned.substring(9, 13)}-${cleaned.substring(13)}';
}

class LocalInviteVerifier implements InviteVerifier {
  const LocalInviteVerifier();

  static const _salt = '8b31db70913fe4fb62ec4bc89774d522';

  /// Отпечаток ключа руководителя по депо: sha256(соль + ключ).
  static const _fingerprints = <String, String>{
    'tch01': '95c9639aa6c034f7c7cdb6b532e47b639ca93495fc55ccc912ca3c5fc97f1af9',
    'tch02': '17d6fc962b1c2827c75aab1d96e7f5a434b30234d3280d1bd74aa94168eaf5e8',
    'tch03': 'f0f8880bff7f4c33cee238c5a3318c38ea4c61bbcfff802541c10a1d0c398ab1',
    'tch04': '66e9b14370a4825ab9c39007fec76a502e868e2963a43e74130e7238e06146dd',
    'tch05': 'f259b8a64b10e20e5387eca8f9b2e973b68318f7a3980003e3b4220a248f0211',
    'tch06': '00726fcc2d877bde849b4e418f4269f933eb3ac27d85c7594e27af4e54866de4',
    'tch07': '0f6cd9e5c03720654b6da23cfdd41fa07c22c340a260a295af09997d97d0da28',
    'tch08': 'c5aa6d54228b47e74d1fe22537c72c5d6ea536a22459727f00112f0fed422580',
    // Отдельный ключ штата Бутовской линии Варшавского депо.
    'tch08_bl':
        '368c95482517c086f31ac8124486f0d551b548124527b13a2b825b0f817d4e0c',
    'tch09': '097e6eb064a68cb215f5cd88f2562e210e6ea566a06b56aafd1720c580d26ffd',
    'tch10': '07e9513719fe0f0bb96013dc3cc823b23db9d3393188854bf158849ad0eaf307',
    'tch11': '5d134583004acbc4e288c1558249fe8ac86e0d1fd6031f090e3fefabc9fe37b2',
    'tch12': 'a1bb0eb99b493807f717c9028082ac6a2f1b6d3e600ba2f3c14ec3471da21199',
    'tch13': '524670d6e7cfd276ddc6ab95dc66603d49b43e593bbedac033e92bfd1b97307c',
    'tch14': 'dfdb70423892ab104cedb5f8f9bb540c9091bbafc710ca40568810986b0ae14c',
    'tch15': '01e4aad8fbe1a3da34aac0648b2a004967c738a6a56cea606b6db4fb9247995c',
    'tch16': 'ace4f409449f732486f64c58024f5d89096c8b942538d3693ad20f290a0a04a5',
    'tch17': '6cb25b12591289ec74de69e3af4b1d1329469e9ae0c7ce7c0f4786708aeb13e3',
    'tch18': '6ee487814338430f7acd0653051bdb0ec241f3353a8b9ec974232e4d21ce1ca7',
    'tch19': '921db6fd41edc851dc3ad10a88785ba885159700e7782c42e9ac011eccb84c30',
    'tch20': '03fce613217904ca4d32974f3309e1cdb0a2e874867530efbef85c93a394016b',
    'tch21': 'fda10ab2ad67300c2e60499f7eb3b3066b5f1e6abab3318a8a45583a134b1ed7',
    'tch22': '27af79ca40e0963e9cbb7be03947abf61e0504b0ecc273e7b59f7ca9ad093b0b',
    'tch23': '9f812b7237cbd59524822f4994e689b12922b587f4990895cc277887655481b2',
    // ТЧ-24 «Ильинское»: прежний id сохранён для существующих профилей.
    'novorizhskoe':
        '0578b4ba9ddef7ce8e363d418167c501d82e709955a498c36b0ac09b3c4efb59',
  };

  @override
  Future<InviteGrant> verify({
    required String depotId,
    required String code,
  }) async {
    final normalized = normalizeInviteCode(code);
    if (normalized.isEmpty) {
      throw const InviteException('Введите ключ руководителя.');
    }
    final expected = _fingerprints[depotId];
    if (expected == null) {
      throw const InviteException('Для этого депо ключ ещё не выдан.');
    }
    final actual = sha256.convert(utf8.encode('$_salt$normalized')).toString();
    if (actual != expected) {
      throw const InviteException(
        'Ключ не подходит к выбранному депо. Проверьте депо и сам ключ.',
      );
    }
    // Ключ руководителя пока один на депо и открывает роль ТЧМ. Разные
    // ключи под разные роли появятся вместе с кабинетом руководителя.
    return InviteGrant(depotId: depotId, role: 'tchm');
  }
}
