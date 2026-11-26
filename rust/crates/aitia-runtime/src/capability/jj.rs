// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Jujutsu (JJ) observation and fenced-effect host capabilities.

use super::{
    CapabilityError, CapabilityFrame, HostCapability, HostCapabilityRegistry, HostEffectClass,
    HostReceipt,
};

pub(super) fn register(registry: &mut HostCapabilityRegistry) {
    registry.register(Box::new(GitOpsJjObserveCutCapability));
    registry.register(Box::new(GitOpsJjPrepareDescriptionCapability));
    registry.register(Box::new(GitOpsJjApplyDescriptionCapability));
    registry.register(Box::new(GitOpsJjReconcileDescriptionCapability));
    registry.register(Box::new(GitOpsJjRecoverPushCapability));
}

struct GitOpsJjObserveCutCapability;

impl HostCapability for GitOpsJjObserveCutCapability {
    fn capability_id(&self) -> &'static str {
        "gitops.jj.observe-cut"
    }

    fn effect_class(&self) -> HostEffectClass {
        HostEffectClass::HostRead
    }

    fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
        let request: serde_json::Value = serde_json::from_str(&frame.payload)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let directory = request["directory"].as_str().unwrap_or(".");
        let requested_paths: Vec<String> = request["requestedPaths"]
            .as_array()
            .map(|items| {
                items
                    .iter()
                    .filter_map(|item| item.as_str().map(str::to_owned))
                    .collect()
            })
            .unwrap_or_default();
        let cut = aitia_jj::observe_workspace(std::path::Path::new(directory))
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let changes = aitia_jj::recorded_changes(&cut)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let path_refs: Vec<&str> = requested_paths.iter().map(String::as_str).collect();
        let max_bytes = usize::try_from(crate::MAX_REQUEST_BYTES)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let observed = aitia_jj::observe_recorded_sources(&cut, &path_refs, max_bytes)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let mut sources = Vec::new();
        for (path, result) in observed {
            if let Ok(text) = result {
                sources.push(serde_json::json!({ "path": path, "text": text }));
            }
        }
        let paths: Vec<&str> = changes.iter().map(|change| change.path.as_str()).collect();
        let payload = serde_json::to_string(&serde_json::json!({
            "cut": crate::commit::review_cut_value(&cut),
            "paths": paths,
            "sources": sources,
        }))
        .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        Ok(HostReceipt::observe(
            self.capability_id(),
            self.effect_class(),
            payload,
        ))
    }
}

fn observe_matching_cut(
    request: &serde_json::Value,
) -> Result<aitia_jj::WorkspaceCut, CapabilityError> {
    let directory = request["directory"].as_str().unwrap_or(".");
    let cut = aitia_jj::observe_workspace(std::path::Path::new(directory))
        .map_err(|error| CapabilityError::Execution(error.to_string()))?;
    if let Some(expected_commit) = request["expectedCommit"].as_str()
        && cut.commit_id() != expected_commit
    {
        return Err(CapabilityError::Execution(
            aitia_jj::JjObservationError::ChangedOperation.to_string(),
        ));
    }
    if let Some(expected_op) = request["expectedOperation"].as_str()
        && cut.operation_id() != expected_op
    {
        return Err(CapabilityError::Execution(
            aitia_jj::JjObservationError::ChangedOperation.to_string(),
        ));
    }
    Ok(cut)
}

struct GitOpsJjPrepareDescriptionCapability;

impl HostCapability for GitOpsJjPrepareDescriptionCapability {
    fn capability_id(&self) -> &'static str {
        "gitops.jj.prepare-description"
    }

    fn effect_class(&self) -> HostEffectClass {
        HostEffectClass::FencedEffect
    }

    fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
        let request: serde_json::Value = serde_json::from_str(&frame.payload)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let cut = observe_matching_cut(&request)?;
        let description = request["description"]
            .as_str()
            .ok_or_else(|| CapabilityError::Execution("missing description field".to_owned()))?;
        let review_context = request["reviewContext"]
            .as_str()
            .ok_or_else(|| CapabilityError::Execution("missing reviewContext field".to_owned()))?;
        let proposal_binding = request["proposalBinding"].as_str().ok_or_else(|| {
            CapabilityError::Execution("missing proposalBinding field".to_owned())
        })?;
        let prepared = aitia_jj::prepare_reviewed_description(
            &cut,
            description,
            review_context,
            proposal_binding,
        )
        .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let payload = serde_json::to_string(&prepared.proposed_receipt().recovery_record())
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        Ok(HostReceipt::observe(
            self.capability_id(),
            self.effect_class(),
            payload,
        ))
    }
}

struct GitOpsJjApplyDescriptionCapability;

impl HostCapability for GitOpsJjApplyDescriptionCapability {
    fn capability_id(&self) -> &'static str {
        "gitops.jj.apply-description"
    }

    fn effect_class(&self) -> HostEffectClass {
        HostEffectClass::FencedEffect
    }

    fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
        let request: serde_json::Value = serde_json::from_str(&frame.payload)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let cut = observe_matching_cut(&request)?;
        let description = request["description"]
            .as_str()
            .ok_or_else(|| CapabilityError::Execution("missing description field".to_owned()))?;
        let review_context = request["reviewContext"]
            .as_str()
            .ok_or_else(|| CapabilityError::Execution("missing reviewContext field".to_owned()))?;
        let proposal_binding = request["proposalBinding"].as_str().ok_or_else(|| {
            CapabilityError::Execution("missing proposalBinding field".to_owned())
        })?;
        let attempt: aitia_jj::DescriptionRecovery =
            serde_json::from_value(request["attempt"].clone())
                .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let prepared = aitia_jj::reopen_reviewed_description(
            &cut,
            description,
            &attempt,
            review_context,
            proposal_binding,
        )
        .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let receipt = prepared
            .publish(|_| true)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let payload = serde_json::to_string(&receipt)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        Ok(HostReceipt::observe(
            self.capability_id(),
            self.effect_class(),
            payload,
        ))
    }
}

struct GitOpsJjReconcileDescriptionCapability;

impl HostCapability for GitOpsJjReconcileDescriptionCapability {
    fn capability_id(&self) -> &'static str {
        "gitops.jj.reconcile-description"
    }

    fn effect_class(&self) -> HostEffectClass {
        HostEffectClass::HostRead
    }

    fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
        let request: serde_json::Value = serde_json::from_str(&frame.payload)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let directory = request["directory"].as_str().unwrap_or(".");
        let attempt: aitia_jj::DescriptionRecovery =
            serde_json::from_value(request["attempt"].clone())
                .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let outcome = aitia_jj::reconcile_description(std::path::Path::new(directory), &attempt)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let payload = serde_json::to_string(&serde_json::json!({
            "attempt": attempt,
            "outcome": outcome,
        }))
        .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        Ok(HostReceipt::observe(
            self.capability_id(),
            self.effect_class(),
            payload,
        ))
    }
}

struct GitOpsJjRecoverPushCapability;

impl HostCapability for GitOpsJjRecoverPushCapability {
    fn capability_id(&self) -> &'static str {
        "gitops.jj.recover-push"
    }

    fn effect_class(&self) -> HostEffectClass {
        HostEffectClass::HostRead
    }

    fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
        let request: serde_json::Value = serde_json::from_str(&frame.payload)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let directory = request["directory"].as_str().unwrap_or(".");
        let remote = request["remote"]
            .as_str()
            .ok_or_else(|| CapabilityError::Execution("missing remote field".to_owned()))?;
        let bookmark = request["bookmark"]
            .as_str()
            .ok_or_else(|| CapabilityError::Execution("missing bookmark field".to_owned()))?;
        let attempt: aitia_jj::DescriptionRecovery =
            serde_json::from_value(request["attempt"].clone())
                .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let receipt = aitia_jj::recover_reviewed_push(
            std::path::Path::new(directory),
            &attempt,
            remote,
            bookmark,
        )
        .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let outcome = if receipt.is_some() {
            "acknowledged"
        } else {
            "unresolved"
        };
        let payload = serde_json::to_string(&serde_json::json!({
            "outcome": outcome,
            "receipt": receipt,
        }))
        .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        Ok(HostReceipt::observe(
            self.capability_id(),
            self.effect_class(),
            payload,
        ))
    }
}
