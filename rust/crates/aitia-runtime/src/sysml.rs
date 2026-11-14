// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Parse SysML documents captured at a recorded JJ workspace cut.

use aitia_jj::{JjObservationError, WorkspaceCut, read_recorded_files};
use std::{fmt, io};

use opensysml::{Connection, Error, Model, SourceDocument, SourcesOptions};

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
