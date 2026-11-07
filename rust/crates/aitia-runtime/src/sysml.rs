// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Parse SysML documents captured at a recorded JJ workspace cut.

use aitia_jj::{JjObservationError, WorkspaceCut, read_recorded_file};
use std::fmt;

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

/// Resolve all declared SysML documents from one recorded JJ workspace cut.
///
/// # Errors
/// Fails if a source cannot be read at the cut, or if OpenSysML rejects the documents.
pub fn parse_recorded_sysml(
    connection: &Connection,
    cut: &WorkspaceCut,
    sources: &[String],
) -> Result<Model, RecordedSysmlError> {
    let documents = sources
        .iter()
        .map(|path| read_recorded_file(cut, path).map(|content| (path.clone(), content)))
        .collect::<Result<Vec<_>, _>>()
        .map_err(RecordedSysmlError::Source)?;
    parse_sysml(connection, documents).map_err(RecordedSysmlError::Model)
}
