// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module EffectAdmission {
  pure def currentGrant(granted: int, revision: int, admitted: int, decided: int,
    grantEpoch: int, epoch: int, clock: int, grantUntil: int): bool =
    granted == revision and admitted == revision and decided == revision and
    grantEpoch == epoch and clock < grantUntil
}
