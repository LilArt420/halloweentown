#!/usr/bin/env python3
"""Checks a Ragnarok Offline mod the way the app will read it.

The same file is in every LilArt420 mod repository (.github/scripts/), run by
.github/workflows/validate.yml. Rules come from Flux159/ragnarokoffline.app:
docs/MODDING.md (mod.json, settings, when/ folders) and docs/MOD_REGISTRY.md
(release zips, CHANGELOG.md). The app's own manifest reader runs as well, in
the workflow (mods::check_dir); this script adds what it leaves optional but a
published mod needs, and says where a problem is with a GitHub annotation.

  validate_mod.py manifest  <mod dir>                 mod.json, settings, when/ folders
  validate_mod.py yaml      <dir>                     every .yml/.yaml parses with rapidyaml
  validate_mod.py changelog <CHANGELOG.md> <version>  a "## <version>" section exists
  validate_mod.py zip       <zip> <name> [<asset pattern>]
                                                      the release zip installs (MOD_REGISTRY.md)
"""

import fnmatch
import json
import os
import re
import sys
import tempfile
import zipfile

errors = 0


def error(msg, file=None, line=None):
    global errors
    errors += 1
    where = ""
    if file:
        where = f" file={file}" + (f",line={line}" if line else "")
    print(f"::error{where}::{msg}", flush=True)


def warning(msg, file=None):
    where = f" file={file}" if file else ""
    print(f"::warning{where}::{msg}", flush=True)


def output(key, value):
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(f"{key}={value}\n")
    print(f"{key}={value}")


# --- mod.json ---------------------------------------------------------------

KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,39}$")  # mods.rs read_manifest
NAME = re.compile(r"^[a-z0-9_-]+$")                 # MOD_REGISTRY.md: name
VERSION = re.compile(r"^\d+(\.\d+)*([-+][0-9A-Za-z.-]+)?$")
WHEN_LAYERS = ("conf", "npc", "db", "lua")          # MODDING.md: when/<key>/


def check_manifest(mod_dir):
    path = os.path.join(mod_dir, "mod.json")
    if not os.path.isfile(path):
        error(f"No mod.json in {mod_dir}/.")
        return
    try:
        with open(path, encoding="utf-8") as f:
            m = json.load(f)
    except (ValueError, UnicodeDecodeError) as e:
        error(f"mod.json is not valid JSON: {e}", path, getattr(e, "lineno", None))
        return
    if not isinstance(m, dict):
        error("mod.json must be an object, starting with '{'.", path)
        return

    name = m.get("name")
    if not isinstance(name, str) or not NAME.match(name):
        error('mod.json needs "name": lowercase letters, digits, - and _ (the registry folder name).', path)
        name = ""
    version = m.get("version")
    if not isinstance(version, str) or not VERSION.match(version):
        error('mod.json needs "version", dotted numbers like "1.2.0" (the app compares it with release tags).', path)
        version = ""
    req = m.get("requires")
    if not isinstance(req, dict):
        error('mod.json needs "requires", e.g. { "app": ">=1.6.1", "era": "any" }.', path)
        req = {}
    else:
        if "app" not in req:
            error('"requires" has no "app": name the oldest app version the mod works on, e.g. ">=1.6.1".', path)
        unknown = sorted(set(req) - {"app", "era", "mods", "client"})
        if unknown:
            error(f'"requires" has keys the app refuses: {", ".join(unknown)} (it understands app, era, mods and client).', path)
    era = req.get("era", "any")
    if era not in ("renewal", "pre-renewal", "any"):
        error(f'"requires.era" is "{era}"; use "renewal", "pre-renewal" or "any".', path)
        era = "any"

    settings = m.get("settings", [])
    if not isinstance(settings, list):
        error('"settings" must be an array of option objects.', path)
        settings = []
    if len(settings) > 40:
        error(f"mod.json declares {len(settings)} settings; a mod may declare at most 40 (MODDING.md).", path)
    keys = {}
    for i, s in enumerate(settings):
        if not isinstance(s, dict):
            error(f"settings[{i}] must be an object.", path)
            continue
        key = s.get("key")
        if not isinstance(key, str) or not KEY.match(key):
            error(f"settings[{i}]: key {key!r} must be 1-40 letters, digits or underscores and cannot start with a digit.", path)
            continue
        if key in keys:
            error(f'setting "{key}" is declared twice.', path)
        kind = s.get("type", "boolean")
        if kind not in ("boolean", "number", "string"):
            error(f'setting "{key}" has type {kind!r}; use "boolean", "number" or "string".', path)
        keys[key] = kind
        if "default" in s:
            d = s["default"]
            ok = {"boolean": isinstance(d, bool),
                  "number": isinstance(d, (int, float)) and not isinstance(d, bool),
                  "string": isinstance(d, str) and len(d) <= 200}.get(kind, True)
            if not ok:
                error(f'setting "{key}" declares type "{kind}", so its "default" must match that type.', path)
        if len(s.get("label", key)) > 120 or len(s.get("description", "")) > 400:
            error(f'setting "{key}" has a label over 120 or a description over 400 characters.', path)
        if kind == "string" and "max_length" in s and not 1 <= s["max_length"] <= 200:
            error(f'setting "{key}": max_length is at most 200.', path)

    # A when/<key>/ folder for a key that isn't a declared boolean is ignored by
    # the app (only a log line says so): here it fails, as it's surely a typo.
    roots = [mod_dir] + [os.path.join(mod_dir, m[k]) for k in ("renewalFolder", "prerenewalFolder")
                         if isinstance(m.get(k), str)]
    if isinstance(m.get("clientFolders"), dict):
        roots += [os.path.join(mod_dir, v) for v in m["clientFolders"].values() if isinstance(v, str)]
    for root in roots:
        for layer in WHEN_LAYERS:
            when = os.path.join(root, layer, "when")
            if not os.path.isdir(when):
                continue
            for key in sorted(os.listdir(when)):
                if not os.path.isdir(os.path.join(when, key)):
                    continue
                if keys.get(key) != "boolean":
                    error(f"{os.path.relpath(os.path.join(when, key))}/ is switched by \"{key}\", "
                          "which mod.json does not declare as a boolean setting, so the app never loads it.")

    print(f"mod.json: {name} {version}, era {era}, {len(settings)} settings")
    output("name", name)
    output("version", version)
    # Which rAthena builds the mod's scripts are loaded on.
    eras = {"renewal": ["RE"], "pre-renewal": ["PRE"]}.get(era, ["RE", "PRE"])
    output("eras", json.dumps(eras))
    has_server = any(os.path.isdir(os.path.join(r, l)) for r in roots for l in ("npc", "db", "conf", "lua"))
    output("server", "true" if has_server else "false")


# --- YAML -------------------------------------------------------------------

def check_yaml(top):
    import ryml  # pip install rapidyaml: the YAML parser rAthena itself uses

    files = []
    for dirpath, dirnames, filenames in os.walk(top):
        dirnames[:] = sorted(d for d in dirnames if d not in (".git", "node_modules"))
        files += [os.path.join(dirpath, f) for f in sorted(filenames) if f.endswith((".yml", ".yaml"))]
    for path in files:
        rel = os.path.relpath(path, top)
        with open(path, "rb") as f:
            data = f.read()
        # rapidyaml prints the reason on stderr and raises an empty exception,
        # so catch stderr to put the reason in the annotation.
        with tempfile.TemporaryFile() as captured:
            sys.stderr.flush()
            saved = os.dup(2)
            os.dup2(captured.fileno(), 2)
            try:
                ryml.parse_in_arena(data)
                failed = None
            except Exception as e:  # ryml.ExceptionParse and friends
                failed = e
            finally:
                os.dup2(saved, 2)
                os.close(saved)
            captured.seek(0)
            said = captured.read().decode("utf-8", "replace")
        if failed is None:
            continue
        reason = next((l for l in said.splitlines() if "ERROR" in l), "") or str(failed) or type(failed).__name__
        at = re.search(r"line=(\d+)", reason)
        error(f"rapidyaml cannot parse {rel}: {reason.strip()}", rel, at.group(1) if at else None)
    print(f"YAML: {len(files)} files parsed with rapidyaml {getattr(ryml, 'version', '')}".rstrip())


# --- CHANGELOG.md -----------------------------------------------------------

def check_changelog(path, version):
    with open(path, encoding="utf-8") as f:
        lines = [l.rstrip("\n").rstrip() for l in f]
    if f"## {version}" not in lines:
        error(f'CHANGELOG.md has no "## {version}" section; the app shows players that section '
              "as the update's notes (MOD_REGISTRY.md).", path)
    else:
        print(f'CHANGELOG.md has a "## {version}" section.')


# --- release zip ------------------------------------------------------------

# MOD_REGISTRY.md, "What the app refuses".
MAX_ARCHIVE = 50 * 1024 * 1024
MAX_UNPACKED = 96 * 1024 * 1024
MAX_FILES = 2000


def check_zip(path, name, pattern=None):
    asset = os.path.basename(path)
    if pattern and not fnmatch.fnmatch(asset.lower(), pattern.lower()):
        error(f"The release asset would be {asset}, which the registry's pattern {pattern} does not match.")
    size = os.path.getsize(path)
    if size > MAX_ARCHIVE:
        error(f"{asset} is {size / 2**20:.1f} MB; the app refuses archives over 50 MB.")
    with zipfile.ZipFile(path) as z:
        infos = z.infolist()
        files = [i for i in infos if not i.is_dir()]
        unpacked = sum(i.file_size for i in files)
        if len(files) > MAX_FILES:
            error(f"{asset} holds {len(files)} files; the app refuses more than {MAX_FILES}.")
        if unpacked > MAX_UNPACKED:
            error(f"{asset} unpacks to {unpacked / 2**20:.1f} MB; the app refuses more than 96 MB.")
        tops = set()
        for i in infos:
            n = i.filename
            if n.startswith("/") or re.match(r"^[A-Za-z]:", n) or "\\" in n:
                error(f"{asset}: {n} is an absolute or Windows path.")
            if ".." in n.split("/"):
                error(f"{asset}: {n} climbs out of the folder.")
            if (i.external_attr >> 16) & 0o170000 == 0o120000:
                error(f"{asset}: {n} is a symbolic link.")
            first = n.split("/")[0]
            if first in ("__MACOSX", ".DS_Store") or n.endswith("/.DS_Store"):
                error(f"{asset}: {n} is Mac metadata; leave it out.")
            tops.add(first)
        names = {i.filename for i in files}
        if "mod.json" in names:
            manifest = "mod.json"
        elif len(tops) == 1 and f"{next(iter(tops))}/mod.json" in names:
            manifest = f"{next(iter(tops))}/mod.json"
        else:
            error(f"{asset} must have mod.json at the top, or inside its one top-level folder "
                  f"(it has: {', '.join(sorted(tops))}).")
            return
        m = json.loads(z.read(manifest))
        if m.get("name") != name:
            error(f"{asset}: {manifest} names the mod {m.get('name')!r}, not {name!r}.")
        print(f"{asset}: {len(files)} files, {size / 2**20:.1f} MB packed, {unpacked / 2**20:.1f} MB unpacked, "
              f"mod.json at {manifest} (version {m.get('version')})")


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "manifest" and len(argv) == 3:
        check_manifest(argv[2])
    elif cmd == "yaml" and len(argv) == 3:
        check_yaml(argv[2])
    elif cmd == "changelog" and len(argv) == 4:
        check_changelog(argv[2], argv[3])
    elif cmd == "zip" and len(argv) in (4, 5):
        check_zip(argv[2], argv[3], argv[4] if len(argv) == 5 else None)
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
