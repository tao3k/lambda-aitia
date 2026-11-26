// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! GitHub PR review observation host capability.

use super::{
    CapabilityError, CapabilityFrame, HostCapability, HostCapabilityRegistry, HostEffectClass,
    HostReceipt,
};

pub(super) fn register(registry: &mut HostCapabilityRegistry) {
    registry.register(Box::new(GitOpsGithubObservePrCapability));
}

struct GitOpsGithubObservePrCapability;

impl HostCapability for GitOpsGithubObservePrCapability {
    fn capability_id(&self) -> &'static str {
        "gitops.github.observe-pr"
    }

    fn effect_class(&self) -> HostEffectClass {
        HostEffectClass::HostRead
    }

    fn invoke(&self, frame: &CapabilityFrame) -> Result<HostReceipt, CapabilityError> {
        let request: serde_json::Value = serde_json::from_str(&frame.payload)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let directory = request["directory"].as_str().unwrap_or(".");
        let cut = aitia_jj::observe_workspace(std::path::Path::new(directory))
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let bookmarks = aitia_jj::recorded_review_bookmarks(&cut)
            .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        let provider = crate::review_provider::observe(&bookmarks, cut.commit_id());
        let payload = serde_json::to_string(&serde_json::json!({
            "bookmarks": bookmarks,
            "providerReview": provider,
        }))
        .map_err(|error| CapabilityError::Execution(error.to_string()))?;
        Ok(HostReceipt::observe(
            self.capability_id(),
            self.effect_class(),
            payload,
        ))
    }
}
