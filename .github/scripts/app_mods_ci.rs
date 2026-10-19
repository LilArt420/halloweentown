
// Appended to stack/src/mods.rs of a Ragnarok Offline checkout by a mod
// repository's CI (.github/scripts/app_mods_ci.rs in LilArt420's mod repos), so
// the mod is read and assembled by the app's own code rather than a copy of it.
// Run with `cargo test -- --ignored ci_mod::<name>`.
#[cfg(test)]
mod ci_mod {
    use super::*;

    fn var(name: &str) -> String {
        std::env::var(name).unwrap_or_else(|_| panic!("{name} is not set"))
    }

    /// `ragnarok-stack mod-check <dir>`, which the app runs on a downloaded
    /// release before it replaces an installed copy.
    #[test]
    #[ignore]
    fn check() {
        let dir = var("CI_MOD_DIR");
        match check_dir(Path::new(&dir)) {
            Ok(version) => println!("the app's manifest reader accepts {dir}: version {version}"),
            Err(e) => panic!("the app refuses {dir}: {e}"),
        }
    }

    /// `mods::assemble`, as the app runs it before every server start: the
    /// db/import tree (custom map cache included), the npc/mods tree and the
    /// lines map_conf.txt gets, written under CI_WORK for the workflow to
    /// install into a rAthena checkout. CI_WORK/app/db-import holds the stubs
    /// and CI_WORK/state the mod, its settings and the era marker.
    #[test]
    #[ignore]
    fn assemble_mod() {
        let work = PathBuf::from(var("CI_WORK"));
        let cfg = Config {
            root: work.join("app"),
            state: work.join("state"),
            nebula_home: work.join("unused"),
            nebula: work.join("unused"),
            docker: work.join("unused"),
            image: String::new(),
            db_image: String::new(),
            app_version: std::env::var("CI_APP_VERSION").ok(),
            ports: crate::ports::Ports::DEFAULT,
        };
        let out = assemble(&cfg).expect("assembling the mods");
        for (name, why) in &out.refused {
            eprintln!("the app refuses {name}: {why}");
        }
        assert!(out.refused.is_empty(), "the app would not apply every mod");
        assert!(!out.names.is_empty(), "no mod was switched on");
        let mut conf = String::new();
        for (file, pairs) in &out.conf {
            for (k, v) in pairs {
                conf.push_str(&format!("{file}\t{k}: {v}\n"));
            }
        }
        fs::write(work.join("map_conf_lines.txt"), format!("{}{}", out.map_lines, out.npc_lines)).unwrap();
        fs::write(work.join("conf_lines.txt"), conf).unwrap();
        println!("applied: {}; custom maps: {:?}", out.names.join(", "), out.maps);
        print!("{}{}", out.map_lines, out.npc_lines);
    }
}
