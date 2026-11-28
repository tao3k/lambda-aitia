// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module WorkCore {
  type Work = {active: bool, queued: bool, cancelRequested: bool}
  pure def cancel(w: Work): Work = {...w, cancelRequested: true}
  pure def complete(w: Work): Work = {...w, active: false}
  pure def drain(w: Work): Work = {...w, queued: false}
  pure def quiescent(w: Work): bool = not(w.active) and not(w.queued)
}
