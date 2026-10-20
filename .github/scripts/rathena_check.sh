#!/usr/bin/env bash
# Load a mod's server side on the rAthena the app ships, and fail on anything
# the map server says about it.
#
#   rathena_check.sh <app checkout> <mod folder> <RE|PRE>
#
# The same file is in every LilArt420 mod repository (.github/scripts/), run by
# .github/workflows/validate.yml. It follows Flux159/rathena's
# npc_db_validation.yml: configure with --enable-buildbot=yes and load every
# table and script with `map-server --run-once`.
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
# That server already warns a little on its own (population engine commands
# with no atcommands.yml entry, a hidden Companion Recruiter), so buildbot's
# exit status fails with or without a mod. So the server is first run without
# the mod, and a run with it fails on every [Warning] or [Error] line the
# baseline did not have, or if it does not get as far as the baseline did.
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
# libconfig on its own first: in a parallel build its obj/ folder can lose
# the race ("can't create obj/grammar.o: No such file or directory").
make libconfig >/dev/null
make -j"$(nproc)" map >/dev/null
cp -R db/import "$WORK/db-import-clean"
cp conf/import/map_conf.txt "$WORK/map_conf-clean.txt"

say "Database"
sudo systemctl start mysql.service
# The runner's MySQL root login, as in Flux159/rathena's tools/ci/sql.sh.
printf '[client]\nuser=root\npassword=root\n' > ~/.my.cnf
mysql -e "CREATE DATABASE ragnarok;"
for f in main logs roulette_default_data; do mysql ragnarok < "sql-files/$f.sql"; done
mysql -e "CREATE USER 'ragnarok'@'localhost' IDENTIFIED WITH mysql_native_password BY 'ragnarok';"
mysql -e "GRANT SELECT,INSERT,UPDATE,DELETE ON ragnarok.* TO 'ragnarok'@'localhost';"

say "The app's mod code (stack/), with the CI test appended"
cat "$HERE/app_mods_ci.rs" >> "$APP/stack/src/mods.rs"
APP_VERSION=$(jq -r .version "$APP/package.json")
(cd "$APP/stack" && cargo test --no-run -q)

# Runs map-server once; leaves the log in $WORK/<label>.plain, the [Warning]
# and [Error] lines in $WORK/<label>.problems, and the exit status in
# $MS_STATUS.
map_server() {
    local label=$1
    MS_STATUS=0
    ./map-server --run-once > "$WORK/$label.log" 2>&1 || MS_STATUS=$?
    # Without colours, and without the bell rAthena rings after "[Error]:".
    sed 's/\x1b\[[0-9;]*[A-Za-z]//g' "$WORK/$label.log" | tr -d '\000-\010\013-\037' > "$WORK/$label.plain"
    # A script error is "[Error]: " and the details on the next lines: join
    # the first two of them on, so the line says what and where.
    awk '/^[[:space:]]*\[(Warning|Error|Fatal Error)\]/ {
             sub(/^[[:space:]]+/, ""); line = $0
             if (line ~ /\]:[[:space:]]*$/) { for (i = 0; i < 2 && (getline more) > 0; i++) { sub(/^[[:space:]]+/, "", more); line = line " " more } }
             print line }' "$WORK/$label.plain" | sort -u > "$WORK/$label.problems"
}

say "map-server --run-once without the mod (baseline)"
map_server baseline
base_status=$MS_STATUS
echo "exit $base_status; warnings and errors the stock server gives by itself:"
sed 's/^/    /' "$WORK/baseline.problems"
grep -q "Server is 'ready'" "$WORK/baseline.plain" || { tail -50 "$WORK/baseline.plain"; echo "::error::The stock map-server did not start; nothing to compare the mod with."; exit 1; }

# One map-server run with the mod applied under the given settings.
run() {
    local label=$1 settings=$2 status
    say "map-server --run-once, $NAME with $label"
    rm -rf "$WORK/app" "$WORK/state"
    mkdir -p "$WORK/app/db-import" "$WORK/state/mods"
    # The stubs package.sh stages: db/import-tmpl, files only.
    find db/import-tmpl -maxdepth 1 -type f -exec cp {} "$WORK/app/db-import/" \;
    cp -R "$MOD" "$WORK/state/mods/$NAME"
    echo "$NAME" > "$WORK/state/mods/enabled.txt"   # on even if "default": "off"
    if [ "$ERA" = PRE ]; then touch "$WORK/state/prerenewal"; fi
    echo "$settings" > "$WORK/state/mod-settings.json"
    # (Called as `run ... || failed=1`, where set -e is off: check each step.)
    if ! (cd "$APP/stack" && CI_WORK="$WORK" CI_APP_VERSION="$APP_VERSION" \
            cargo test -q -- --ignored ci_mod::assemble_mod --nocapture); then
        echo "::error::The app's mods::assemble did not apply $NAME ($ERA, $label): see above."
        return 1
    fi

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

    map_server "$label"
    status=$MS_STATUS
    # What the server said about the mod's own files, problem or not.
    echo "--- lines naming the mod's files (npc/mods/, db/import/):"
    grep -E "npc/mods/|db/import/" "$WORK/$label.plain" | grep -vE "^\s*\[Status\]: (Loading|Done reading)" | sed 's/^/    /' || true
    grep -E "Loading '[0-9]+' entries in 'db/import/|Done reading '[0-9]+' entries in 'db/import/" "$WORK/$label.plain" | sed 's/^/    /' || true

    local new
    new=$(comm -13 "$WORK/baseline.problems" "$WORK/$label.problems")
    if [ -n "$new" ]; then
        echo "--- map-server log around each new problem:"
        while IFS= read -r line; do
            key=$(grep -o 'script error on [^ ]* line [0-9]*' <<< "$line" || echo "$line")
            grep -n -F -A8 -- "$key" "$WORK/$label.plain" | head -12
            echo "::error::map-server ($ERA, $label): $line"
        done <<< "$new"
    fi
    if ! grep -q "Server is 'ready'" "$WORK/$label.plain"; then
        tail -60 "$WORK/$label.plain"
        echo "::error::map-server ($ERA, $label) stopped before it was ready (exit $status). The end of its log is above."
        return 1
    fi
    if [ "$status" -ne 0 ] && [ "$status" -ne "$base_status" ]; then
        echo "::error::map-server ($ERA, $label) exited with $status; without the mod it exits with $base_status."
        return 1
    fi
    if [ -n "$new" ]; then return 1; fi
    echo "No warnings or errors beyond the stock server's."
}

all_on=$(jq -c --arg n "$NAME" '{($n): ([.settings[]? | select((.type // "boolean") == "boolean") | {(.key): true}] | add // {})}' "$MOD/mod.json")
failed=0
run defaults '{}' || failed=1
if [ "$all_on" != "{\"$NAME\":{}}" ]; then
    run all-switches-on "$all_on" || failed=1
fi
exit $failed
