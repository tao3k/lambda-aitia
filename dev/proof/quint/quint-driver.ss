;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(export invoke)

;; The JavaScript target uses Node only for the process boundary.
;; Quint owns the model, evaluation and verdict.
(def (invoke)
  (##inline-host-statement "
const [quint, model, ...extra] = process.argv.slice(2);
if (!quint || !model || extra.length !== 0) {
  console.error('usage: node driver.js <quint> <model.qnt>');
  process.exitCode = 2;
} else {
  const result = require('node:child_process').spawnSync(
    process.execPath, [quint, 'test', '--backend=typescript', model],
    { stdio: 'inherit' }
  );
  if (result.error || result.signal) {
    console.error(result.error || result.signal);
  }
  process.exitCode = result.status ?? 1;
}"))
