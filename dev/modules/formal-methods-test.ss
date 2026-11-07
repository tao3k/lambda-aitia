;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :std/error
        (only-in :clan/poo/object .o .get .ref)
        (only-in :agentic-ai-lab/modules/proof/interface agentic-ai-lab-proof-module?)
        (only-in "../../init.ss" lambda-aitia.init.exports))
(export formal-methods-test)

(def formal-methods-test
  (test-suite "Formal methods consume the admitted Module scope"
    (test-case "declared engines reuse Lab Proof without execution or authority"
      (let* ((scope (.get (.get lambda-aitia.init.exports modules) formal-methods))
             (providers (.get scope providers)))
        (check-equal? (agentic-ai-lab-proof-module? (.get scope module)) #t)
        (check-equal? ((.get scope engines)
                       (list (.get providers quint) (.get providers lean) (.get providers cedar)))
                      '(quint lean cedar))
        (check-equal? (.ref (.get providers quint) 'role) 'state-transition-model-checking)
        (check-equal? (.ref (.get providers lean) 'role) 'refinement-and-contract-proof)
        (check-equal? (.ref (.get providers cedar) 'role) 'authorization-policy-validation)
        (for-each (lambda (provider)
                    (check-equal? ((.get scope provider?) provider) #t)
                    (check-equal? (.ref provider 'obligation-only?) #t)
                    (check-equal? (.ref provider 'runtime-executed?) #f))
                  (list (.get providers quint) (.get providers lean) (.get providers cedar)))))
    (test-case "invalid artifacts and forged execution claims are refused"
      (let* ((scope (.get (.get lambda-aitia.init.exports modules) formal-methods))
             (provider (.get (.get scope providers) quint)))
        (check-exception ((.get scope provider) 'quint 'model-checking '(42)) Error?)
        (check-equal? ((.get scope provider?) (.o (:: @ provider) artifact-kinds: '(42))) #f)
        (check-equal? ((.get scope provider?) (.o (:: @ provider) runtime-executed?: #t)) #f)
        (check-equal? ((.get scope provider?) (.o (:: @ provider) obligation-only?: #f)) #f)
        (check-exception ((.get scope engines) (list (.o (:: @ provider) runtime-executed?: #t))) Error?)))))
