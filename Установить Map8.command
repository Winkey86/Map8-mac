#!/bin/zsh

set -euo pipefail

wine_version="11.14"
wine_url="https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.14/wine-staging-11.14-osx64.tar.xz"
wine_sha256="cc8ff0f2f95e26e591d049092c16898f10718b7c74addfbf6498ad06ca3bab42"

package_dir=$(cd -- "$(dirname -- "$0")" && pwd)
user_home="${HOME:?Не удалось определить домашнюю папку}"
support_root="${MAP8_INSTALL_ROOT:-$user_home/Library/Application Support/Map8}"
applications_dir="${MAP8_APPS_DIR:-$user_home/Applications}"
runtime_dir="$support_root/runtime-$wine_version"
wine_app="$runtime_dir/Wine Staging.app"
wine_bin="$wine_app/Contents/Resources/wine/bin/wine"
game_dir="$support_root/game"
prefix_dir="$support_root/prefix"
launcher_source="$package_dir/launcher/Map8.app"
launcher_target="$applications_dir/Map8.app"
temp_dir=""

pause_on_error() {
    exit_code=$?
    if [[ -n "$temp_dir" && -d "$temp_dir" ]]; then
        /bin/rm -rf "$temp_dir"
    fi
    if (( exit_code != 0 )); then
        print ""
        print "Установка не завершена. Скопируйте текст ошибки и пришлите автору пакета."
        print "Нажмите Enter, чтобы закрыть окно."
        read -r
    fi
    exit "$exit_code"
}
trap pause_on_error EXIT

print ""
print "=== Установка Map8 для macOS ==="
print ""

if [[ ! -f "$package_dir/game/Map8.exe" || ! -f "$package_dir/game/Map8.dir" ]]; then
    print "Ошибка: рядом с установщиком нет папки game с файлами Map8."
    exit 1
fi

if [[ ! -d "$launcher_source" ]]; then
    print "Ошибка: рядом с установщиком нет приложения launcher/Map8.app."
    exit 1
fi

if [[ "$(/usr/bin/uname -m)" == "arm64" ]]; then
    if ! /usr/sbin/pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
        print "Устанавливаю компонент Apple Rosetta 2…"
        /usr/sbin/softwareupdate --install-rosetta --agree-to-license
    fi
fi

/bin/mkdir -p "$support_root" "$applications_dir" "$game_dir" "$prefix_dir"

if [[ ! -x "$wine_bin" ]]; then
    temp_dir=$(/usr/bin/mktemp -d "/private/tmp/map8-install.XXXXXX")
    archive="$temp_dir/wine-staging-$wine_version.tar.xz"

    if [[ -n "${MAP8_WINE_ARCHIVE:-}" && -f "${MAP8_WINE_ARCHIVE}" ]]; then
        print "Проверяю подготовленный пакет Wine…"
        /bin/cp "${MAP8_WINE_ARCHIVE}" "$archive"
    else
        print "Скачиваю бесплатный Wine (это нужно только при первой установке)…"
        /usr/bin/curl -fL --retry 3 --progress-bar "$wine_url" -o "$archive"
    fi

    actual_sha=$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')
    if [[ "$actual_sha" != "$wine_sha256" ]]; then
        print "Ошибка: контрольная сумма Wine не совпала. Установка остановлена."
        exit 1
    fi

    print "Распаковываю Wine…"
    /bin/mkdir -p "$runtime_dir"
    /usr/bin/tar -xf "$archive" -C "$runtime_dir"
    if [[ ! -d "$wine_app" ]]; then
        print "Ошибка: в архиве не найдено приложение Wine Staging.app."
        exit 1
    fi
    /usr/bin/xattr -dr com.apple.quarantine "$wine_app" 2>/dev/null || true
    /bin/rm -rf "$temp_dir"
    temp_dir=""
else
    print "Wine уже установлен — повторно не скачиваю."
fi

print "Копирую Map8…"
/usr/bin/ditto "$package_dir/game" "$game_dir"

print "Создаю приложение Map8…"
/usr/bin/ditto "$launcher_source" "$launcher_target"
/bin/chmod +x "$launcher_target/Contents/MacOS/Map8Launcher"
/usr/bin/xattr -dr com.apple.quarantine "$launcher_target" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$launcher_target" >/dev/null 2>&1

if [[ ! -d "$prefix_dir/drive_c" ]]; then
    print "Первый запуск Wine — подождите немного…"
    /usr/bin/env WINEPREFIX="$prefix_dir" WINEDEBUG=-all \
        "$wine_bin" wineboot --init >"$support_root/install.log" 2>&1
    /usr/bin/env WINEPREFIX="$prefix_dir" WINEDEBUG=-all \
        "$wine_app/Contents/Resources/wine/bin/wineserver" -w >>"$support_root/install.log" 2>&1 || true
fi

print ""
print "Готово. Map8 находится в папке «Программы» вашего пользователя."
print "Сейчас приложение запустится."
print ""

trap - EXIT
if [[ "${MAP8_SKIP_LAUNCH:-0}" == "1" ]]; then
    exit 0
fi
/usr/bin/open "$launcher_target"
/bin/sleep 2

print "Если всё открылось, это окно можно закрыть."
print "Нажмите Enter."
read -r
