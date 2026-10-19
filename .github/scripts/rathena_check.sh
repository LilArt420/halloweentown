#!/usr/bin/env bash
# Load a mod's server side on the rAthena the app ships, and fail on anything
# the map server says about it.
#
#   rathena_check.sh <app checkout> <mod folder> <RE|PRE>
#
# The same file is in every LilArt420 mod repository (.github/scripts/), run by
# .github/workflows/validate.yml. It follows Flux159/rathena's
# npc_db_validation.yml: configure with --enable-buildbot=yes, which makes
# `map-server --run-once` exit non-zero after any warning or error.
#
# The server is the app's: Flux159/rathena at the app's config/VENDOR_PINS
# commit, with scripts/apply-server-mods.sh applied and its default packet
# version. The mod goes in the way the app puts it in, by the app's own
# mods::assemble (app_mods_ci.rs, appended to the app's stack/src/mods.rs):
# its tables merged into db/import over the stock stubs, custom maps into the
# import map cache, scripts under npc/mods/ with F_ModSetting, and the npc:/map:
# lines map_conf.txt gets. Twice when the mod has yes/no settings: once with
# their defaults, and once with every one of them on, so every when/<key>/
# folder is loaded at least once.
#
# Not covered: conf/groups.yml and atcommands (merged into the app's own
# copies, which this checkout does not have), lua/ hooks (the population
# engine runs them, not the map server), and anything a mod's client/ does.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
APP=$(cd "${1:?app checkout}" && pwd)
MOD=$(cd "${2:?mod folder}" && pwd)
ERA=${3:?RE or PRE}
WORK=${RUNNER_TEMP:-/tmp}/mod-rathena
RA=$WORK/rathena
NAME=$(jq -r .name "$MOD/mod.json")

say() { printf '\n==> %s\n' "$*"; }

say "rAthena at the app's pin, with the app's server mods"
grep -E '^rathena[[:space:]]' "$APP/config/VENDOR_PINS"
bash "$APP/scripts/vendor-fetch.sh" rathena "$RA"
bash "$APP/scripts/apply-server-mods.sh" "$RA"
PACKETVER=$(awk '$2 == "default" { print $1 }' "$APP/config/PACKETVERS")
PRERE=$([ "$ERA" = PRE ] && echo yes || echo no)

say "Build: packetver $PACKETVER, pre-renewal $PRERE, buildbot"
cd "$RA"
./configure --enable-packetver="$PACKETVER" --enable-prere="$PRERE" --enable-buildbot=yes >/dev/null
make import >/dev/null
make -j"$(nproc)" map >/dev/null
cp -R db/import "$WORK/db-import-clean"
cp conf/import/map_conf.txt "$WORK/map_conf-clean.txt"

say "Database"
sudo systemctl start mysql.service
mysql -uroot -proot -e "CREATE DATABASE ragnarok;"
mysql -uroot -proot ragnarok < sql-files/main.sql
mysql -uroot -proot ragnarok < sql-files/logs.sql
mysql -uroot -proot -e "CREATE USER 'ragnarok'@'localhost' IDENTIFIED WITH mysql_native_password BY 'ragnarok';"
mysql -uroot -proot -e "GRANT SELECT,INSERT,UPDATE,DELETE ON ragnarok.* TO 'ragnarok'@'localhost';"

say "The app's mod code (stack/), with the CI test appended"
cat "$HERE/app_mods_ci.rs" >> "$APP/stack/src/mods.rs"
APP_VERSION=$(jq -r .version "$APP/package.json")
(cd "$APP/stack" && cargo test --no-run -q)

# One map-server run with the mod applied under the given settings.
run() {
    local label=$1 settings=$2
    say "map-server --run-once, $NAME with $label"
    rm -rf "$WORK/app" "$WORK/state"
    mkdir -p "$WORK/app/db-import" "$WORK/state/mods"
    # The stubs package.sh stages: db/import-tmpl, files only.
    find db/import-tmpl -maxdepth 1 -type f -exec cp {} "$WORK/app/db-import/" \;
    cp -R "$MOD" "$WORK/state/mods/$NAME"
    echo "$NAME" > "$WORK/state/mods/enabled.txt"   # on even if "default": "off"
    if [ "$ERA" = PRE ]; then touch "$WORK/state/prerenewal"; fi
    echo "$settings" > "$WORK/state/mod-settings.json"
    (cd "$APP/stack" && CI_WORK="$WORK" CI_APP_VERSION="$APP_VERSION" \
        cargo test -q -- --ignored ci_mod::assemble_mod --nocapture)

    # As the app mounts them: the assembled tree replaces db/import, and the
    # scripts go to npc/mods.
    rm -rf db/import npc/mods
    if [ -d "$WORK/state/modbuild/db" ]; then
        cp -R "$WORK/state/modbuild/db" db/import
    else
        cp -R "$WORK/db-import-clean" db/import
    fi
    if [ -d "$WORK/state/modbuild/npc" ]; then cp -R "$WORK/state/modbuild/npc" npc/mods; fi
    cp "$WORK/map_conf-clean.txt" conf/import/map_conf.txt
    cat "$WORK/map_conf_lines.txt" >> conf/import/map_conf.txt
    while IFS=$'\t' read -r file line; do
        if [ -n "$file" ]; then echo "$line" >> "conf/import/$file"; fi
    done < "$WORK/conf_lines.txt"

    local log=$WORK/map-server-$label.log
    set +e
    ./map-server --run-once 2>&1 | tee "$log"
    local status=${PIPESTATUS[0]}
    set -e
    # Name the mod's own lines, so they're findable in a long log.
    if grep -E '\[(Warning|Error|Debug)\]' "$log" | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' | grep -E "npc/mods/|db/import/" ; then
        echo "::error::map-server ($ERA, $label) reported problems in $NAME's files (above)."
    fi
    if [ "$status" -ne 0 ]; then
        echo "::error::map-server --run-once ($ERA, $label) exited with $status: in buildbot mode any warning or error fails. See the log above."
        return 1
    fi
}

defaults='{}'
all_on=$(jq -c --arg n "$NAME" '{($n): ([.settings[]? | select((.type // "boolean") == "boolean") | {(.key): true}] | add // {})}' "$MOD/mod.json")
failed=0
run defaults "$defaults" || failed=1
if [ "$all_on" != "{\"$NAME\":{}}" ]; then
    run all-switches-on "$all_on" || failed=1
fi
exit $failed
