// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Capture bounded, canonical source-tree bytes for verification.

use rustix::fs::{AtFlags, Dir, FileType, Mode, OFlags, open, openat, statat};
use sha2::{Digest, Sha256};
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::os::fd::{AsFd, BorrowedFd};
use std::path::Path;

const MAGIC: &[u8] = b"lambda-aitia.source-tree.v1\0";
const MAX_BYTES: usize = 64 * 1024 * 1024;
const MAX_FILES: usize = 10_000;
const ENTRY_HEADER: usize = 4 + 8;
const OPEN_FLAGS: OFlags = OFlags::RDONLY
    .union(OFlags::CLOEXEC)
    .union(OFlags::NOFOLLOW)
    .union(OFlags::NONBLOCK);

struct Capture {
    size: usize,
    entries: Vec<(String, Vec<u8>)>,
}

pub(crate) fn sha256(bytes: &[u8]) -> String {
    format!("sha256:{:x}", Sha256::digest(bytes))
}

fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

/// Capture regular files in the Scheme source-lock wire format.
///
/// # Errors
///
/// Rejects non-regular entries, invalid paths, I/O failures, and captures
/// exceeding the source-lock file or byte budget.
pub fn capture_source_tree(root: &Path) -> io::Result<Vec<u8>> {
    let root = root.canonicalize()?;
    let directory = open(root, OPEN_FLAGS | OFlags::DIRECTORY, Mode::empty())?;
    let mut capture = Capture {
        size: MAGIC.len() + 8,
        entries: Vec::new(),
    };
    capture.walk(directory.as_fd(), "")?;
    encode_source_tree(capture.entries, capture.size)
}

#[cfg(feature = "gitops")]
pub(crate) fn capture_recorded_source_tree(
    cut: &aitia_jj::WorkspaceCut,
    paths: &[&str],
) -> Result<Vec<u8>, aitia_jj::JjObservationError> {
    use aitia_jj::JjObservationError;

    let mut paths = paths.to_vec();
    paths.sort_unstable();
    if paths.is_empty()
        || paths.len() > MAX_FILES
        || paths.iter().any(|path| !valid_frozen_path(path))
        || paths.windows(2).any(|pair| pair[0] == pair[1])
    {
        return Err(JjObservationError::Output(
            "invalid recorded source paths".into(),
        ));
    }
    let header = paths.iter().try_fold(MAGIC.len() + 8, |size, path| {
        size.checked_add(ENTRY_HEADER)?.checked_add(path.len())
    });
    let available = header
        .and_then(|size| MAX_BYTES.checked_sub(size))
        .ok_or_else(|| {
            JjObservationError::Output("recorded source paths exceed capture limit".into())
        })?;
    let contents = aitia_jj::read_recorded_files(cut, &paths, available)?;
    let size = MAX_BYTES - available + contents.iter().map(Vec::len).sum::<usize>();
    let entries = paths.into_iter().map(str::to_owned).zip(contents).collect();
    encode_source_tree(entries, size).map_err(JjObservationError::Io)
}

fn encode_source_tree(mut entries: Vec<(String, Vec<u8>)>, size: usize) -> io::Result<Vec<u8>> {
    entries.sort_unstable_by(|a, b| a.0.cmp(&b.0));
    let mut output = Vec::with_capacity(size);
    output.extend_from_slice(MAGIC);
    output.extend_from_slice(&(entries.len() as u64).to_be_bytes());
    for (path, bytes) in entries {
        let length = u32::try_from(path.len()).map_err(|_| invalid("source path is too long"))?;
        output.extend_from_slice(&length.to_be_bytes());
        output.extend_from_slice(path.as_bytes());
        output.extend_from_slice(&(bytes.len() as u64).to_be_bytes());
        output.extend(bytes);
    }
    Ok(output)
}

/// One validated file in a frozen source tree.
#[derive(Debug, PartialEq, Eq)]
pub struct FrozenSourceFile<'a> {
    pub path: &'a str,
    pub bytes: &'a [u8],
}

/// Validate and decode a frozen source tree without copying file contents.
///
/// # Errors
///
/// Rejects malformed or oversized input, unsafe paths, duplicate entries,
/// and files that would also have to be directories.
pub fn decode_source_tree(payload: &[u8]) -> io::Result<Vec<FrozenSourceFile<'_>>> {
    let mut input = payload
        .strip_prefix(MAGIC)
        .filter(|_| payload.len() <= MAX_BYTES)
        .ok_or_else(|| invalid("invalid frozen source payload"))?;
    let count = read_length(u64::from_be_bytes(read_array(&mut input)?))?;
    if count > MAX_FILES || count > input.len() / ENTRY_HEADER {
        return Err(invalid("invalid frozen source file count"));
    }

    let mut files: Vec<FrozenSourceFile<'_>> = Vec::with_capacity(count);
    for _ in 0..count {
        let path_len = read_length(u64::from(u32::from_be_bytes(read_array(&mut input)?)))?;
        let path = std::str::from_utf8(take_bytes(&mut input, path_len)?)
            .map_err(|_| invalid("invalid UTF-8 source path"))?;
        if !valid_frozen_path(path) || files.last().is_some_and(|file| file.path >= path) {
            return Err(invalid("invalid frozen source path or ordering"));
        }
        let size = read_length(u64::from_be_bytes(read_array(&mut input)?))?;
        files.push(FrozenSourceFile {
            path,
            bytes: take_bytes(&mut input, size)?,
        });
    }

    if !input.is_empty() {
        return Err(invalid("trailing frozen source payload bytes"));
    }
    for file in &files {
        let prefix = format!("{}/", file.path);
        let candidate = files.partition_point(|entry| entry.path < prefix.as_str());
        if files
            .get(candidate)
            .is_some_and(|entry| entry.path.starts_with(&prefix))
        {
            return Err(invalid("frozen source file conflicts with a directory"));
        }
    }
    Ok(files)
}

/// Owns a private copy of a frozen source tree until replay ends.
pub struct FrozenWorkspace {
    source: tempfile::TempDir,
}

impl FrozenWorkspace {
    /// Validate the full snapshot before creating a private source directory.
    ///
    /// # Errors
    ///
    /// Propagates invalid snapshots and file-system failures. The private
    /// directory is cleaned up if preparing any entry fails.
    pub fn prepare(payload: &[u8]) -> io::Result<Self> {
        let files = decode_source_tree(payload)?;
        let source = tempfile::Builder::new().prefix("aitia-source-").tempdir()?;
        for file in files {
            let target = source.path().join(file.path);
            if let Some(parent) = target.parent() {
                fs::create_dir_all(parent)?;
            }
            File::create_new(target)?.write_all(file.bytes)?;
        }
        Ok(Self { source })
    }

    /// Source root for the verifier's working directory.
    #[must_use]
    pub fn root(&self) -> &Path {
        self.source.path()
    }
}

fn valid_frozen_path(path: &str) -> bool {
    !path.contains(['\\', '\0'])
        && !matches!(path.as_bytes(), [drive, b':', ..] if drive.is_ascii_alphabetic())
        && path.split('/').all(|part| !matches!(part, "" | "." | ".."))
}

fn read_length(value: u64) -> io::Result<usize> {
    usize::try_from(value).map_err(|_| invalid("frozen source length is too large"))
}

fn take_bytes<'a>(input: &mut &'a [u8], length: usize) -> io::Result<&'a [u8]> {
    let (bytes, rest) = input
        .split_at_checked(length)
        .ok_or_else(|| invalid("truncated frozen source payload"))?;
    *input = rest;
    Ok(bytes)
}

fn read_array<const N: usize>(input: &mut &[u8]) -> io::Result<[u8; N]> {
    take_bytes(input, N)?
        .try_into()
        .map_err(|_| invalid("invalid frozen source field"))
}

impl Capture {
    fn walk(&mut self, directory: BorrowedFd<'_>, prefix: &str) -> io::Result<()> {
        for entry in Dir::read_from(directory)? {
            let entry = entry?;
            let name = entry.file_name();
            let component = name
                .to_str()
                .map_err(|_| invalid("invalid UTF-8 source path"))?;
            if matches!(component, "." | "..") {
                continue;
            }
            let windows_drive =
                matches!(component.as_bytes(), [drive, b':', ..] if drive.is_ascii_alphabetic());
            if component.contains('\\') || (prefix.is_empty() && windows_drive) {
                return Err(invalid(
                    "source path cannot be represented in a frozen tree",
                ));
            }

            let path = if prefix.is_empty() {
                component.to_owned()
            } else {
                format!("{prefix}/{component}")
            };
            let stat = statat(directory, name, AtFlags::SYMLINK_NOFOLLOW)?;
            match FileType::from_raw_mode(stat.st_mode) {
                FileType::Directory => {
                    let child = openat(
                        directory,
                        name,
                        OPEN_FLAGS | OFlags::DIRECTORY,
                        Mode::empty(),
                    )?;
                    self.walk(child.as_fd(), &path)?;
                }
                FileType::RegularFile => {
                    let file = File::from(openat(directory, name, OPEN_FLAGS, Mode::empty())?);
                    if !file.metadata()?.is_file() {
                        return Err(invalid("source entry changed type during capture"));
                    }
                    self.record(path, file)?;
                }
                _ => return Err(invalid("source tree contains a symlink or non-file")),
            }
        }
        Ok(())
    }

    fn record(&mut self, path: String, file: File) -> io::Result<()> {
        let header = ENTRY_HEADER + path.len();
        let remaining = MAX_BYTES
            .checked_sub(self.size + header)
            .filter(|_| self.entries.len() < MAX_FILES)
            .ok_or_else(|| invalid("source tree exceeds verifier capture limit"))?;
        let mut bytes = Vec::new();
        file.take(remaining as u64 + 1).read_to_end(&mut bytes)?;
        if bytes.len() > remaining {
            return Err(invalid("source tree exceeds verifier capture limit"));
        }
        self.size += header + bytes.len();
        self.entries.push((path, bytes));
        Ok(())
    }
}

#[cfg(test)]
#[path = "../tests/unit/source_tree.rs"]
mod tests;
