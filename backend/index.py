"""API приложения «Нормативы ТЧМ» на Яндекс Облаке.

Одна функция за API Gateway: маршруты разбираются здесь же, потому что их
немного и держать их в одном файле проще, чем размазывать по функциям.

Схема таблиц создаётся при первом обращении и переживает повторные запуски:
CREATE TABLE IF NOT EXISTS. Отдельного шага миграции нет намеренно — база
serverless, таблиц мало, и лишний ручной шаг забудут сделать.
"""

import base64
import hashlib
import json
import os
import re
import secrets
import smtplib
import ssl
import time
from email.message import EmailMessage
import urllib.parse
import urllib.request
import uuid

import jwt
import ydb

YDB_ENDPOINT = os.environ["YDB_ENDPOINT"]
YDB_DATABASE = os.environ["YDB_DATABASE"]
JWT_SECRET = os.environ["JWT_SECRET"]

# Вход через Яндекс ID. Секрет приезжает из Lockbox; пока его нет, эти
# маршруты честно отвечают «не настроено», а вход по почте работает.
YANDEX_CLIENT_ID = os.environ.get("YANDEX_CLIENT_ID", "")
YANDEX_CLIENT_SECRET = os.environ.get("YANDEX_CLIENT_SECRET", "")

# Куда возвращать человека из браузера обратно в приложение.
APP_REDIRECT_SCHEME = os.environ.get("APP_REDIRECT_SCHEME", "tchm://auth")

# Адрес самого API: нужен, чтобы собрать ссылку подтверждения в письме.
PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "")

# Почта, с которой уходят письма. Пароль — приложения, а не от аккаунта, и
# лежит в Lockbox: обычный пароль в переменной окружения — это доступ ко
# всей переписке того ящика, а не только к отправке.
SMTP_HOST = os.environ.get("SMTP_HOST", "smtp.yandex.ru")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "465"))
SMTP_USER = os.environ.get("SMTP_USER", "")
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD", "")
MAIL_FROM = os.environ.get("MAIL_FROM", "") or SMTP_USER

# Ссылка подтверждения живёт сутки: письмо доходит за минуты, а вечная
# ссылка в чужом почтовом ящике — это вечный вход в учётную запись.
VERIFY_TTL_SECONDS = 24 * 3600

# Домены служебной почты, с которых разрешена регистрация. Пусто — принимаем
# любой адрес. Список живёт в переменной функции, а не в сборке приложения:
# сменить домен нужно уметь без выпуска новой версии в сторах.
ALLOWED_EMAIL_DOMAINS = [
    d.strip().lower()
    for d in os.environ.get("ALLOWED_EMAIL_DOMAINS", "").split(",")
    if d.strip()
]

# Назначение администратора применяется только при подтверждении почты
# или регистрации с подтверждённой почтой Яндекс ID. Клиент эту роль не задаёт.
ADMIN_EMAILS = {
    email.strip().lower()
    for email in os.environ.get("ADMIN_EMAILS", "").split(",")
    if email.strip()
}


def _verified_registration_role(email, requested_role):
    return "admin" if email.strip().lower() in ADMIN_EMAILS else requested_role


# Ссылка восстановления живёт час: она даёт сменить пароль, то есть по сути
# и есть доступ к учётной записи, и валяться в почте сутками ей нечего.
RESET_TTL_SECONDS = 3600

# Сколько живёт токен входа. Неделя: люди заходят в приложение не каждый
# день, и заставлять их вводить пароль на каждой смене — лишнее.
TOKEN_TTL_SECONDS = 7 * 24 * 3600

_driver = None
_pool = None
_schema_ready = False


def _connect():
    global _driver, _pool
    if _pool is not None:
        return _pool
    _driver = ydb.Driver(
        endpoint=YDB_ENDPOINT,
        database=YDB_DATABASE,
        credentials=ydb.iam.MetadataUrlCredentials(),
    )
    _driver.wait(fail_fast=True, timeout=10)
    _pool = ydb.QuerySessionPool(_driver)
    return _pool


SCHEMA = [
    """
    CREATE TABLE IF NOT EXISTS users (
        id Utf8 NOT NULL,
        email Utf8,
        email_lower Utf8,
        password_hash Utf8,
        password_salt Utf8,
        yandex_id Utf8,
        display_name Utf8,
        personnel_number Utf8,
        depot_id Utf8,
        role Utf8,
        status Utf8,
        consent_version Utf8,
        consent_at Timestamp,
        created_at Timestamp,
        PRIMARY KEY (id),
        INDEX idx_email GLOBAL ON (email_lower),
        INDEX idx_yandex GLOBAL ON (yandex_id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS depot_invites (
        depot_id Utf8 NOT NULL,
        fingerprint Utf8,
        salt Utf8,
        role Utf8,
        PRIMARY KEY (depot_id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS app_config (
        id Utf8 NOT NULL,
        writes_blocked Bool,
        reads_blocked Bool,
        note Utf8,
        updated_by Utf8,
        updated_at Timestamp,
        PRIMARY KEY (id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS columns (
        id Utf8 NOT NULL,
        depot_id Utf8,
        number Uint32,
        title Utf8,
        tchm_name Utf8,
        tchm_personnel_number Utf8,
        instructor_name Utf8,
        updated_at Timestamp,
        PRIMARY KEY (id),
        INDEX idx_depot GLOBAL ON (depot_id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS machinists (
        id Utf8 NOT NULL,
        depot_id Utf8,
        column_id Utf8,
        full_name Utf8,
        class_rank Utf8,
        work_start Utf8,
        ticket Utf8,
        kip Utf8,
        tra Utf8,
        atz Utf8,
        coupling Utf8,
        vn Utf8,
        notes Utf8,
        kip_extension_months Uint32,
        kip_extension_order Utf8,
        updated_at Timestamp,
        updated_by Utf8,
        PRIMARY KEY (id),
        INDEX idx_depot GLOBAL ON (depot_id),
        INDEX idx_column GLOBAL ON (column_id)
    )
    """,
]


def _ensure_schema(pool):
    global _schema_ready
    if _schema_ready:
        return
    for statement in SCHEMA:
        pool.execute_with_retries(statement)
    _schema_ready = True


# ---- пароли -----------------------------------------------------------
# scrypt из стандартной библиотеки: bcrypt и argon2 тянут нативные сборки,
# а в облачной функции лишние зависимости — лишние поломки при деплое.

def _hash_password(password: str, salt: str) -> str:
    digest = hashlib.scrypt(
        password.encode("utf-8"),
        salt=bytes.fromhex(salt),
        n=16384,
        r=8,
        p=1,
        dklen=32,
    )
    return digest.hex()


def _new_salt() -> str:
    return secrets.token_hex(16)


def _issue_token(user_id: str, role: str, depot_id: str) -> str:
    now = int(time.time())
    return jwt.encode(
        {
            "act": "access",
            "sub": user_id,
            "role": role,
            "depot": depot_id,
            "iat": now,
            "exp": now + TOKEN_TTL_SECONDS,
        },
        JWT_SECRET,
        algorithm="HS256",
    )


def _read_token(headers: dict):
    raw = headers.get("Authorization") or headers.get("authorization") or ""
    if not isinstance(raw, str) or not raw.startswith("Bearer "):
        return None
    try:
        claims = jwt.decode(
            raw[7:], JWT_SECRET, algorithms=["HS256"],
            options={"require": ["act", "sub", "iat", "exp"]},
        )
    except (jwt.PyJWTError, TypeError, ValueError):
        return None
    # Ссылки подтверждения/восстановления и пропуски OAuth подписываются
    # тем же сервером, но не дают права обращаться к пользовательскому API.
    if claims["act"] != "access":
        return None
    if not isinstance(claims["sub"], str) or not claims["sub"].strip():
        return None
    if any(type(claims[key]) is not int for key in ("iat", "exp")):
        return None
    if claims["exp"] <= claims["iat"]:
        return None
    return claims


# ---- ответы -----------------------------------------------------------

def _mail_configured() -> bool:
    return bool(SMTP_USER and SMTP_PASSWORD and PUBLIC_BASE_URL)


def _send_verification(email: str, display_name: str, user_id: str):
    token = jwt.encode(
        {
            "sub": user_id,
            "act": "verify",
            "exp": int(time.time()) + VERIFY_TTL_SECONDS,
        },
        JWT_SECRET,
        algorithm="HS256",
    )
    link = f"{PUBLIC_BASE_URL.rstrip('/')}/auth/verify?token={token}"
    message = EmailMessage()
    message["Subject"] = "Подтверждение почты — Нормативы ТЧМ"
    message["From"] = MAIL_FROM
    message["To"] = email
    message.set_content(
        f"{display_name}, здравствуйте.\n\n"
        "Вы зарегистрировались в приложении «Нормативы ТЧМ». "
        "Чтобы войти, подтвердите адрес почты — откройте ссылку:\n\n"
        f"{link}\n\n"
        "Ссылка действует сутки. Если это были не вы, просто удалите письмо: "
        "без подтверждения учётная запись не работает.\n"
    )
    context = ssl.create_default_context()
    with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, context=context, timeout=15) as smtp:
        smtp.login(SMTP_USER, SMTP_PASSWORD)
        smtp.send_message(message)


def _send_reset(email: str, display_name: str, user_id: str):
    token = jwt.encode(
        {
            "sub": user_id,
            "act": "reset",
            "exp": int(time.time()) + RESET_TTL_SECONDS,
        },
        JWT_SECRET,
        algorithm="HS256",
    )
    link = f"{PUBLIC_BASE_URL.rstrip('/')}/auth/reset?token={token}"
    message = EmailMessage()
    message["Subject"] = "Смена пароля — Нормативы ТЧМ"
    message["From"] = MAIL_FROM
    message["To"] = email
    message.set_content(
        f"{display_name}, здравствуйте.\n\n"
        "Кто-то попросил сменить пароль в приложении «Нормативы ТЧМ». "
        "Если это были вы — откройте ссылку и задайте новый:\n\n"
        f"{link}\n\n"
        "Ссылка действует час. Если это были не вы — ничего делать не нужно, "
        "старый пароль продолжает работать.\n"
    )
    context = ssl.create_default_context()
    with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, context=context, timeout=15) as smtp:
        smtp.login(SMTP_USER, SMTP_PASSWORD)
        smtp.send_message(message)


def _html(code: int, title: str, text: str):
    """Страница, которую человек видит в браузере после нажатия на ссылку."""
    body = (
        "<!doctype html><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<style>body{font:16px/1.5 -apple-system,system-ui,sans-serif;"
        "margin:0;display:flex;min-height:100vh;align-items:center;"
        "justify-content:center;background:#f5f4f2;color:#1b1d20}"
        "div{max-width:22rem;padding:2rem;text-align:center}"
        "h1{font-size:1.25rem;margin:0 0 .5rem}p{color:#6c7075;margin:0}"
        "</style>"
        f"<div><h1>{title}</h1><p>{text}</p></div>"
    )
    return {
        "statusCode": code,
        "headers": {"Content-Type": "text/html; charset=utf-8"},
        "body": body,
    }


def _raw_body(event) -> str:
    """Тело запроса строкой.

    Шлюз отдаёт не-JSON тело (например, обычную веб-форму) в base64 —
    без этого разбора форма смены пароля молча не срабатывала.
    """
    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        try:
            return base64.b64decode(raw).decode("utf-8")
        except Exception:  # noqa: BLE001
            return ""
    return raw


def _reply(code: int, body: dict):
    return {
        "statusCode": code,
        "headers": {"Content-Type": "application/json; charset=utf-8"},
        "body": json.dumps(body, ensure_ascii=False),
    }


def _error(code: int, message: str):
    return _reply(code, {"error": message})


EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _user_public(row) -> dict:
    return {
        "id": row["id"],
        "email": row["email"],
        "displayName": row["display_name"],
        "personnelNumber": row["personnel_number"],
        "depotId": row["depot_id"],
        "role": row["role"],
        "status": row["status"],
    }


def _find_user_by_email(pool, email_lower: str):
    result = pool.execute_with_retries(
        "DECLARE $email AS Utf8; "
        "SELECT * FROM users VIEW idx_email WHERE email_lower = $email LIMIT 1",
        {"$email": (email_lower, ydb.PrimitiveType.Utf8)},
    )
    rows = result[0].rows
    return rows[0] if rows else None


def _find_user_by_yandex(pool, yandex_id: str):
    result = pool.execute_with_retries(
        "DECLARE $yid AS Utf8; "
        "SELECT * FROM users VIEW idx_yandex WHERE yandex_id = $yid LIMIT 1",
        {"$yid": (yandex_id, ydb.PrimitiveType.Utf8)},
    )
    rows = result[0].rows
    return rows[0] if rows else None


def _invite_ok(pool, depot_id: str, code: str) -> bool:
    """Ключ депо проверяется на сервере, а не в приложении.

    В этом весь смысл переезда: раньше отпечаток и соль уезжали вместе со
    сборкой, и подделать регистрацию мог любой, кто вскрыл apk.
    """
    result = pool.execute_with_retries(
        "DECLARE $depot AS Utf8; "
        "SELECT * FROM depot_invites WHERE depot_id = $depot LIMIT 1",
        {"$depot": (depot_id, ydb.PrimitiveType.Utf8)},
    )
    rows = result[0].rows
    if not rows:
        return False
    row = rows[0]
    normalized = re.sub(r"[^0-9A-Z]", "", (code or "").upper())
    digest = hashlib.sha256((row["salt"] + normalized).encode("utf-8"))
    return secrets.compare_digest(digest.hexdigest(), row["fingerprint"])


# ---- маршруты ---------------------------------------------------------

def _register(pool, body):
    email = (body.get("email") or "").strip()
    password = body.get("password") or ""
    display_name = (body.get("displayName") or "").strip()
    personnel = (body.get("personnelNumber") or "").strip()
    depot_id = (body.get("depotId") or "").strip()
    invite = body.get("inviteCode") or ""
    role = body.get("role") or "viewer"

    if not EMAIL_RE.match(email):
        return _error(400, "Проверьте адрес почты.")
    if ALLOWED_EMAIL_DOMAINS:
        domain = email.rsplit("@", 1)[-1].lower()
        if domain not in ALLOWED_EMAIL_DOMAINS:
            return _error(
                400,
                "Регистрация только со служебной почты "
                f"({', '.join(ALLOWED_EMAIL_DOMAINS)}).",
            )
    if len(password) < 8:
        return _error(400, "Пароль должен быть не короче 8 знаков.")
    if len(display_name) < 3:
        return _error(400, "Укажите фамилию и инициалы.")
    if not depot_id:
        return _error(400, "Выберите депо.")
    if role not in ("viewer", "tchm"):
        return _error(400, "При регистрации доступны только ТЧМ и гость.")
    if role != "viewer" and not personnel:
        return _error(400, "Введите табельный номер.")
    if not _invite_ok(pool, depot_id, invite):
        return _error(403, "Ключ не подходит к выбранному депо.")
    if _find_user_by_email(pool, email.lower()):
        return _error(409, "На эту почту уже есть учётная запись.")
    if not _mail_configured():
        return _error(503, "Отправка писем не настроена, регистрация закрыта.")

    salt = _new_salt()
    user_id = str(uuid.uuid4())
    now = int(time.time() * 1_000_000)
    pool.execute_with_retries(
        """
        DECLARE $id AS Utf8; DECLARE $email AS Utf8;
        DECLARE $email_lower AS Utf8; DECLARE $hash AS Utf8;
        DECLARE $salt AS Utf8; DECLARE $name AS Utf8;
        DECLARE $personnel AS Utf8; DECLARE $depot AS Utf8;
        DECLARE $role AS Utf8; DECLARE $consent AS Utf8;
        DECLARE $now AS Timestamp;
        UPSERT INTO users (id, email, email_lower, password_hash, password_salt,
            display_name, personnel_number, depot_id, role, status,
            consent_version, consent_at, created_at)
        VALUES ($id, $email, $email_lower, $hash, $salt, $name, $personnel,
            $depot, $role, "pending", $consent, $now, $now)
        """,
        {
            "$id": (user_id, ydb.PrimitiveType.Utf8),
            "$email": (email, ydb.PrimitiveType.Utf8),
            "$email_lower": (email.lower(), ydb.PrimitiveType.Utf8),
            "$hash": (_hash_password(password, salt), ydb.PrimitiveType.Utf8),
            "$salt": (salt, ydb.PrimitiveType.Utf8),
            "$name": (display_name, ydb.PrimitiveType.Utf8),
            "$personnel": (personnel, ydb.PrimitiveType.Utf8),
            "$depot": (depot_id, ydb.PrimitiveType.Utf8),
            "$role": (role, ydb.PrimitiveType.Utf8),
            "$consent": (
                (body.get("consentVersion") or ""),
                ydb.PrimitiveType.Utf8,
            ),
            "$now": (now, ydb.PrimitiveType.Timestamp),
        },
    )
    try:
        _send_verification(email, display_name, user_id)
    except Exception as error:  # noqa: BLE001
        # Учётная запись уже создана, но без письма войти нельзя. Говорим
        # честно и даём человеку понять, что повторить отправку можно.
        return _error(502, f"Не удалось отправить письмо: {error}")
    # Токена здесь нет намеренно: до подтверждения почты входить нечем.
    return _reply(
        200,
        {
            "status": "pending",
            "message": "Отправили письмо на "
            f"{email}. Откройте ссылку из него, чтобы войти.",
        },
    )


def _login(pool, body):
    email = (body.get("email") or "").strip().lower()
    password = body.get("password") or ""
    row = _find_user_by_email(pool, email)
    # Один и тот же текст на «нет такой почты» и «неверный пароль»: иначе по
    # разнице ответов перебирают, кто вообще зарегистрирован.
    if not row or not row["password_hash"]:
        return _error(401, "Неверная почта или пароль.")
    expected = _hash_password(password, row["password_salt"])
    if not secrets.compare_digest(expected, row["password_hash"]):
        return _error(401, "Неверная почта или пароль.")
    if row["status"] == "disabled":
        return _error(403, "Доступ к этой учётной записи закрыт.")
    if row["status"] == "pending":
        return _error(403, "Подтвердите почту — письмо со ссылкой уже у вас.")
    if row["status"] != "active":
        return _error(403, "Учётная запись не активна.")
    return _reply(
        200,
        {
            "token": _issue_token(row["id"], row["role"], row["depot_id"] or ""),
            "user": _user_public(row),
        },
    )


def _verify(pool, params):
    try:
        claims = jwt.decode(
            (params or {}).get("token") or "", JWT_SECRET, algorithms=["HS256"]
        )
    except jwt.PyJWTError:
        return _html(
            400,
            "Ссылка не работает",
            "Она устарела или была изменена. Запросите письмо заново.",
        )
    if claims.get("act") != "verify":
        return _html(400, "Ссылка не работает", "Неверный тип ссылки.")
    rows = pool.execute_with_retries(
        "DECLARE $id AS Utf8; SELECT status, email, role FROM users WHERE id = $id",
        {"$id": (claims["sub"], ydb.PrimitiveType.Utf8)},
    )[0].rows
    if not rows:
        return _html(404, "Учётная запись не найдена", "Возможно, её удалили.")
    if rows[0]["status"] == "disabled":
        return _html(403, "Доступ закрыт", "Обратитесь к руководителю.")
    role = rows[0]["role"]
    if rows[0]["status"] == "pending":
        role = _verified_registration_role(rows[0]["email"], role)
    pool.execute_with_retries(
        "DECLARE $id AS Utf8; DECLARE $role AS Utf8; "
        "UPDATE users SET status = \"active\", role = $role WHERE id = $id",
        {
            "$id": (claims["sub"], ydb.PrimitiveType.Utf8),
            "$role": (role, ydb.PrimitiveType.Utf8),
        },
    )
    return _html(
        200,
        "Почта подтверждена",
        "Вернитесь в приложение и войдите по почте и паролю.",
    )


def _forgot(pool, body):
    """Письмо со ссылкой на смену пароля.

    Ответ всегда одинаковый, есть такая почта или нет: иначе форма
    восстановления превращается в способ проверять, кто зарегистрирован.
    """
    email = (body.get("email") or "").strip().lower()
    row = _find_user_by_email(pool, email)
    if row and row["status"] != "disabled" and _mail_configured():
        try:
            _send_reset(row["email"], row["display_name"], row["id"])
        except Exception:  # noqa: BLE001 — наружу об этом знать незачем
            pass
    return _reply(
        200,
        {"message": "Если такая почта есть, письмо со ссылкой отправлено."},
    )


RESET_FORM = """
<!doctype html><meta charset='utf-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<style>body{{font:16px/1.5 -apple-system,system-ui,sans-serif;margin:0;
display:flex;min-height:100vh;align-items:center;justify-content:center;
background:#f5f4f2;color:#1b1d20}}form{{max-width:22rem;width:100%;
padding:2rem}}h1{{font-size:1.25rem;margin:0 0 1rem}}
input{{width:100%;box-sizing:border-box;font-size:1rem;padding:.75rem;
border:1px solid #e4e2de;border-radius:12px;margin-bottom:.75rem}}
button{{width:100%;font-size:1rem;font-weight:700;padding:.85rem;color:#fff;
background:#a0141a;border:0;border-radius:14px}}
p{{color:#6c7075;font-size:.85rem}}</style>
<form method='post' action='/auth/reset'>
<h1>Новый пароль</h1>
<input type='hidden' name='token' value='{token}'>
<input type='password' name='password' placeholder='Не короче 8 знаков'
 minlength='8' required autofocus>
<button type='submit'>Сохранить</button>
<p>После сохранения вернитесь в приложение и войдите с новым паролем.</p>
</form>
"""


def _reset_form(params):
    token = (params or {}).get("token") or ""
    try:
        claims = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
    except jwt.PyJWTError:
        return _html(
            400,
            "Ссылка не работает",
            "Она устарела или была изменена. Запросите письмо заново.",
        )
    if claims.get("act") != "reset":
        return _html(400, "Ссылка не работает", "Неверный тип ссылки.")
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "text/html; charset=utf-8"},
        "body": RESET_FORM.format(token=token),
    }


def _reset_apply(pool, event, body):
    # Форма шлёт данные как обычная веб-форма, приложение — как JSON.
    token = body.get("token") or ""
    password = body.get("password") or ""
    if not token:
        parsed = urllib.parse.parse_qs(_raw_body(event))
        token = (parsed.get("token") or [""])[0]
        password = (parsed.get("password") or [""])[0]
    try:
        claims = jwt.decode(token, JWT_SECRET, algorithms=["HS256"],
                            options={"require": ["exp", "sub"]})
    except jwt.PyJWTError:
        return _html(400, "Ссылка не работает", "Она устарела. Запросите новую.")
    if claims.get("act") != "reset" or not isinstance(claims.get("sub"), str) or not claims["sub"]:
        return _html(400, "Ссылка не работает", "Неверный тип ссылки.")
    if len(password) < 8:
        return _html(400, "Пароль слишком короткий", "Нужно не меньше 8 знаков.")
    rows = pool.execute_with_retries(
        "DECLARE $id AS Utf8; SELECT status, email, role FROM users WHERE id = $id",
        {"$id": (claims["sub"], ydb.PrimitiveType.Utf8)},
    )[0].rows
    if not rows:
        return _html(404, "Учётная запись не найдена", "Возможно, её удалили.")
    row = rows[0]
    if row["status"] not in ("pending", "active"):
        return _html(403, "Доступ закрыт", "Обратитесь к руководителю.")
    role = row["role"]
    if row["status"] == "pending":
        role = _verified_registration_role(row["email"], role)
    salt = _new_salt()
    # Смена пароля заодно подтверждает почту: ссылка пришла на неё, значит
    # ящик доступен человеку. Держать его после этого в «ожидает» незачем.
    result = pool.execute_with_retries(
        "DECLARE $id AS Utf8; DECLARE $hash AS Utf8; DECLARE $salt AS Utf8; "
        "DECLARE $role AS Utf8; DECLARE $old_role AS Utf8; "
        "DECLARE $old_status AS Utf8; DECLARE $email AS Utf8; "
        "UPDATE users SET password_hash = $hash, password_salt = $salt, "
        "status = \"active\", role = $role "
        "WHERE id = $id AND status = $old_status AND role = $old_role "
        "AND email = $email RETURNING id",
        {
            "$id": (claims["sub"], ydb.PrimitiveType.Utf8),
            "$hash": (_hash_password(password, salt), ydb.PrimitiveType.Utf8),
            "$salt": (salt, ydb.PrimitiveType.Utf8),
            "$role": (role, ydb.PrimitiveType.Utf8),
            "$old_role": (row["role"], ydb.PrimitiveType.Utf8),
            "$old_status": (row["status"], ydb.PrimitiveType.Utf8),
            "$email": (row["email"], ydb.PrimitiveType.Utf8),
        },
    )
    if not result[0].rows:
        return _html(409, "Учётная запись изменилась",
                     "Пароль не изменён. Запросите новую ссылку восстановления.")
    return _html(
        200, "Пароль изменён", "Вернитесь в приложение и войдите с новым."
    )


def _resend(pool, body):
    email = (body.get("email") or "").strip().lower()
    password = body.get("password") or ""
    row = _find_user_by_email(pool, email)
    # Пароль спрашиваем, чтобы письмо нельзя было слать на чужой адрес,
    # зная только его: иначе это рассылка чужими руками.
    if not row or not row["password_hash"]:
        return _error(401, "Неверная почта или пароль.")
    if not secrets.compare_digest(
        _hash_password(password, row["password_salt"]), row["password_hash"]
    ):
        return _error(401, "Неверная почта или пароль.")
    if row["status"] != "pending":
        return _error(400, "Эта почта уже подтверждена.")
    if not _mail_configured():
        return _error(503, "Отправка писем не настроена.")
    try:
        _send_verification(row["email"], row["display_name"], row["id"])
    except Exception as error:  # noqa: BLE001
        return _error(502, f"Не удалось отправить письмо: {error}")
    return _reply(200, {"status": "sent"})


def _yandex_start():
    """Отправляем человека на страницу разрешения Яндекса.

    `state` подписываем своим же ключом: обратно он вернётся как есть, и по
    подписи видно, что это наш запрос, а не чужая ссылка, подсунутая
    пользователю.
    """
    if not YANDEX_CLIENT_ID or not YANDEX_CLIENT_SECRET:
        return _error(503, "Вход через Яндекс ещё не настроен.")
    state = jwt.encode(
        {"n": secrets.token_urlsafe(12), "exp": int(time.time()) + 600},
        JWT_SECRET,
        algorithm="HS256",
    )
    query = urllib.parse.urlencode(
        {
            "response_type": "code",
            "client_id": YANDEX_CLIENT_ID,
            "state": state,
        }
    )
    return {
        "statusCode": 302,
        "headers": {"Location": f"https://oauth.yandex.ru/authorize?{query}"},
        "body": "",
    }


def _app_redirect(params: dict):
    """Возврат в приложение по своей ссылке: token или error."""
    query = urllib.parse.urlencode(params)
    return {
        "statusCode": 302,
        "headers": {"Location": f"{APP_REDIRECT_SCHEME}?{query}"},
        "body": "",
    }


def _yandex_callback(pool, event):
    if not YANDEX_CLIENT_ID or not YANDEX_CLIENT_SECRET:
        return _error(503, "Вход через Яндекс ещё не настроен.")
    params = event.get("queryStringParameters") or {}
    code = params.get("code")
    state = params.get("state")
    if not code:
        return _app_redirect({"error": "Яндекс не вернул код авторизации."})
    try:
        jwt.decode(state or "", JWT_SECRET, algorithms=["HS256"])
    except jwt.PyJWTError:
        return _app_redirect({"error": "Ссылка входа устарела, повторите."})

    token_body = urllib.parse.urlencode(
        {
            "grant_type": "authorization_code",
            "code": code,
            "client_id": YANDEX_CLIENT_ID,
            "client_secret": YANDEX_CLIENT_SECRET,
        }
    ).encode()
    request = urllib.request.Request(
        "https://oauth.yandex.ru/token", data=token_body
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        token_data = json.loads(response.read())
    access = token_data.get("access_token")
    if not access:
        return _app_redirect({"error": "Яндекс не выдал токен."})

    info_request = urllib.request.Request(
        "https://login.yandex.ru/info?format=json",
        headers={"Authorization": f"OAuth {access}"},
    )
    with urllib.request.urlopen(info_request, timeout=10) as response:
        info = json.loads(response.read())

    yandex_id = str(info.get("id") or "")
    email = (info.get("default_email") or "").strip().lower()
    if not yandex_id:
        return _app_redirect({"error": "Яндекс не вернул идентификатор."})

    row = _find_user_by_yandex(pool, yandex_id)
    if row is None and email:
        row = _find_user_by_email(pool, email)
    # Незнакомого человека не разворачиваем, но и внутрь не пускаем: выдаём
    # короткий пропуск на форму регистрации. Ключ депо и табельный там
    # обязательны ровно так же — Яндекс подтверждает только почту.
    if row is None:
        ticket = jwt.encode(
            {
                "act": "signup",
                "yid": yandex_id,
                "email": email,
                "name": (
                    f"{info.get('last_name') or ''} "
                    f"{info.get('first_name') or ''}"
                ).strip(),
                "exp": int(time.time()) + 600,
            },
            JWT_SECRET,
            algorithm="HS256",
        )
        return _app_redirect({"signup": ticket})
    if row["status"] == "disabled":
        return _app_redirect({"error": "Доступ к учётной записи закрыт."})
    if row["status"] == "pending":
        return _app_redirect({"error": "Сначала подтвердите почту по письму."})
    if row["status"] != "active":
        return _app_redirect({"error": "Учётная запись не активна."})

    if not row["yandex_id"]:
        pool.execute_with_retries(
            "DECLARE $id AS Utf8; DECLARE $yid AS Utf8; "
            "UPSERT INTO users (id, yandex_id) VALUES ($id, $yid)",
            {
                "$id": (row["id"], ydb.PrimitiveType.Utf8),
                "$yid": (yandex_id, ydb.PrimitiveType.Utf8),
            },
        )
    return _app_redirect(
        {"token": _issue_token(row["id"], row["role"], row["depot_id"] or "")}
    )


def _yandex_signup(pool, body):
    """Регистрация по пропуску от Яндекса.

    Пароля здесь нет вовсе: входить человек будет тем же Яндексом. Почта
    приходит из пропуска и уже подтверждена — письма не шлём, статус сразу
    активный.
    """
    try:
        ticket = jwt.decode(
            body.get("ticket") or "", JWT_SECRET, algorithms=["HS256"]
        )
    except jwt.PyJWTError:
        return _error(400, "Пропуск устарел — войдите через Яндекс заново.")
    if ticket.get("act") != "signup":
        return _error(400, "Неверный пропуск.")

    display_name = (body.get("displayName") or ticket.get("name") or "").strip()
    personnel = (body.get("personnelNumber") or "").strip()
    depot_id = (body.get("depotId") or "").strip()
    role = body.get("role") or "viewer"
    email = (ticket.get("email") or "").strip()

    if len(display_name) < 3:
        return _error(400, "Укажите фамилию и инициалы.")
    if not depot_id:
        return _error(400, "Выберите депо.")
    if role not in ("viewer", "tchm"):
        return _error(400, "При регистрации доступны только ТЧМ и гость.")
    if role != "viewer" and not personnel:
        return _error(400, "Введите табельный номер.")
    if not _invite_ok(pool, depot_id, body.get("inviteCode") or ""):
        return _error(403, "Ключ не подходит к выбранному депо.")

    existing = _find_user_by_yandex(pool, ticket["yid"]) or (
        _find_user_by_email(pool, email.lower()) if email else None
    )
    if existing:
        return _error(409, "Такая учётная запись уже есть — просто войдите.")

    role = _verified_registration_role(email, role)
    user_id = str(uuid.uuid4())
    now = int(time.time() * 1_000_000)
    pool.execute_with_retries(
        """
        DECLARE $id AS Utf8; DECLARE $email AS Utf8;
        DECLARE $email_lower AS Utf8; DECLARE $yid AS Utf8;
        DECLARE $name AS Utf8; DECLARE $personnel AS Utf8;
        DECLARE $depot AS Utf8; DECLARE $role AS Utf8;
        DECLARE $consent AS Utf8; DECLARE $now AS Timestamp;
        UPSERT INTO users (id, email, email_lower, yandex_id, display_name,
            personnel_number, depot_id, role, status, consent_version,
            consent_at, created_at)
        VALUES ($id, $email, $email_lower, $yid, $name, $personnel, $depot,
            $role, "active", $consent, $now, $now)
        """,
        {
            "$id": (user_id, ydb.PrimitiveType.Utf8),
            "$email": (email, ydb.PrimitiveType.Utf8),
            "$email_lower": (email.lower(), ydb.PrimitiveType.Utf8),
            "$yid": (str(ticket["yid"]), ydb.PrimitiveType.Utf8),
            "$name": (display_name, ydb.PrimitiveType.Utf8),
            "$personnel": (personnel, ydb.PrimitiveType.Utf8),
            "$depot": (depot_id, ydb.PrimitiveType.Utf8),
            "$role": (role, ydb.PrimitiveType.Utf8),
            "$consent": (
                body.get("consentVersion") or "",
                ydb.PrimitiveType.Utf8,
            ),
            "$now": (now, ydb.PrimitiveType.Timestamp),
        },
    )
    return _reply(
        200,
        {
            "token": _issue_token(user_id, role, depot_id),
            "user": {
                "id": user_id,
                "email": email,
                "displayName": display_name,
                "personnelNumber": personnel,
                "depotId": depot_id,
                "role": role,
                "status": "active",
            },
        },
    )


def _me(pool, claims):
    result = pool.execute_with_retries(
        "DECLARE $id AS Utf8; SELECT * FROM users WHERE id = $id LIMIT 1",
        {"$id": (claims["sub"], ydb.PrimitiveType.Utf8)},
    )
    rows = result[0].rows
    if not rows:
        return _error(404, "Профиль не найден.")
    if rows[0]["status"] != "active":
        return _error(403, "Учётная запись не активна.")
    return _reply(200, {"user": _user_public(rows[0])})


def _request_path(event) -> str:
    """Путь запроса.

    API Gateway кладёт его не всегда в одно и то же место: у интеграции с
    функцией это `path`, но при шаблоне `{proxy+}` туда попадает шаблон, а
    настоящий путь — в requestContext. Берём первое непустое.
    """
    candidates = [
        (event.get("requestContext") or {}).get("resourcePath"),
        ((event.get("requestContext") or {}).get("http") or {}).get("path"),
        event.get("url"),
        event.get("path"),
    ]
    for value in candidates:
        if isinstance(value, str) and value and "{" not in value:
            return value.split("?")[0].rstrip("/") or "/"
    proxy = (event.get("pathParams") or {}).get("proxy")
    if isinstance(proxy, str) and proxy:
        return "/" + proxy.strip("/")
    return "/"


# ---- данные: колонны и машинисты --------------------------------------
# Права проверяются здесь, на сервере, а не в приложении. Это и есть смысл
# переезда: раньше клиент сам решал, что ему можно, и правила Firestore
# принимали его слово.

# Гость смотрит своё депо, ТЧМ ведёт его данные. Администратор и
# разработчик работают со всеми депо; режим обслуживания — только у
# разработчика. Оператор и инструктор здесь не используются.
ROLES = ("viewer", "tchm", "admin", "developer")
MANAGEMENT_ROLES = ("admin", "developer")
EDIT_ANY_ROLES = ("tchm", "admin", "developer")


def _auth(pool, headers):
    """Кто пришёл. Роль и депо берём из базы, а не из токена.

    В токене они тоже лежат, но токен живёт неделю: за это время человека
    могут отключить или сменить ему роль, и полагаться на слепок недельной
    давности нельзя.
    """
    claims = _read_token(headers)
    if not claims:
        return None
    result = pool.execute_with_retries(
        "DECLARE $id AS Utf8; SELECT * FROM users WHERE id = $id LIMIT 1",
        {"$id": (claims["sub"], ydb.PrimitiveType.Utf8)},
    )
    rows = result[0].rows
    if not rows or rows[0]["status"] != "active":
        return None
    return rows[0]


def _scope_depot(user, params):
    """Депо, с которым разрешено работать этому запросу.

    Администратор и разработчик работают со всеми депо; без фильтра — все.
    Остальным депо навязывается из профиля, и подменить его запросом нельзя.
    """
    if user["role"] in MANAGEMENT_ROLES:
        return (params or {}).get("depotId")
    return user["depot_id"]


def _can_edit_column(user, column_id: str) -> bool:
    """Колонны депо правит ТЧМ. Привязки человека к одной колонне нет:
    она нужна была только инструктору, которого не существует."""
    return user["role"] in EDIT_ANY_ROLES


def _users_list(pool, user, params):
    """Список учётных записей. Администратору и разработчику.

    В старой базе `users` читал любой вошедший — гость видел ФИО, табельные
    и почты всех депо. Здесь так не будет: список нужен ровно одному экрану
    обслуживания, остальным он не положен.
    """
    if user["role"] not in MANAGEMENT_ROLES:
        return _error(403, "Список учётных записей доступен администратору и разработчику.")
    depot = (params or {}).get("depotId")
    if depot:
        result = pool.execute_with_retries(
            "DECLARE $depot AS Utf8; SELECT * FROM users WHERE depot_id = $depot",
            {"$depot": (depot, ydb.PrimitiveType.Utf8)},
        )
    else:
        result = pool.execute_with_retries("SELECT * FROM users")
    return _reply(
        200,
        {
            "users": [
                {
                    "id": row["id"],
                    "email": row["email"],
                    "displayName": row["display_name"],
                    "personnelNumber": row["personnel_number"],
                    "depotId": row["depot_id"],
                    "role": row["role"],
                    "status": row["status"],
                }
                for row in result[0].rows
            ]
        },
    )


def _lock_read(pool):
    rows = pool.execute_with_retries(
        "SELECT * FROM app_config WHERE id = \"app\""
    )[0].rows
    if not rows:
        return {"writesBlocked": False, "readsBlocked": False, "note": ""}
    row = rows[0]
    return {
        "writesBlocked": bool(row["writes_blocked"]),
        "readsBlocked": bool(row["reads_blocked"]),
        "note": row["note"] or "",
        "updatedBy": row["updated_by"] or "",
    }


def _maintenance_guard(pool, user, method):
    """Check every data request, including requests made outside the app.

    Identity/authentication and /lock remain available for recovery. Developers
    may inspect data during a blackout, but cannot modify it until unlocked.
    """
    lock = _lock_read(pool)
    writing = method not in ("GET", "HEAD", "OPTIONS")
    if lock["readsBlocked"] and (writing or user["role"] != "developer"):
        return _reply(503, {
            "error": "Ведутся технические работы. Доступ к данным временно закрыт.",
            "code": "maintenance_full",
            "lock": lock,
        })
    if writing and lock["writesBlocked"]:
        return _reply(503, {
            "error": "Идут технические работы. Доступен только просмотр данных.",
            "code": "maintenance_read_only",
            "lock": lock,
        })
    return None


def _lock_write(pool, user, body):
    if user["role"] != "developer":
        return _error(403, "Режим обслуживания доступен разработчику.")
    pool.execute_with_retries(
        """
        DECLARE $writes AS Bool; DECLARE $reads AS Bool;
        DECLARE $note AS Utf8; DECLARE $by AS Utf8;
        DECLARE $now AS Timestamp;
        UPSERT INTO app_config (id, writes_blocked, reads_blocked, note,
            updated_by, updated_at)
        VALUES ("app", $writes, $reads, $note, $by, $now)
        """,
        {
            "$writes": (bool(body.get("writesBlocked")), ydb.PrimitiveType.Bool),
            "$reads": (bool(body.get("readsBlocked")), ydb.PrimitiveType.Bool),
            "$note": (str(body.get("note") or ""), ydb.PrimitiveType.Utf8),
            "$by": (user["display_name"] or "", ydb.PrimitiveType.Utf8),
            "$now": (int(time.time() * 1_000_000), ydb.PrimitiveType.Timestamp),
        },
    )
    return _reply(200, _lock_read(pool))


def _users_status(pool, user, body):
    """Закрыть или открыть доступ учётным записям.

    Список, а не одна запись: у человека может быть несколько профилей, и
    закрывать надо все разом — иначе войдёт под оставшимся.
    """
    if user["role"] not in MANAGEMENT_ROLES:
        return _error(403, "Закрывать доступ может администратор или разработчик.")
    status = body.get("status")
    if status not in ("active", "disabled"):
        return _error(400, "Статус может быть active или disabled.")
    ids = [str(i) for i in (body.get("userIds") or []) if str(i)]
    if not ids:
        return _error(400, "Не указано, кому менять доступ.")
    if user["id"] in ids and status == "disabled":
        return _error(400, "Себе доступ не закрывают.")
    # Проверяем весь набор до первой записи: администратор не может
    # отключить/удалить разработчика, в том числе смешанным запросом.
    if user["role"] == "admin":
        for user_id in ids:
            rows = pool.execute_with_retries(
                "DECLARE $id AS Utf8; SELECT role FROM users WHERE id = $id",
                {"$id": (user_id, ydb.PrimitiveType.Utf8)},
            )[0].rows
            if rows and rows[0]["role"] == "developer":
                return _error(403, "Учётную запись разработчика меняет только разработчик.")
    for user_id in ids:
        pool.execute_with_retries(
            "DECLARE $id AS Utf8; DECLARE $status AS Utf8; "
            "UPDATE users SET status = $status WHERE id = $id"
            + (' AND role != "developer"' if user["role"] == "admin" else ""),
            {
                "$id": (user_id, ydb.PrimitiveType.Utf8),
                "$status": (status, ydb.PrimitiveType.Utf8),
            },
        )
    return _reply(200, {"changed": len(ids), "status": status})


def _users_delete(pool, user, body):
    if user["role"] not in MANAGEMENT_ROLES:
        return _error(403, "Удалять учётные записи может администратор или разработчик.")
    ids = [str(i) for i in (body.get("userIds") or []) if str(i)]
    if not ids:
        return _error(400, "Не указано, кого удалять.")
    if user["id"] in ids:
        return _error(400, "Себя не удаляют.")
    # Проверяем весь набор до первой записи: администратор не может
    # отключить/удалить разработчика, в том числе смешанным запросом.
    if user["role"] == "admin":
        for user_id in ids:
            rows = pool.execute_with_retries(
                "DECLARE $id AS Utf8; SELECT role FROM users WHERE id = $id",
                {"$id": (user_id, ydb.PrimitiveType.Utf8)},
            )[0].rows
            if rows and rows[0]["role"] == "developer":
                return _error(403, "Учётную запись разработчика меняет только разработчик.")
    for user_id in ids:
        pool.execute_with_retries(
            "DECLARE $id AS Utf8; DELETE FROM users WHERE id = $id"
            + (' AND role != "developer"' if user["role"] == "admin" else ""),
            {"$id": (user_id, ydb.PrimitiveType.Utf8)},
        )
    return _reply(200, {"deleted": len(ids)})


def _columns_list(pool, user, params):
    depot = _scope_depot(user, params)
    if not depot and user["role"] not in MANAGEMENT_ROLES:
        return _reply(200, {"columns": []})
    if depot:
        result = pool.execute_with_retries(
            "DECLARE $depot AS Utf8; "
            "SELECT * FROM columns VIEW idx_depot WHERE depot_id = $depot",
            {"$depot": (depot, ydb.PrimitiveType.Utf8)},
        )
    else:
        result = pool.execute_with_retries("SELECT * FROM columns")
    rows = sorted(result[0].rows, key=lambda r: r["number"] or 0)
    return _reply(
        200,
        {
            "columns": [
                {
                    "id": r["id"],
                    "depotId": r["depot_id"],
                    "number": r["number"],
                    "title": r["title"],
                    "tchmName": r["tchm_name"],
                    "tchmPersonnelNumber": r["tchm_personnel_number"],
                    "instructorName": r["instructor_name"],
                }
                for r in rows
            ]
        },
    )


def _column_save(pool, user, body, column_id=None):
    if user["role"] not in EDIT_ANY_ROLES:
        return _error(403, "Менять колонны может только ТЧМ.")
    depot = _scope_depot(user, body) or user["depot_id"]
    number = body.get("number")
    if type(number) is not int or not 0 < number <= 4_294_967_295:
        return _error(400, "Номер колонны — целое число от 1 до 4294967295.")
    # Номер уникален внутри депо, поэтому он же и идентификатор документа.
    target = column_id or f"{depot}_column_{number}"
    if column_id:
        existing = pool.execute_with_retries(
            "DECLARE $id AS Utf8; SELECT depot_id FROM columns WHERE id = $id",
            {"$id": (column_id, ydb.PrimitiveType.Utf8)},
        )[0].rows
        if not existing:
            return _error(404, "Колонна не найдена.")
        if user["role"] in MANAGEMENT_ROLES:
            depot = existing[0]["depot_id"]
        if existing[0]["depot_id"] != depot:
            return _error(403, "Колонна принадлежит другому депо.")
    if not depot:
        return _error(400, "Укажите депо для колонны.")
    declarations = """
        DECLARE $id AS Utf8; DECLARE $depot AS Utf8; DECLARE $number AS Uint32;
        DECLARE $title AS Utf8; DECLARE $tchm AS Utf8;
        DECLARE $tchm_num AS Utf8; DECLARE $instructor AS Utf8;
        DECLARE $now AS Timestamp;
        """
    if column_id:
        statement = """
        UPDATE columns SET number = $number, title = $title, tchm_name = $tchm,
            tchm_personnel_number = $tchm_num, instructor_name = $instructor,
            updated_at = $now
        WHERE id = $id AND depot_id = $depot
        RETURNING id;
        """
    else:
        # INSERT makes duplicate creation atomic, including concurrent POSTs.
        statement = """
        INSERT INTO columns (id, depot_id, number, title, tchm_name,
            tchm_personnel_number, instructor_name, updated_at)
        VALUES ($id, $depot, $number, $title, $tchm, $tchm_num,
            $instructor, $now)
        """
    parameters = {
        "$id": (target, ydb.PrimitiveType.Utf8),
        "$depot": (depot, ydb.PrimitiveType.Utf8),
        "$number": (number, ydb.PrimitiveType.Uint32),
        "$title": (
            body.get("title") or f"Колонна №{number}",
            ydb.PrimitiveType.Utf8,
        ),
        "$tchm": (body.get("tchmName") or "", ydb.PrimitiveType.Utf8),
        "$tchm_num": (
            body.get("tchmPersonnelNumber") or "",
            ydb.PrimitiveType.Utf8,
        ),
        "$instructor": (
            body.get("instructorName") or "",
            ydb.PrimitiveType.Utf8,
        ),
        "$now": (int(time.time() * 1_000_000), ydb.PrimitiveType.Timestamp),
    }
    try:
        result = pool.execute_with_retries(declarations + statement, parameters)
    except ydb.PreconditionFailed as error:
        # Query Service and older YDB engines use different conflict messages.
        duplicate = any(text in str(error) for text in (
            "insert_pk", "Conflict with existing key",
        ))
        if not column_id and duplicate:
            return _error(409, f"Колонна №{number} уже существует в этом депо.")
        raise
    if column_id and not result[0].rows:
        return _error(404, "Колонна не найдена или больше не принадлежит этому депо.")
    return _reply(200, {"id": target})


class _TransactionQueries:
    """Run the handler's queries in one serializable transaction."""
    def __init__(self, tx):
        self.tx = tx

    def execute_with_retries(self, query, parameters=None):
        with self.tx.execute(query, parameters) as results:
            return list(results)


def _transactional(pool, operation):
    def run(session):
        with session.transaction(ydb.QuerySerializableReadWrite()) as tx:
            result = operation(_TransactionQueries(tx))
            if result['statusCode'] < 400:
                tx.commit()
            else:
                tx.rollback()
            return result
    return pool.retry_operation_sync(run)


def _column_delete(pool, user, column_id):
    if user['role'] not in EDIT_ANY_ROLES:
        return _error(403, 'Нет прав на удаление колонны.')

    def remove(queries):
        params = {'$id': (column_id, ydb.PrimitiveType.Utf8)}
        rows = queries.execute_with_retries(
            'DECLARE $id AS Utf8; SELECT depot_id FROM columns WHERE id = $id',
            params,
        )[0].rows
        if not rows:
            return _error(404, 'Колонна не найдена.')
        if (user['role'] not in MANAGEMENT_ROLES
                and rows[0]['depot_id'] != user['depot_id']):
            return _error(403, 'Колонна принадлежит другому депо.')
        occupied = queries.execute_with_retries(
            'DECLARE $id AS Utf8; SELECT id FROM machinists WHERE column_id = $id LIMIT 1',
            params,
        )[0].rows
        if occupied:
            return _error(409, 'Сначала перенесите машинистов в другую колонну.')
        queries.execute_with_retries(
            'DECLARE $id AS Utf8; DELETE FROM columns WHERE id = $id', params,
        )
        return _reply(200, {'id': column_id})

    return _transactional(pool, remove)


MACHINIST_FIELDS = {
    "fullName": "full_name",
    "classRank": "class_rank",
    "workStart": "work_start",
    "ticket": "ticket",
    "kip": "kip",
    "tra": "tra",
    "atz": "atz",
    "coupling": "coupling",
    "vn": "vn",
    "notes": "notes",
    "kipExtensionOrder": "kip_extension_order",
}


def _machinists_list(pool, user, params):
    depot = _scope_depot(user, params)
    if not depot and user["role"] not in MANAGEMENT_ROLES:
        return _reply(200, {"machinists": []})
    if depot:
        result = pool.execute_with_retries(
            "DECLARE $depot AS Utf8; "
            "SELECT * FROM machinists VIEW idx_depot WHERE depot_id = $depot",
            {"$depot": (depot, ydb.PrimitiveType.Utf8)},
        )
    else:
        result = pool.execute_with_retries("SELECT * FROM machinists")
    rows = result[0].rows
    column_id = (params or {}).get("columnId")
    if column_id:
        rows = [r for r in rows if r["column_id"] == column_id]
    out = []
    for r in rows:
        item = {
            "id": r["id"],
            "depotId": r["depot_id"],
            "columnId": r["column_id"],
            "kipExtensionMonths": r["kip_extension_months"] or 0,
            "updatedBy": r["updated_by"],
        }
        for api_name, column in MACHINIST_FIELDS.items():
            item[api_name] = r[column]
        out.append(item)
    out.sort(key=lambda m: (m["columnId"] or "", m["fullName"] or ""))
    return _reply(200, {"machinists": out})


def _machinist_save(pool, user, body, machinist_id=None):
    # Column existence and saving must be atomic with column deletion.
    return _transactional(
        pool, lambda queries: _machinist_save_transaction(queries, user, body, machinist_id),
    )


def _machinist_save_transaction(pool, user, body, machinist_id=None):
    column_id = body.get("columnId") or ""
    if not column_id:
        return _error(400, "Не указана колонна.")
    if not _can_edit_column(user, column_id):
        return _error(403, "Нет прав на эту колонну.")
    column = pool.execute_with_retries(
        "DECLARE $id AS Utf8; SELECT depot_id FROM columns WHERE id = $id",
        {"$id": (column_id, ydb.PrimitiveType.Utf8)},
    )[0].rows
    if not column:
        return _error(404, "Колонна не найдена.")
    depot = _scope_depot(user, {"depotId": column[0]["depot_id"]})
    if column[0]["depot_id"] != depot:
        return _error(403, "Колонна принадлежит другому депо.")
    if machinist_id:
        existing = pool.execute_with_retries(
            "DECLARE $id AS Utf8; SELECT depot_id FROM machinists WHERE id = $id",
            {"$id": (machinist_id, ydb.PrimitiveType.Utf8)},
        )[0].rows
        if not existing:
            return _error(404, "Машинист не найден.")
        if existing[0]["depot_id"] != depot:
            return _error(403, "Запись принадлежит другому депо.")
    target = machinist_id or str(uuid.uuid4())
    values = {
        "$id": (target, ydb.PrimitiveType.Utf8),
        "$depot": (depot, ydb.PrimitiveType.Utf8),
        "$column": (column_id, ydb.PrimitiveType.Utf8),
        "$months": (
            int(body.get("kipExtensionMonths") or 0),
            ydb.PrimitiveType.Uint32,
        ),
        "$now": (int(time.time() * 1_000_000), ydb.PrimitiveType.Timestamp),
        "$by": (user["display_name"] or "", ydb.PrimitiveType.Utf8),
    }
    for api_name, column_name in MACHINIST_FIELDS.items():
        values[f"${column_name}"] = (
            str(body.get(api_name) or ""),
            ydb.PrimitiveType.Utf8,
        )
    declares = " ".join(f"DECLARE {k} AS Utf8;" for k in values if k not in
                        ("$months", "$now"))
    columns_sql = ", ".join(MACHINIST_FIELDS.values())
    params_sql = ", ".join(f"${c}" for c in MACHINIST_FIELDS.values())
    pool.execute_with_retries(
        f"""
        {declares} DECLARE $months AS Uint32; DECLARE $now AS Timestamp;
        UPSERT INTO machinists (id, depot_id, column_id, {columns_sql},
            kip_extension_months, updated_at, updated_by)
        VALUES ($id, $depot, $column, {params_sql}, $months, $now, $by)
        """,
        values,
    )
    return _reply(200, {"id": target})


def _machinist_delete(pool, user, machinist_id):
    rows = pool.execute_with_retries(
        "DECLARE $id AS Utf8; "
        "SELECT depot_id, column_id FROM machinists WHERE id = $id",
        {"$id": (machinist_id, ydb.PrimitiveType.Utf8)},
    )[0].rows
    if not rows:
        return _error(404, "Машинист не найден.")
    depot = _scope_depot(user, {"depotId": rows[0]["depot_id"]})
    if rows[0]["depot_id"] != depot:
        return _error(403, "Запись принадлежит другому депо.")
    if not _can_edit_column(user, rows[0]["column_id"]):
        return _error(403, "Нет прав на эту колонну.")
    pool.execute_with_retries(
        "DECLARE $id AS Utf8; DELETE FROM machinists WHERE id = $id",
        {"$id": (machinist_id, ydb.PrimitiveType.Utf8)},
    )
    return _reply(200, {"deleted": machinist_id})


# ---- служебные операции ----------------------------------------------
# Доступны только прямым вызовом функции (yc serverless function invoke),
# где пускает IAM облака. Через шлюз сюда не попасть: у HTTP-события всегда
# есть httpMethod, и такие вызовы уходят в обычную маршрутизацию.
#
# Отдельного админ-пароля намеренно нет: общий секрет пришлось бы кому-то
# передавать и где-то хранить, а право на вызов функции и так есть только у
# владельца облака.

INVITE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTVWXYZ"


def _admin(pool, request):
    action = request.get("action")

    if action == "issue_invite":
        depot_id = (request.get("depotId") or "").strip()
        if not depot_id:
            return {"error": "Нужен depotId."}
        prefix = (request.get("prefix") or depot_id[:5].upper()).ljust(5, "X")
        code = request.get("code") or "{}-{}-{}-{}".format(
            prefix[:5],
            "".join(secrets.choice(INVITE_ALPHABET) for _ in range(4)),
            "".join(secrets.choice(INVITE_ALPHABET) for _ in range(4)),
            "".join(secrets.choice(INVITE_ALPHABET) for _ in range(4)),
        )
        normalized = re.sub(r"[^0-9A-Z]", "", code.upper())
        salt = secrets.token_hex(16)
        fingerprint = hashlib.sha256((salt + normalized).encode()).hexdigest()
        pool.execute_with_retries(
            "DECLARE $depot AS Utf8; DECLARE $fp AS Utf8; "
            "DECLARE $salt AS Utf8; DECLARE $role AS Utf8; "
            "UPSERT INTO depot_invites (depot_id, fingerprint, salt, role) "
            "VALUES ($depot, $fp, $salt, $role)",
            {
                "$depot": (depot_id, ydb.PrimitiveType.Utf8),
                "$fp": (fingerprint, ydb.PrimitiveType.Utf8),
                "$salt": (salt, ydb.PrimitiveType.Utf8),
                "$role": (request.get("role") or "tchm", ydb.PrimitiveType.Utf8),
            },
        )
        # Ключ показывается один раз — в базе лежит только отпечаток.
        return {"depotId": depot_id, "code": code}

    if action == "issue_invites":
        # Пачкой: ключи живут списком, по одному на депо, и руководителю
        # передаётся строка его депо. Выпускать их по одному вызову значило
        # бы двадцать четыре раза повторить одно и то же.
        issued = []
        for depot_id in request.get("depotIds") or []:
            depot_id = (depot_id or "").strip()
            if not depot_id:
                continue
            prefix = depot_id.upper()[:5].ljust(5, "X")
            code = "{}-{}-{}-{}".format(
                prefix,
                "".join(secrets.choice(INVITE_ALPHABET) for _ in range(4)),
                "".join(secrets.choice(INVITE_ALPHABET) for _ in range(4)),
                "".join(secrets.choice(INVITE_ALPHABET) for _ in range(4)),
            )
            normalized = re.sub(r"[^0-9A-Z]", "", code)
            salt = secrets.token_hex(16)
            fingerprint = hashlib.sha256(
                (salt + normalized).encode()
            ).hexdigest()
            pool.execute_with_retries(
                "DECLARE $depot AS Utf8; DECLARE $fp AS Utf8; "
                "DECLARE $salt AS Utf8; DECLARE $role AS Utf8; "
                "UPSERT INTO depot_invites (depot_id, fingerprint, salt, role) "
                "VALUES ($depot, $fp, $salt, $role)",
                {
                    "$depot": (depot_id, ydb.PrimitiveType.Utf8),
                    "$fp": (fingerprint, ydb.PrimitiveType.Utf8),
                    "$salt": (salt, ydb.PrimitiveType.Utf8),
                    "$role": (
                        request.get("role") or "tchm",
                        ydb.PrimitiveType.Utf8,
                    ),
                },
            )
            issued.append({"depotId": depot_id, "code": code})
        return {"issued": issued}

    if action == "revoke_invite":
        depot_id = (request.get("depotId") or "").strip()
        pool.execute_with_retries(
            "DECLARE $depot AS Utf8; "
            "DELETE FROM depot_invites WHERE depot_id = $depot",
            {"$depot": (depot_id, ydb.PrimitiveType.Utf8)},
        )
        return {"revoked": depot_id}

    if action == "list_invites":
        result = pool.execute_with_retries(
            "SELECT depot_id, role FROM depot_invites"
        )
        return {
            "invites": [
                {"depotId": row["depot_id"], "role": row["role"]}
                for row in result[0].rows
            ]
        }

    if action == "set_role":
        email = (request.get("email") or "").strip().lower()
        role = request.get("role") or "viewer"
        if role not in ROLES:
            return {"error": f"Роли «{role}» не существует. Есть: {', '.join(ROLES)}"}
        row = _find_user_by_email(pool, email)
        if not row:
            return {"error": "Нет такой учётной записи."}
        pool.execute_with_retries(
            "DECLARE $id AS Utf8; DECLARE $role AS Utf8; "
            "UPSERT INTO users (id, role) VALUES ($id, $role)",
            {
                "$id": (row["id"], ydb.PrimitiveType.Utf8),
                "$role": (role, ydb.PrimitiveType.Utf8),
            },
        )
        return {"email": email, "role": role}

    if action == "import_columns":
        # Перенос из Firestore. Идентификаторы сохраняем как были: на них
        # ссылаются машинисты, и перенумеровать их значило бы порвать связь.
        written = 0
        for item in request.get("columns") or []:
            pool.execute_with_retries(
                """
                DECLARE $id AS Utf8; DECLARE $depot AS Utf8;
                DECLARE $number AS Uint32; DECLARE $title AS Utf8;
                DECLARE $tchm AS Utf8; DECLARE $tchm_num AS Utf8;
                DECLARE $instructor AS Utf8; DECLARE $now AS Timestamp;
                UPSERT INTO columns (id, depot_id, number, title, tchm_name,
                    tchm_personnel_number, instructor_name, updated_at)
                VALUES ($id, $depot, $number, $title, $tchm, $tchm_num,
                    $instructor, $now)
                """,
                {
                    "$id": (str(item.get("id")), ydb.PrimitiveType.Utf8),
                    "$depot": (str(item.get("depotId") or ""), ydb.PrimitiveType.Utf8),
                    "$number": (int(item.get("number") or 0), ydb.PrimitiveType.Uint32),
                    "$title": (str(item.get("title") or ""), ydb.PrimitiveType.Utf8),
                    "$tchm": (str(item.get("tchmName") or ""), ydb.PrimitiveType.Utf8),
                    "$tchm_num": (
                        str(item.get("tchmPersonnelNumber") or ""),
                        ydb.PrimitiveType.Utf8,
                    ),
                    "$instructor": (
                        str(item.get("instructorName") or ""),
                        ydb.PrimitiveType.Utf8,
                    ),
                    "$now": (
                        int(time.time() * 1_000_000),
                        ydb.PrimitiveType.Timestamp,
                    ),
                },
            )
            written += 1
        return {"written": written}

    if action == "import_machinists":
        written = 0
        columns_sql = ", ".join(MACHINIST_FIELDS.values())
        params_sql = ", ".join(f"${c}" for c in MACHINIST_FIELDS.values())
        declares = " ".join(
            f"DECLARE ${c} AS Utf8;" for c in MACHINIST_FIELDS.values()
        )
        for item in request.get("machinists") or []:
            values = {
                "$id": (str(item.get("id")), ydb.PrimitiveType.Utf8),
                "$depot": (
                    str(item.get("depotId") or ""),
                    ydb.PrimitiveType.Utf8,
                ),
                "$column": (
                    str(item.get("columnId") or ""),
                    ydb.PrimitiveType.Utf8,
                ),
                "$months": (
                    int(item.get("kipExtensionMonths") or 0),
                    ydb.PrimitiveType.Uint32,
                ),
                "$by": (
                    str(item.get("updatedBy") or ""),
                    ydb.PrimitiveType.Utf8,
                ),
                "$now": (
                    int(time.time() * 1_000_000),
                    ydb.PrimitiveType.Timestamp,
                ),
            }
            for api_name, column_name in MACHINIST_FIELDS.items():
                values[f"${column_name}"] = (
                    str(item.get(api_name) or ""),
                    ydb.PrimitiveType.Utf8,
                )
            pool.execute_with_retries(
                f"""
                DECLARE $id AS Utf8; DECLARE $depot AS Utf8;
                DECLARE $column AS Utf8; DECLARE $by AS Utf8;
                DECLARE $months AS Uint32; DECLARE $now AS Timestamp;
                {declares}
                UPSERT INTO machinists (id, depot_id, column_id, {columns_sql},
                    kip_extension_months, updated_at, updated_by)
                VALUES ($id, $depot, $column, {params_sql}, $months, $now, $by)
                """,
                values,
            )
            written += 1
        return {"written": written}

    if action == "user_info":
        row = _find_user_by_email(pool, (request.get("email") or "").lower())
        if not row:
            return {"error": "Нет такой учётной записи."}
        return {
            "id": row["id"],
            "email": row["email"],
            "displayName": row["display_name"],
            "role": row["role"],
            "status": row["status"],
            "depotId": row["depot_id"],
        }

    if action == "delete_user":
        email = (request.get("email") or "").strip().lower()
        row = _find_user_by_email(pool, email)
        if not row:
            return {"error": "Нет такой учётной записи."}
        pool.execute_with_retries(
            "DECLARE $id AS Utf8; DELETE FROM users WHERE id = $id",
            {"$id": (row["id"], ydb.PrimitiveType.Utf8)},
        )
        return {"deleted": email}

    if action == "purge_depot":
        # Снос всех данных одного депо: нужен для уборки после проверок.
        depot_id = (request.get("depotId") or "").strip()
        if not depot_id:
            return {"error": "Нужен depotId."}
        for table in ("machinists", "columns", "depot_invites"):
            key = "depot_id"
            pool.execute_with_retries(
                f"DECLARE $depot AS Utf8; "
                f"DELETE FROM {table} WHERE {key} = $depot",
                {"$depot": (depot_id, ydb.PrimitiveType.Utf8)},
            )
        return {"purged": depot_id}

    if action == "stats":
        out = {}
        for table in ("users", "columns", "machinists", "depot_invites"):
            result = pool.execute_with_retries(f"SELECT COUNT(*) AS c FROM {table}")
            out[table] = result[0].rows[0]["c"]
        return out

    return {"error": f"Неизвестное действие: {action}"}


def handler(event, context):
    if "admin" in event and "httpMethod" not in event:
        pool = _connect()
        _ensure_schema(pool)
        return _admin(pool, event["admin"])

    path = _request_path(event)
    method = (event.get("httpMethod") or "GET").upper()
    headers = event.get("headers") or {}

    if path == "/health":
        return _reply(200, {"ok": True, "service": "tchm-api"})

    try:
        pool = _connect()
        _ensure_schema(pool)
    except Exception as error:  # noqa: BLE001 — наружу отдаём общий текст
        return _error(503, f"База недоступна: {error}")

    body = {}
    if event.get("body"):
        try:
            body = json.loads(_raw_body(event))
        except json.JSONDecodeError:
            # Веб-форма смены пароля шлёт form-urlencoded — её разбирает
            # сам обработчик, поэтому здесь это не ошибка.
            body = {}

    try:
        if path == "/auth/register" and method == "POST":
            return _register(pool, body)
        if path == "/auth/login" and method == "POST":
            return _login(pool, body)
        if path == "/auth/verify":
            return _verify(pool, event.get("queryStringParameters"))
        if path == "/auth/forgot" and method == "POST":
            return _forgot(pool, body)
        if path == "/auth/reset":
            if method == "GET":
                return _reset_form(event.get("queryStringParameters"))
            if method == "POST":
                return _reset_apply(pool, event, body)
        if path == "/auth/resend" and method == "POST":
            return _resend(pool, body)
        if path == "/auth/yandex/start":
            return _yandex_start()
        if path == "/auth/yandex/signup" and method == "POST":
            return _yandex_signup(pool, body)
        if path == "/auth/yandex/callback":
            return _yandex_callback(pool, event)
        if path == "/me" and method == "GET":
            claims = _read_token(headers)
            if not claims:
                return _error(401, "Нужен токен входа.")
            return _me(pool, claims)

        # Дальше — только для вошедших. Профиль перечитывается из базы на
        # каждый запрос: закрытый доступ должен срабатывать сразу, а не
        # через неделю, когда истечёт токен.
        if (
            path.startswith("/users")
            or path.startswith("/columns")
            or path.startswith("/machinists")
            or path == "/lock"
        ):
            user = _auth(pool, headers)
            if not user:
                return _error(401, "Нужен токен входа.")
            params = event.get("queryStringParameters") or {}
            parts = [p for p in path.split("/") if p]
            item_id = parts[1] if len(parts) > 1 else None

            if path == "/lock":
                if method == "GET":
                    return _reply(200, _lock_read(pool))
                if method == "PUT":
                    return _lock_write(pool, user, body)

            # Do not cache the flags: each request sees the current lock.
            blocked = _maintenance_guard(pool, user, method)
            if blocked is not None:
                return blocked

            if parts[0] == "users":
                if method == "GET":
                    return _users_list(pool, user, params)
                if method == "PUT" and item_id == "status":
                    return _users_status(pool, user, body)
                if method == "POST" and item_id == "delete":
                    return _users_delete(pool, user, body)

            if parts[0] == "columns":
                if method == "GET":
                    return _columns_list(pool, user, params)
                if method == "POST":
                    return _column_save(pool, user, body)
                if method == "PUT" and item_id:
                    return _column_save(pool, user, body, item_id)
                if method == "DELETE" and item_id:
                    return _column_delete(pool, user, item_id)

            if parts[0] == "machinists":
                if method == "GET":
                    return _machinists_list(pool, user, params)
                if method == "POST":
                    return _machinist_save(pool, user, body)
                if method == "PUT" and item_id:
                    return _machinist_save(pool, user, body, item_id)
                if method == "DELETE" and item_id:
                    return _machinist_delete(pool, user, item_id)
    except Exception as error:  # noqa: BLE001
        return _error(500, f"Ошибка обработки: {error}")

    return _error(404, "Нет такого метода.")
