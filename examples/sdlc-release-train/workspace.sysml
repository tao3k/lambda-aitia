// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

package BillingCheckoutReleaseTrain {
    private import ScalarValues::*;

    doc /* Real two-repository SDLC release-train topology:
         * Wave 0 (`billing-core`, OpenSecurity profile) must reach quiescent and push its
         * reviewed commit before Wave 1 (`checkout-service`, Standard-Free SDLC Core) may
         * apply and push downstream. */

    part def WorkspaceRepo {
        attribute repoId : String;
        attribute directory : String;
        attribute dependsOn : String[0..*];
        attribute profile : String;
        attribute pushRemote : String;
        attribute pushBookmark : String;
    }

    part billingCore : WorkspaceRepo {
        attribute :>> repoId = "billing-core";
        attribute :>> directory = "./billing-core";
        attribute :>> profile = "lambda-aitia/sdlc";
        attribute :>> pushRemote = "origin";
        attribute :>> pushBookmark = "reviewed";
    }

    part checkoutService : WorkspaceRepo {
        attribute :>> repoId = "checkout-service";
        attribute :>> directory = "./checkout-service";
        attribute :>> dependsOn = ("billing-core");
        attribute :>> profile = "lambda-aitia/sdlc";
        attribute :>> pushRemote = "origin";
        attribute :>> pushBookmark = "reviewed";
    }
}
