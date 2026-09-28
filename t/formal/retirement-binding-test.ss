;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/misc/ports read-all-as-string)
        (only-in :clan/poo/object .ref)
        (only-in :poo-flow/src/feature-system/source-lock-feature source-lock-payload-digest)
        :poo-flow/lambda-aitia/modules/assurance/interface
        :poo-flow/lambda-aitia/modules/sdlc/interface
        :poo-flow/lambda-aitia/user-interface/scenarios/job-retirement-contract)
(export retirement-binding-test)

;;; IO belongs to the qualification fixture, not the public design value.
;;; Hash every member before making one group artifact: changing any model,
;;; config, imported helper or proof source invalidates the declared source cut.
(def (source-group-digest paths)
  (assurance-canonical-digest
   (map (lambda (path)
          (list path (source-lock-payload-digest
                      (call-with-input-file path read-all-as-string)))) paths)))
(def (source id digest)
  (assurance-artifact id "r1" 'supported digest
                      owner: "lambda-aitia" media-kind: 'formal-source
                      provenance: '("repository-source-bytes")))
(def tla-source (source "retirement/tla" (source-group-digest job-retirement-tla-sources)))
(def lean-source (source "retirement/lean" (source-group-digest job-retirement-lean-sources)))
(def (snapshot tla lean)
  (assurance-snapshot
   "retirement/formal-cut" "cut-1" "retirement/formal-sources"
   '(("retirement/tla" . "r1") ("retirement/lean" . "r1")) '()
   "retirement/design-r1" "formal-review" "r1" (list tla lean) '()))
(def source-cut (snapshot tla-source lean-source))
(def links
  (map (lambda (artifact)
         (sdlc-design-implementation-link
          job-retirement-contract job-retirement-safety artifact source-cut))
       (list tla-source lean-source)))

(def retirement-binding-test
  (test-suite "Retirement POO contract to formal source binding"
    (test-case "both views bind one declaration without granting conformance"
      (let (review (sdlc-design-implementation-review
                    job-retirement-contract source-cut links))
        (check (.ref review 'mapping-current?) => #t)
        (for-each
         (lambda (link)
           (check (.ref link 'contract) => "job-executor/retirement")
           (check (.ref link 'contract-revision) => "r1")
           (check (.ref link 'contract-digest)
                  => (sdlc-design-contract-digest job-retirement-contract))) links)
        (check (.ref review 'implementation-conforms?) => #f)
        (check (.ref review 'evidence-admitted?) => #f)
        (check (.ref review 'release-authorized?) => #f)))
    (test-case "same-revision TLA source mutation invalidates the joined mapping"
      (let* ((changed (source "retirement/tla" (source-lock-payload-digest "changed model")))
             (review (sdlc-design-implementation-review
                       job-retirement-contract (snapshot changed lean-source) links)))
        (check (.ref review 'mapping-current?) => #f)
        (check (length (.ref review 'blocked-links)) => 2)
        (check (.ref (car (.ref review 'blocked-links)) 'blocker) => 'snapshot-changed)))
    (test-case "same-revision Lean source mutation also invalidates the mapping"
      (let* ((changed (source "retirement/lean" (source-lock-payload-digest "changed law")))
             (review (sdlc-design-implementation-review
                       job-retirement-contract (snapshot tla-source changed) links)))
        (check (.ref review 'mapping-current?) => #f)
        (check (length (.ref review 'blocked-links)) => 2)
        (check (.ref (car (.ref review 'blocked-links)) 'blocker) => 'snapshot-changed)))
    (test-case "a changed design premise cannot reuse either formal link"
      (let* ((changed
              (sdlc-design-contract
               "job-executor/retirement" "r1" "RFC/0004/retirement-ingress"
               (.ref job-retirement-contract 'responsibilities)
               (.ref job-retirement-contract 'owned-state) '()
               (cons (sdlc-design-assumption "distributed-fence" "a1"
                       "Closing and epoch advancement may be separate operations.")
                     (.ref job-retirement-contract 'assumptions))
               (list job-retirement-safety) '()))
             (review (sdlc-design-implementation-review changed source-cut links)))
        (check (.ref review 'mapping-current?) => #f)
        (check (length (.ref review 'blocked-links)) => 2)
        (for-each (lambda (link) (check (.ref link 'blocker) => 'contract-changed))
                  (.ref review 'blocked-links))))))
