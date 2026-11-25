// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Parse SysML documents captured at a recorded JJ workspace cut.

use aitia_jj::{JjObservationError, WorkspaceCut, read_recorded_files};
use std::{fmt, io};

use opensysml::{Connection, Error, Model, SourceDocument, SourcesOptions, Symbol, Value};

/// Architectural commit scope projected from a parsed SysML v2 `CommitScope` part.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SysmlScopeProjection {
    pub name: String,
    pub paths: Vec<String>,
    pub element_id: String,
}

/// Host capability specification projected from a parsed SysML v2 `HostCapabilitySpec` part.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SysmlCapabilitySpec {
    pub capability_id: String,
    pub effect_class: String,
    pub element_id: String,
}

fn collect_text_values(value: &Value, out: &mut Vec<String>) {
    match value {
        Value::Text(text) if !text.is_empty() => out.push(text.clone()),
        Value::Sequence(items) => {
            for item in items {
                collect_text_values(item, out);
            }
        }
        Value::Set(set) => {
            for item in set.elements() {
                collect_text_values(item, out);
            }
        }
        _ => {}
    }
}

fn collect_scope_candidates(
    symbol: &Symbol,
    depth: usize,
    candidates: &mut Vec<String>,
) -> Result<(), Error> {
    if depth > 4 {
        return Ok(());
    }
    let children = symbol.children()?;
    let has_scope_name = children.iter().any(|child| child.name() == "scopeName");
    let has_owned_paths = children.iter().any(|child| child.name() == "ownedPaths");
    if has_scope_name && has_owned_paths && symbol.kind().to_ascii_lowercase().contains("part") {
        candidates.push(symbol.id().to_owned());
        return Ok(());
    }
    for child in children {
        collect_scope_candidates(&child, depth + 1, candidates)?;
    }
    Ok(())
}

/// Project declared `CommitScope` parts (`scopeName` + `ownedPaths`) from a parsed SysML v2 model.
///
/// # Errors
/// Fails if OpenSysML symbol traversal or instantiation fails.
pub fn extract_declared_scopes(model: &Model) -> Result<Vec<SysmlScopeProjection>, Error> {
    let mut candidates = Vec::new();
    for root in model.roots() {
        collect_scope_candidates(root, 0, &mut candidates)?;
    }
    let mut scopes = Vec::new();
    for fqn in candidates {
        let instantiation = model.instantiate(&fqn)?;
        for instance in instantiation.instances() {
            let Some(name_feature) = instance.feature("scopeName") else {
                continue;
            };
            let Some(Value::Text(name)) = name_feature.value() else {
                continue;
            };
            let Some(paths_feature) = instance.feature("ownedPaths") else {
                continue;
            };
            let mut paths = Vec::new();
            for value in paths_feature.values() {
                collect_text_values(value, &mut paths);
            }
            if paths.is_empty()
                && let Some(value) = paths_feature.value()
            {
                collect_text_values(value, &mut paths);
            }
            if !name.is_empty() && !paths.is_empty() {
                scopes.push(SysmlScopeProjection {
                    name: name.clone(),
                    paths,
                    element_id: fqn.clone(),
                });
                break;
            }
        }
    }
    scopes.sort_by(|left, right| {
        left.name
            .cmp(&right.name)
            .then_with(|| left.element_id.cmp(&right.element_id))
    });
    Ok(scopes)
}

fn collect_capability_candidates(
    symbol: &Symbol,
    depth: usize,
    candidates: &mut Vec<String>,
) -> Result<(), Error> {
    if depth > 4 {
        return Ok(());
    }
    let children = symbol.children()?;
    let has_id = children.iter().any(|child| child.name() == "capabilityId");
    let has_effect = children.iter().any(|child| child.name() == "effectClass");
    if has_id && has_effect && symbol.kind().to_ascii_lowercase().contains("part") {
        candidates.push(symbol.id().to_owned());
        return Ok(());
    }
    for child in children {
        collect_capability_candidates(&child, depth + 1, candidates)?;
    }
    Ok(())
}

/// Project declared `HostCapabilitySpec` parts (`capabilityId` + `effectClass`) from a parsed SysML v2 model.
///
/// # Errors
/// Fails if OpenSysML symbol traversal or instantiation fails.
pub fn extract_declared_capabilities(model: &Model) -> Result<Vec<SysmlCapabilitySpec>, Error> {
    let mut candidates = Vec::new();
    for root in model.roots() {
        collect_capability_candidates(root, 0, &mut candidates)?;
    }
    let mut specs = Vec::new();
    for fqn in candidates {
        let instantiation = model.instantiate(&fqn)?;
        for instance in instantiation.instances() {
            let Some(id_feature) = instance.feature("capabilityId") else {
                continue;
            };
            let Some(Value::Text(capability_id)) = id_feature.value() else {
                continue;
            };
            let Some(effect_feature) = instance.feature("effectClass") else {
                continue;
            };
            let Some(Value::Text(effect_class)) = effect_feature.value() else {
                continue;
            };
            if !capability_id.is_empty() && !effect_class.is_empty() {
                specs.push(SysmlCapabilitySpec {
                    capability_id: capability_id.clone(),
                    effect_class: effect_class.clone(),
                    element_id: fqn.clone(),
                });
                break;
            }
        }
    }
    specs.sort_by(|left, right| {
        left.capability_id
            .cmp(&right.capability_id)
            .then_with(|| left.element_id.cmp(&right.element_id))
    });
    Ok(specs)
}

/// Parse captured source contents under their project-relative document names.
/// The caller owns the connection and binds these inputs to the observed cut.
pub fn parse_sysml(
    connection: &Connection,
    sources: impl IntoIterator<Item = (String, String)>,
) -> Result<Model, Error> {
    let documents = sources
        .into_iter()
        .map(|(name, content)| SourceDocument::inline(name, content))
        .collect::<Vec<_>>();
    connection.parse_sources(
        &documents,
        &SourcesOptions {
            strict: true,
            strict_conformance: true,
            ..SourcesOptions::default()
        },
    )
}

/// Failure to read or parse a project model at a recorded workspace cut.
#[derive(Debug)]
pub enum RecordedSysmlError {
    /// JJ refused a source read at the requested cut.
    Source(JjObservationError),
    /// OpenSysML refused the captured documents.
    Model(Error),
}

impl fmt::Display for RecordedSysmlError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Source(error) => error.fmt(formatter),
            Self::Model(error) => error.fmt(formatter),
        }
    }
}

impl std::error::Error for RecordedSysmlError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Source(error) => Some(error),
            Self::Model(error) => Some(error),
        }
    }
}

/// Resolve all declared SysML documents from one recorded JJ workspace cut,
/// within the total source byte budget.
///
/// # Errors
/// Fails if a source cannot be read at the cut, or if OpenSysML rejects the documents.
pub fn parse_recorded_sysml(
    connection: &Connection,
    cut: &WorkspaceCut,
    sources: &[String],
) -> Result<Model, RecordedSysmlError> {
    parse_sysml(connection, recorded_documents(cut, sources)?).map_err(RecordedSysmlError::Model)
}

pub(crate) fn recorded_documents(
    cut: &WorkspaceCut,
    sources: &[String],
) -> Result<Vec<(String, String)>, RecordedSysmlError> {
    load_documents(sources, |paths| {
        read_recorded_files(cut, paths, crate::MAX_REQUEST_BYTES as usize)
    })
}

#[cfg(feature = "linked-program")]
pub(crate) fn revision_documents(
    directory: &std::path::Path,
    revision: &str,
    sources: &[String],
) -> Result<Vec<(String, String)>, RecordedSysmlError> {
    load_documents(sources, |paths| {
        aitia_jj::read_revision_files(
            directory,
            revision,
            paths,
            crate::MAX_REQUEST_BYTES as usize,
        )
    })
}

#[cfg(feature = "linked-program")]
pub(crate) fn parse_model_report(
    load: impl FnOnce() -> Result<Vec<(String, String)>, RecordedSysmlError> + Send,
) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    // The host worker owns JJ reads and the SDK connection. Join it before
    // returning the report to the Scheme owner.
    let report = std::thread::scope(|scope| {
        scope
            .spawn(|| {
                let documents = load()?;
                let connection = Connection::connect().map_err(RecordedSysmlError::Model)?;
                let model =
                    parse_sysml(&connection, documents).map_err(RecordedSysmlError::Model)?;
                Ok::<_, RecordedSysmlError>(serde_json::json!({
                    "documents": model.documents(), "modelHash": model.hash()
                }))
            })
            .join()
    })
    .map_err(|_| io::Error::other("SysML host worker panicked"))?;
    Ok(report?)
}

#[cfg(feature = "linked-program")]
pub(crate) fn project_model_scopes(
    load: impl FnOnce() -> Result<Vec<(String, String)>, RecordedSysmlError> + Send,
) -> Result<Vec<SysmlScopeProjection>, Box<dyn std::error::Error>> {
    let scopes = std::thread::scope(|scope| {
        scope
            .spawn(|| {
                let documents = load()?;
                if documents.is_empty() {
                    return Ok::<_, RecordedSysmlError>(Vec::new());
                }
                let connection = Connection::connect().map_err(RecordedSysmlError::Model)?;
                let model =
                    parse_sysml(&connection, documents).map_err(RecordedSysmlError::Model)?;
                extract_declared_scopes(&model).map_err(RecordedSysmlError::Model)
            })
            .join()
    })
    .map_err(|_| io::Error::other("SysML scope worker panicked"))?;
    Ok(scopes?)
}

#[cfg(feature = "linked-program")]
pub(crate) fn project_recorded_scopes(
    cut: &WorkspaceCut,
) -> Result<Vec<SysmlScopeProjection>, Box<dyn std::error::Error>> {
    let sources = aitia_jj::recorded_sysml_paths(cut)?;
    if sources.is_empty() {
        return Ok(Vec::new());
    }
    project_model_scopes(|| recorded_documents(cut, &sources))
}

#[cfg(feature = "linked-program")]
pub(crate) fn project_revision_scopes(
    directory: &std::path::Path,
    revision: &str,
) -> Result<Vec<SysmlScopeProjection>, Box<dyn std::error::Error>> {
    let sources = aitia_jj::recorded_revision_sysml_paths(directory, revision)?;
    if sources.is_empty() {
        return Ok(Vec::new());
    }
    project_model_scopes(|| revision_documents(directory, revision, &sources))
}

#[cfg(feature = "linked-program")]
pub(crate) fn observe_commit_sysml_and_scopes(
    cut: &WorkspaceCut,
    affected_paths: &[String],
) -> (Option<serde_json::Value>, Vec<SysmlScopeProjection>) {
    let all_paths = aitia_jj::recorded_sysml_paths(cut).unwrap_or_default();
    if affected_paths.is_empty() && all_paths.is_empty() {
        return (None, Vec::new());
    }
    std::thread::scope(|scope| {
        scope
            .spawn(|| {
                let connection = match Connection::connect() {
                    Ok(connection) => connection,
                    Err(error) => {
                        let model = (!affected_paths.is_empty()).then(|| {
                            serde_json::json!({
                                "paths": affected_paths,
                                "status": "open",
                                "detail": error.to_string(),
                            })
                        });
                        return (model, Vec::new());
                    }
                };
                let same_set = !affected_paths.is_empty() && affected_paths == all_paths.as_slice();
                let mut scopes = Vec::new();
                let model = if !affected_paths.is_empty() {
                    match recorded_documents(cut, affected_paths).and_then(|docs| {
                        parse_sysml(&connection, docs).map_err(RecordedSysmlError::Model)
                    }) {
                        Ok(parsed) => {
                            if same_set {
                                scopes = extract_declared_scopes(&parsed).unwrap_or_default();
                            }
                            Some(serde_json::json!({
                                "paths": affected_paths,
                                "status": "passed",
                                "report": {
                                    "documents": parsed.documents(),
                                    "modelHash": parsed.hash(),
                                },
                            }))
                        }
                        Err(error) => Some(serde_json::json!({
                            "paths": affected_paths,
                            "status": "open",
                            "detail": error.to_string(),
                        })),
                    }
                } else {
                    None
                };
                if !same_set
                    && !all_paths.is_empty()
                    && let Ok(parsed) = recorded_documents(cut, &all_paths).and_then(|docs| {
                        parse_sysml(&connection, docs).map_err(RecordedSysmlError::Model)
                    })
                {
                    scopes = extract_declared_scopes(&parsed).unwrap_or_default();
                }
                (model, scopes)
            })
            .join()
    })
    .unwrap_or_else(|_| {
        let model = (!affected_paths.is_empty()).then(|| {
            serde_json::json!({
                "paths": affected_paths,
                "status": "open",
                "detail": "SysML host worker panicked",
            })
        });
        (model, Vec::new())
    })
}

fn load_documents(
    sources: &[String],
    read: impl FnOnce(&[&str]) -> Result<Vec<Vec<u8>>, JjObservationError>,
) -> Result<Vec<(String, String)>, RecordedSysmlError> {
    let paths: Vec<_> = sources.iter().map(String::as_str).collect();
    let contents = read(&paths).map_err(RecordedSysmlError::Source)?;
    sources
        .iter()
        .cloned()
        .zip(contents)
        .map(|(name, bytes)| {
            String::from_utf8(bytes)
                .map(|text| (name, text))
                .map_err(|error| {
                    RecordedSysmlError::Source(JjObservationError::Io(io::Error::new(
                        io::ErrorKind::InvalidData,
                        error.utf8_error(),
                    )))
                })
        })
        .collect()
}
