// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

package ExampleMultiRepoWorkspace {
    private import ScalarValues::*;

    doc /* Authoritative SysML v2 multi-repository topology consumed directly by
         * `aitia flow run --workspace workspace.sysml` with zero downstream Gerbil
         * compilation and zero hand-written JSON manifest. */

    part def WorkspaceRepo {
        attribute repoId : String;
        attribute directory : String;
        attribute dependsOn : String[0..*];
        attribute profile : String;
        attribute pushRemote : String;
        attribute pushBookmark : String;
    }

    part upstreamCore : WorkspaceRepo {
        attribute :>> repoId = "upstream-core";
        attribute :>> directory = "./upstream-core";
        attribute :>> profile = "lambda-aitia/sdlc";
        attribute :>> pushRemote = "origin";
        attribute :>> pushBookmark = "reviewed";
    }

    part downstreamApp : WorkspaceRepo {
        attribute :>> repoId = "downstream-app";
        attribute :>> directory = "./downstream-app";
        attribute :>> dependsOn = ("upstream-core");
        attribute :>> profile = "lambda-aitia/sdlc";
        attribute :>> pushRemote = "origin";
        attribute :>> pushBookmark = "reviewed";
    }
}
