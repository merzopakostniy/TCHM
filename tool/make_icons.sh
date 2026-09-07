#!/bin/bash
# Раскладывает одну квадратную иконку 1024x1024 по всем размерам Android и iOS.
#
#   ./tool/make_icons.sh assets/brand/app_icon_1024.png
#
# Работает на голом macOS через sips, ничего ставить не нужно.
set -euo pipefail

SRC="${1:-}"
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
  echo "Укажите путь к иконке: ./tool/make_icons.sh assets/brand/app_icon_1024.png" >&2
  exit 1
fi

BG="000713"                      # фон adaptive icon, из values/ic_launcher_background.xml
RES="android/app/src/main/res"
IOS="ios/Runner/Assets.xcassets/AppIcon.appiconset"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

W=$(sips -g pixelWidth "$SRC" | tail -1 | awk '{print $2}')
H=$(sips -g pixelHeight "$SRC" | tail -1 | awk '{print $2}')
echo "исходник: ${W}x${H}"
[ "$W" = "$H" ] || echo "  ВНИМАНИЕ: иконка не квадратная, её растянет"
[ "$W" -ge 1024 ] || echo "  ВНИМАНИЕ: меньше 1024 — крупные размеры будут мылить"

# ---- Android: обычная иконка (её лаунчер показывает как есть) --------------
echo "Android ic_launcher"
for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  dpi="${pair%%:*}"; px="${pair##*:}"
  sips -Z "$px" "$SRC" --out "$RES/mipmap-$dpi/ic_launcher.png" >/dev/null
  echo "  $dpi ${px}px"
done

# ---- Android: adaptive foreground ------------------------------------------
# Маска лаунчера съедает края, гарантированно виден только центр (66%).
# Поэтому картинку вписываем в эти 66%, а поля добиваем цветом фона —
# фон иконки тот же, поэтому шва не видно.
echo "Android ic_launcher_foreground (вписано в безопасную зону)"
for pair in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
  dpi="${pair%%:*}"; px="${pair##*:}"
  inner=$(( px * 66 / 100 ))
  sips -Z "$inner" "$SRC" --out "$TMP/fg.png" >/dev/null
  sips -p "$px" "$px" --padColor "$BG" "$TMP/fg.png" \
       --out "$RES/mipmap-$dpi/ic_launcher_foreground.png" >/dev/null
  echo "  $dpi ${px}px (картинка ${inner}px)"
done

# ---- iOS -------------------------------------------------------------------
# App Store отклоняет иконки с прозрачностью, поэтому альфу схлопываем на
# фон: прогон через jpeg убирает альфа-канал, а поля цветом фона не дают
# появиться светлой рамке.
echo "iOS AppIcon"
if [ "$(sips -g hasAlpha "$SRC" | tail -1 | awk '{print $2}')" = "yes" ]; then
  echo "  в иконке есть прозрачность — подкладываю фон #$BG"
  sips -s format jpeg -s formatOptions 100 "$SRC" --out "$TMP/flat.jpg" >/dev/null
  sips -s format png "$TMP/flat.jpg" --out "$TMP/flat.png" >/dev/null
  BASE="$TMP/flat.png"
else
  BASE="$SRC"
fi

ios_icon() {  # имя, размер
  sips -Z "$2" "$BASE" --out "$IOS/$1" >/dev/null
  echo "  $1 ${2}px"
}
ios_icon Icon-App-20x20@1x.png 20
ios_icon Icon-App-20x20@2x.png 40
ios_icon Icon-App-20x20@3x.png 60
ios_icon Icon-App-29x29@1x.png 29
ios_icon Icon-App-29x29@2x.png 58
ios_icon Icon-App-29x29@3x.png 87
ios_icon Icon-App-40x40@1x.png 40
ios_icon Icon-App-40x40@2x.png 80
ios_icon Icon-App-40x40@3x.png 120
ios_icon Icon-App-60x60@2x.png 120
ios_icon Icon-App-60x60@3x.png 180
ios_icon Icon-App-76x76@1x.png 76
ios_icon Icon-App-76x76@2x.png 152
ios_icon Icon-App-83.5x83.5@2x.png 167
ios_icon tchm_icon_1024x1024.png 1024

echo ""
echo "готово. Пересобрать: flutter clean && flutter build apk --debug"
