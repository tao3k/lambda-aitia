// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Executable architectural boundary gate for `aitia-runtime`.
//!
//! Enforces:
//! 1. Thin CLI adapter layer (`src/cli/` contains ONLY argument parsing & I/O, never domain logic).
//! 2. Flat Host Capability Frame Mapper (`src/capability/`) with bidirectional Rust ↔ SysML parity.
//! 3. Zero scope merging or naming-policy mutation in Rust (Scheme owns semantics).

use aitia_runtime::{
    CapabilityError, CapabilityFrame, CapabilityId, HostCapability, HostCapabilityRegistry,
    HostEffectClass, HostReceipt,
};
use std::{
    collections::BTreeSet,
    fs,
    path::{Path, PathBuf},
};

const ALLOWED_TOP_LEVEL_SRC_FILES: &[&str] = &[
    "checks.rs",
    "lib.rs",
    "limits.rs",
    "org_edit.rs",
    "program.rs",
    "project.rs",
    "protocol.rs",
    "pytest.rs",
    "review_provider.rs",
    "session.rs",
    "source_tree.rs",
    "sysml.rs",
];

const ALLOWED_SRC_SUBDIRS: &[&str] = &["bin", "capability", "cli", "commit", "linked"];

// Strict thin-CLI line ceilings: CLI files only parse args, read stdin, call runtime
// library modules, and print stdout. Domain/orchestration logic belongs in core modules.
const CLI_LINE_CEILINGS: &[(&str, usize)] = &[
    ("cli/mod.rs", 20),
    ("cli/dispatch.rs", 150),
    ("cli/flow.rs", 75),
    ("cli/jj.rs", 100),
];

fn collect_rs_files(dir: &Path, out: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(dir).expect("read rust source dir") {
        let path = entry.expect("dir entry").path();
        if path.is_dir() {
            collect_rs_files(&path, out);
        } else if path.extension().and_then(|e| e.to_str()) == Some("rs") {
            out.push(path);
        }
    }
}

#[test]
fn rust_runtime_stays_within_approved_host_frame_mapper_topology() {
    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let allowed_files: BTreeSet<&str> = ALLOWED_TOP_LEVEL_SRC_FILES.iter().copied().collect();
    let allowed_dirs: BTreeSet<&str> = ALLOWED_SRC_SUBDIRS.iter().copied().collect();

    let mut actual_dirs = BTreeSet::new();
    for entry in fs::read_dir(&src_dir).expect("read aitia-runtime/src") {
        let path = entry.expect("read dir entry").path();
        let name = path
            .file_name()
            .and_then(|n| n.to_str())
            .expect("utf-8 filename")
            .to_owned();
        if path.is_dir() {
            assert!(
                allowed_dirs.contains(name.as_str()),
                "Unapproved directory `src/{name}` in aitia-runtime."
            );
            actual_dirs.insert(name);
        } else if path.extension().and_then(|e| e.to_str()) == Some("rs") {
            assert!(
                allowed_files.contains(name.as_str()),
                "Unapproved module `src/{name}` in aitia-runtime: add new host effects under \
                 `src/capability/` and keep higher-order workflows in Scheme POO/ASCENT/FunFlow."
            );
        }
    }
    assert!(
        actual_dirs.contains("capability") && actual_dirs.contains("cli"),
        "aitia-runtime must preserve src/capability/ and thin src/cli/ boundaries"
    );
}

#[test]
fn cli_layer_is_strictly_thin_and_contains_no_domain_logic() {
    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    for &(file, ceiling) in CLI_LINE_CEILINGS {
        let text = fs::read_to_string(src_dir.join(file)).expect("read cli source file");
        let lines = text.lines().count();
        assert!(
            lines <= ceiling,
            "src/{file} grew to {lines} lines (ceiling {ceiling}): keep CLI files strictly thin; \
             place implementation logic in core runtime modules or Scheme."
        );
    }

    let forbidden_in_cli = [
        "ring::signature",
        "struct Governance",
        "drive_scheme_protocol",
        "observe_recorded_sources",
        "audit_recorded_configuration",
        "run_recorded_pytest",
        "reopen_reviewed_description",
        "push_reviewed_description",
    ];
    let mut cli_files = Vec::new();
    collect_rs_files(&src_dir.join("cli"), &mut cli_files);
    assert!(!cli_files.is_empty(), "src/cli/ must exist");
    for path in cli_files {
        let text = fs::read_to_string(&path).expect("read cli file");
        for forbidden in forbidden_in_cli {
            assert!(
                !text.contains(forbidden),
                "{} contains domain implementation `{forbidden}`; move implementation out of src/cli/.",
                path.display()
            );
        }
    }
}

#[test]
fn rust_does_not_mutate_scheme_naming_policy_or_merge_scopes() {
    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut files = Vec::new();
    collect_rs_files(&src_dir, &mut files);
    for path in files {
        let text = fs::read_to_string(&path).expect("read runtime source file");
        assert!(
            !text.contains("merge_sysml_scopes"),
            "{} must not merge SysML scopes into Scheme naming policy in Rust; forward raw `sysmlScopes` receipts to Scheme.",
            path.display()
        );
    }
}

#[test]
fn sysml_v2_owns_project_commit_scopes_not_project_json() {
    let repo_root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let project_json_path = repo_root.join(".agents/aita/project.json");
    let project_json: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(&project_json_path).expect("read project.json"))
            .expect("parse project.json");
    let naming = &project_json["programs"]["jj"]["settings"]["naming"];
    assert!(
        naming.get("scopes").is_none(),
        ".agents/aita/project.json must not declare hand-maintained `naming.scopes`; declare `CommitScope` parts in dev/sysml/project-architecture.sysml."
    );

    let sysml_arch_path = repo_root.join("dev/sysml/project-architecture.sysml");
    let sysml_text =
        fs::read_to_string(&sysml_arch_path).expect("read dev/sysml/project-architecture.sysml");
    assert!(
        sysml_text.contains("part def CommitScope"),
        "dev/sysml/project-architecture.sysml must declare `part def CommitScope`"
    );
    assert!(
        sysml_text.contains("part def HostCapabilitySpec"),
        "dev/sysml/project-architecture.sysml must declare `part def HostCapabilitySpec`"
    );

    // Bidirectional parity gate: EVERY HostCapability registered under src/capability/
    // must be declared as a HostCapabilitySpec in dev/sysml/project-architecture.sysml,
    // and vice versa (0 undocumented or shadow host capabilities).
    let mut cap_files = Vec::new();
    collect_rs_files(
        &Path::new(env!("CARGO_MANIFEST_DIR")).join("src/capability"),
        &mut cap_files,
    );
    let mut rust_caps = BTreeSet::new();
    for path in cap_files {
        let text = fs::read_to_string(&path).expect("read capability source");
        let lines: Vec<&str> = text.lines().collect();
        for window in lines.windows(2) {
            if window[0].contains("fn capability_id(&self) -> &'static str") {
                let trimmed = window[1].trim();
                if let Some(id) = trimmed.strip_prefix('"').and_then(|s| s.strip_suffix('"')) {
                    rust_caps.insert(id.to_owned());
                }
            }
        }
    }
    let mut sysml_caps = BTreeSet::new();
    for line in sysml_text.lines() {
        if let Some(rest) = line.split("capabilityId = \"").nth(1)
            && let Some(id) = rest.split('"').next()
        {
            sysml_caps.insert(id.to_owned());
        }
    }
    assert!(
        !rust_caps.is_empty(),
        "src/capability/ must register at least one HostCapability"
    );
    assert_eq!(
        rust_caps, sysml_caps,
        "Rust HostCapabilityRegistry and dev/sysml/project-architecture.sysml HostCapabilitySpec drifted out of sync!"
    );
}

#[test]
fn host_capability_registry_enforces_fenced_effects_and_zero_authority() {
    struct TestRead;
    impl HostCapability for TestRead {
        fn capability_id(&self) -> &'static str {
            "jj.read-test"
        }
        fn effect_class(&self) -> HostEffectClass {
            HostEffectClass::HostRead
        }
        fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
            Ok(HostReceipt {
                capability: CapabilityId::new(self.capability_id()),
                effect_class: self.effect_class(),
                payload: frame.payload.clone(),
                action_authorized: true,
            })
        }
    }

    struct TestFenced;
    impl HostCapability for TestFenced {
        fn capability_id(&self) -> &'static str {
            "jj.fenced-test"
        }
        fn effect_class(&self) -> HostEffectClass {
            HostEffectClass::FencedEffect
        }
        fn invoke(&self, _frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
            Ok(HostReceipt::observe(
                self.capability_id(),
                self.effect_class(),
                "{}".to_owned(),
            ))
        }
    }

    let mut registry = HostCapabilityRegistry::new();
    registry.register(Box::new(TestRead));
    registry.register(Box::new(TestFenced));

    let unknown = registry.dispatch(&CapabilityFrame {
        capability: CapabilityId::new("missing.capability"),
        effect_class: HostEffectClass::HostRead,
        payload: "{}".to_owned(),
        fence_token: None,
    });
    assert!(matches!(
        unknown,
        Err(CapabilityError::UnknownCapability(_))
    ));

    let mismatch = registry.dispatch(&CapabilityFrame {
        capability: CapabilityId::new("jj.fenced-test"),
        effect_class: HostEffectClass::HostRead,
        payload: "{}".to_owned(),
        fence_token: Some("tok".to_owned()),
    });
    assert!(matches!(
        mismatch,
        Err(CapabilityError::EffectClassMismatch { .. })
    ));

    let missing_token = registry.dispatch(&CapabilityFrame {
        capability: CapabilityId::new("jj.fenced-test"),
        effect_class: HostEffectClass::FencedEffect,
        payload: "{}".to_owned(),
        fence_token: None,
    });
    assert!(matches!(
        missing_token,
        Err(CapabilityError::MissingFenceToken(_))
    ));

    let read = registry
        .dispatch(&CapabilityFrame {
            capability: CapabilityId::new("jj.read-test"),
            effect_class: HostEffectClass::HostRead,
            payload: "{\"ok\":true}".to_owned(),
            fence_token: None,
        })
        .expect("registered read capability succeeds");
    assert!(!read.action_authorized);

    let with_token = registry
        .dispatch(&CapabilityFrame {
            capability: CapabilityId::new("jj.fenced-test"),
            effect_class: HostEffectClass::FencedEffect,
            payload: "{}".to_owned(),
            fence_token: Some("scheme-approved-fence".to_owned()),
        })
        .expect("fenced capability executes with fence token");
    assert!(!with_token.action_authorized);

    // Batch dispatch validates EVERY frame before executing any capability (fail-closed)
    let bad_batch = registry.dispatch_batch(&[
        CapabilityFrame {
            capability: CapabilityId::new("jj.read-test"),
            effect_class: HostEffectClass::HostRead,
            payload: "{}".to_owned(),
            fence_token: None,
        },
        CapabilityFrame {
            capability: CapabilityId::new("jj.fenced-test"),
            effect_class: HostEffectClass::FencedEffect,
            payload: "{}".to_owned(),
            fence_token: None,
        },
    ]);
    assert!(matches!(
        bad_batch,
        Err(CapabilityError::MissingFenceToken(_))
    ));

    let good_batch = registry
        .dispatch_batch(&[
            CapabilityFrame {
                capability: CapabilityId::new("jj.read-test"),
                effect_class: HostEffectClass::HostRead,
                payload: "{\"n\":1}".to_owned(),
                fence_token: None,
            },
            CapabilityFrame {
                capability: CapabilityId::new("jj.fenced-test"),
                effect_class: HostEffectClass::FencedEffect,
                payload: "{}".to_owned(),
                fence_token: Some("tok-1".to_owned()),
            },
        ])
        .expect("valid batch succeeds with zero authority");
    assert_eq!(good_batch.len(), 2);
    assert!(good_batch.iter().all(|receipt| !receipt.action_authorized));
}
