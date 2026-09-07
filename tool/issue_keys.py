#!/usr/bin/env python3
"""Выпуск ключей регистрации на все депо разом и запись их в КЛЮЧИ_ДЕПО.txt.

Ключи живут списком: по одному на депо, руководителю передаётся строка его
депо. Поэтому выпускаем пачкой, а не по одному вызову.

Запуск из корня проекта:

    python3 tool/issue_keys.py

Скрипт берёт перечень депо из lib/depots.dart, зовёт служебную операцию
функции tchm-api через `yc` (пускает только IAM владельца облака) и
перезаписывает КЛЮЧИ_ДЕПО.txt.

ВАЖНО. Каждый запуск выпускает НОВЫЕ ключи: старые перестают работать сразу.
Файл перезаписывается целиком, поэтому потерянный ключ не восстанавливается —
только выпускается заново.
"""

import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEPOTS = ROOT / "lib" / "depots.dart"
KEYS_FILE = ROOT / "КЛЮЧИ_ДЕПО.txt"
YC = Path.home() / "yandex-cloud" / "bin" / "yc"
FOLDER = "b1gbmm8sm75e9gc1or56"
FUNCTION = "tchm-api"

DEPOT_RE = re.compile(
    r"Depot\(\s*id:\s*'([^']+)'"
    r"(?:\s*,\s*number:\s*(\d+))?"
    r"\s*,\s*name:\s*'([^']+)'",
    re.S,
)


def read_depots():
    text = DEPOTS.read_text(encoding="utf-8")
    # У депо без номера поле number отсутствует, поэтому разбираем два
    # порядка полей: с номером и без.
    depots = []
    for block in re.findall(r"Depot\((.*?)\)", text, re.S):
        ident = re.search(r"id:\s*'([^']+)'", block)
        name = re.search(r"name:\s*'([^']+)'", block)
        number = re.search(r"number:\s*(\d+)", block)
        if not ident or not name:
            continue
        depots.append(
            {
                "id": ident.group(1),
                "name": name.group(1),
                "number": int(number.group(1)) if number else None,
            }
        )
    return depots


def issue(depot_ids):
    payload = json.dumps({"admin": {"action": "issue_invites", "depotIds": depot_ids}})
    result = subprocess.run(
        [
            str(YC),
            "serverless",
            "function",
            "invoke",
            "--name",
            FUNCTION,
            "--folder-id",
            FOLDER,
            "--data",
            payload,
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.exit(f"yc вернул ошибку:\n{result.stderr.strip()}")
    data = json.loads(result.stdout)
    if "issued" not in data:
        sys.exit(f"Неожиданный ответ функции: {data}")
    return {item["depotId"]: item["code"] for item in data["issued"]}


def main():
    depots = read_depots()
    if not depots:
        sys.exit("Не удалось разобрать перечень депо из lib/depots.dart")
    print(f"Депо в справочнике: {len(depots)}")
    codes = issue([d["id"] for d in depots])

    lines = [
        "КЛЮЧИ РЕГИСТРАЦИИ ДЛЯ РУКОВОДИТЕЛЕЙ ДЕПО",
        f"Выпущено {date.today().strftime('%d.%m.%Y')}. Приложение «Нормативы ТЧМ».",
        "",
        "НЕ ХРАНИТЬ В ГИТЕ. НЕ ПЕРЕСЫЛАТЬ ОДНИМ СПИСКОМ.",
        "Каждому руководителю передаётся ТОЛЬКО ключ его депо.",
        "",
        "Кто получил ключ — регистрируется как ТЧМ и правит данные своего",
        "депо, поэтому ключ передаётся лично, а не в общий чат.",
        "Регистр и дефисы при вводе значения не имеют.",
        "",
        "-" * 64,
    ]
    for depot in depots:
        title = (
            f"ТЧ-{depot['number']} «{depot['name']}»"
            if depot["number"]
            else f"«{depot['name']}» (без ТЧ)"
        )
        lines.append(f"{title:<30}{codes.get(depot['id'], '— не выпущен —')}")
    lines += [
        "-" * 64,
        "",
        "Ключи проверяются НА СЕРВЕРЕ: в базе лежит только отпечаток, сам",
        "ключ не хранится нигде. Восстановить потерянный нельзя — выпускается",
        "новый, и старый сразу перестаёт работать.",
        "",
        "ЕСЛИ КЛЮЧ УТЁК",
        "Отозвать одним депо:",
        "  yc serverless function invoke --name tchm-api \\",
        f"    --folder-id {FOLDER} \\",
        "    --data '{\"admin\":{\"action\":\"revoke_invite\",\"depotId\":\"tch16\"}}'",
        "",
        "Перевыпустить все: python3 tool/issue_keys.py",
        "Пересобирать приложение не нужно — ключи живут в базе.",
    ]
    KEYS_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Готово: {KEYS_FILE.name}, ключей {len(codes)}")


if __name__ == "__main__":
    main()
