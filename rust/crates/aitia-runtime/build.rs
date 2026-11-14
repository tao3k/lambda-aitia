// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

#[cfg(feature = "linked-program")]
fn main() {
    use gerbil_scheme_aot_build::{
        ProgramArchiveContract, ProgramArchiveObservation, ProgramArchiveObserver,
        ProgramArchiveRequest, build_program_archive_with_contract, discover_gambit_gsc_from_env,
    };
    use sha2::{Digest, Sha256};
    use std::{env, fs::File, path::PathBuf};

    struct CargoInputs;
    impl ProgramArchiveObserver for CargoInputs {
        fn observe(&self, _observation: ProgramArchiveObservation<'_>) {}

        fn observe_source_input(&self, source: &std::path::Path) {
            println!("cargo:rerun-if-changed={}", source.display());
        }
    }

    println!("cargo:rerun-if-env-changed=AITIA_PROGRAM_MANIFEST");
    let manifest = PathBuf::from(
        env::var_os("AITIA_PROGRAM_MANIFEST").expect("stage the AITIA Scheme program first"),
    );
    println!("cargo:rerun-if-changed={}", manifest.display());
    let out = PathBuf::from(env::var_os("OUT_DIR").expect("Cargo output directory"));
    let gsc = discover_gambit_gsc_from_env().expect("paired Gambit compiler");
    let receipt = build_program_archive_with_contract(
        ProgramArchiveRequest {
            manifest: &manifest,
            gsc: &gsc,
            archive_name: "aitia_program",
            linker_name: "aitia_program",
            out_dir: &out,
        },
        ProgramArchiveContract {
            required_modules: &[
                "gerbil-scheme-rust/scheme/runtime",
                "lambda-aitia/init",
                "lambda-aitia/bindings/operations",
                "lambda-aitia/rust/scheme/program",
                "lambda-aitia/modules/gitops/review-lineage",
                "lambda-aitia/modules/gitops/review-query",
                "agentic-ai-lab/modules/query/scheme-graph",
                "orgize/languages/org/modules/org-elements/values",
                "orgize/languages/org/modules/org-contract/values",
                "orgize/languages/org/modules/org-contract/evaluation",
            ],
            forbidden_modules: &[
                "lambda-aitia/bindings/c/aitia-native",
                "lambda-aitia/bindings/c/aitia-contract",
            ],
            linker_main_symbol: "aitia_program_unused_main",
            additional_objects: &[],
            native_headers: &[],
        },
        &CargoInputs,
    )
    .expect("link the compiler-owned AITIA program archive");
    let mut archive = File::open(&receipt.archive_file).expect("open the compiled Scheme program");
    let mut context = Sha256::new();
    std::io::copy(&mut archive, &mut context).expect("identify the compiled Scheme program");
    println!(
        "cargo:rustc-env=AITIA_PROGRAM_CONTEXT=sha256:{:x}",
        context.finalize()
    );
    for directive in receipt.cargo_directives {
        println!("{}", directive.line());
    }
}

#[cfg(not(feature = "linked-program"))]
fn main() {}
