// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

package CardanoDiamondReleaseTrain {
    private import ScalarValues::*;

    doc /* 4-repository IOHK/Bazel diamond topology:
         * Wave 0: protocol-base
         * Wave 1: ledger-core, network-mux (disjoint concurrent peers)
         * Wave 2: node-runner (converging consumer) */

    part def WorkspaceRepo {
        attribute repoId : String;
        attribute directory : String;
        attribute dependsOn : String[0..*];
        attribute profile : String;
        attribute pushRemote : String;
        attribute pushBookmark : String;
        attribute interfacePaths : String[0..*];
        attribute pinnedUpstreamInterfaces : String[0..*];
        attribute assumes : String[0..*];
        attribute guarantees : String[0..*];
    }

    part def TufPolicy {
        attribute minThreshold : String;
        attribute minEpoch : String;
    }

    part releaseTufPolicy : TufPolicy {
        attribute :>> minThreshold = "2";
        attribute :>> minEpoch = "5";
    }

    part protocolBase : WorkspaceRepo {
        attribute :>> repoId = "protocol-base";
        attribute :>> directory = "./protocol-base";
        attribute :>> profile = "lambda-aitia/sdlc";
        attribute :>> pushRemote = "origin";
        attribute :>> pushBookmark = "reviewed";
        attribute :>> interfacePaths = ("include/protocol.h");
        attribute :>> guarantees = ("protocol.v1.codecs", "crypto.ed25519");
    }

    part ledgerCore : WorkspaceRepo {
        attribute :>> repoId = "ledger-core";
        attribute :>> directory = "./ledger-core";
        attribute :>> dependsOn = ("protocol-base");
        attribute :>> profile = "lambda-aitia/sdlc";
        attribute :>> pushRemote = "origin";
        attribute :>> pushBookmark = "reviewed";
        attribute :>> assumes = ("protocol.v1.codecs");
        attribute :>> guarantees = ("ledger.utxo.deterministic");
    }

    part networkMux : WorkspaceRepo {
        attribute :>> repoId = "network-mux";
        attribute :>> directory = "./network-mux";
        attribute :>> dependsOn = ("protocol-base");
        attribute :>> profile = "lambda-aitia/sdlc";
        attribute :>> pushRemote = "origin";
        attribute :>> pushBookmark = "reviewed";
        attribute :>> assumes = ("protocol.v1.codecs", "crypto.ed25519");
        attribute :>> guarantees = ("network.mux.framed");
    }

    part nodeRunner : WorkspaceRepo {
        attribute :>> repoId = "node-runner";
        attribute :>> directory = "./node-runner";
        attribute :>> dependsOn = ("ledger-core", "network-mux");
        attribute :>> profile = "lambda-aitia/sdlc";
        attribute :>> pushRemote = "origin";
        attribute :>> pushBookmark = "reviewed";
        attribute :>> assumes = ("ledger.utxo.deterministic", "network.mux.framed");
        attribute :>> guarantees = ("node.consensus.ready");
    }
}
