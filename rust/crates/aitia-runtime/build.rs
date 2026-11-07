// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

#[cfg(feature = "linked-program")]
fn main() {
    use gerbil_scheme_aot_build::{
        ProgramArchiveContract, ProgramArchiveObservation, ProgramArchiveObserver,
        ProgramArchiveRequest, build_program_archive_with_contract, discover_gambit_gsc_from_env,
    };
    use std::{env, path::PathBuf};

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
    for directive in receipt.cargo_directives {
        println!("{}", directive.line());
    }
}

#[cfg(not(feature = "linked-program"))]
fn main() {}
