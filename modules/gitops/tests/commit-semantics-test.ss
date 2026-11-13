;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test :std/error (only-in :clan/poo/object .o .cc .get)
        (only-in "../commit-semantics.ss" gitops-commit-semantics)
        (only-in "../commit-evidence.ss" gitops-nasa-draft-requirements
                 gitops-nasa-commit-description gitops-commit-check-receipt))
(export commit-semantics-test)

(def current-cut
  (.o project: "example" workspace: "default" change: "change"
      operation: "operation" commit: "revision" tree: "tree" parents: '("parent")))
(def reference
  (.o identity: "RFC-7" source: "docs/design.org" element: "commit-engineering"))
(def naming
  (.o project-key: "AITIA" primary-language: #f language-sources: '("docs/design.org") types: '("feat" "fix" "docs")
      scopes: (list (.o name: "gitops" paths: '("modules/gitops")))
      references: (list reference)))
(def source
  (.o path: "docs/design.org" cut: current-cut
      text: "* Commit engineering\n:PROPERTIES:\n:ID: commit-engineering\n:ENGINEERING_ID: RFC-7\n:END:\n"))
(def proposal
  (.o identity: "candidate-a" reference: "RFC-7" type: "feat" scope: "gitops"
      language: "en" language-source: "docs/design.org"
      summary: "Validate commit intent" rationale: "Adds source-bound intent admission"))
(def (assess (policy naming) (sources (list source)) (proposals (list proposal))
             (paths '("modules/gitops/config.ss")))
  (gitops-commit-semantics policy current-cut sources paths proposals))

(def commit-semantics-test
  (test-suite "Engineering title proposals are relations, not authority"
    (test-case "a source-bound engineering reference yields a canonical readable title"
      (let (view (assess))
        (check-equal? (.get view titles)
                      '(("candidate-a" "AITIA-RFC-7 feat(gitops): Validate commit intent")))
        (check-equal? (.get view open) '())))
    (test-case "missing, forged, revised and duplicate source elements cannot support a reference"
      (for-each
       (lambda (sources)
         (let (view (assess naming sources))
           (check-equal? (.get view titles) '())
           (check (and (member '("candidate-a" "missing-reference") (.get view open)) #t) => #t)))
       (list '() (list (.cc source path: "docs/forged.org"))
             (list (.cc source cut: (.cc current-cut tree: "different")))
             (list (.cc source text: "* Changed\n:PROPERTIES:\n:ID: other\n:END:\n"))
             (list (.cc source text: "* Forged\n:PROPERTIES:\n:ID: commit-engineering\n:ENGINEERING_ID: PR-2\n:END:\n"))
             (list (.cc source text: "* Ambiguous\n:PROPERTIES:\n:ID: commit-engineering\n:ENGINEERING_ID: RFC-7\n:ENGINEERING_ID: RFC-8\n:END:\n"))
             (list (.cc source text: (string-append (.get source text) (.get source text))))
             (list source source))))
    (test-case "every part of the source cut participates in admission"
      (for-each
       (lambda (stale-cut)
         (check-equal? (.get (assess naming (list (.cc source cut: stale-cut))) titles) '()))
       (list (.cc current-cut project: "other") (.cc current-cut workspace: "other")
             (.cc current-cut change: "other") (.cc current-cut operation: "other")
             (.cc current-cut commit: "other") (.cc current-cut tree: "other")
             (.cc current-cut parents: '("different")))))
    (test-case "equal cut values do not require the same object instance"
      (check-equal? (.get (assess naming (list (.cc source cut: (.cc current-cut)))) titles)
                    (.get (assess) titles)))
    (test-case "PR and NASA identifiers do not silently replace the engineering reference"
      (for-each
       (lambda (identity)
         (check-equal? (.get (assess naming (list source)
                                    (list (.cc proposal reference: identity))) titles) '()))
       '("2" "PR-2" "SWE-084")))
    (test-case "the affected scope has a directory boundary"
      (check-equal? (.get (assess naming (list source) (list proposal)
                                  '("modules/gitops-other/config.ss")) titles) '())
      (check-equal? (.get (assess naming (list source) (list (.cc proposal scope: "runtime"))) titles) '()))
    (test-case "conflicting declarations cannot widen a scope"
      (let* ((scope (.o name: "gitops" paths: '("modules/gitops" "docs")))
             (same (.cc scope paths: '("docs" "modules/gitops" "docs")))
             (conflict (.cc scope paths: '("modules/runtime")))
             (accepted (assess (.cc naming scopes: (list scope same))))
             (rejected (assess (.cc naming scopes: (list scope conflict)))))
        (check-equal? (.get accepted titles) (.get (assess) titles))
        (check-equal? (.get accepted affected-scopes) '(("gitops")))
        (check-equal? (.get rejected titles) '())
        (check-equal? (.get rejected affected-scopes) '())
        (check-equal? (.get rejected open) '(("candidate-a" "conflicting-scope")))))
    (test-case "unsupported types and malformed narration are not repaired by guessing"
      (for-each
       (lambda (candidate)
         (check-equal? (.get (assess naming (list source) (list candidate)) titles) '()))
       (list (.cc proposal type: "invented") (.cc proposal summary: "Line\nbreak")
             (.cc proposal summary: "123") (.cc proposal rationale: "")
             (.cc proposal summary: (make-string 72 #\a)))))
    (test-case "the rendered title accepts 72 characters and rejects 73"
      (let* ((prefix "AITIA-RFC-7 feat(gitops): ")
             (summary-value (make-string (- 72 (string-length prefix)) #\a))
             (accepted (assess naming (list source) (list (.cc proposal summary: summary-value))))
             (rejected (assess naming (list source)
                               (list (.cc proposal summary: (string-append summary-value "a"))))))
        (check-equal? (.get accepted titles)
                      (list (list "candidate-a" (string-append prefix summary-value))))
        (check-equal? (.get accepted open) '())
        (check-equal? (.get rejected titles) '())
        (check-equal? (.get rejected open) '(("candidate-a" "invalid-narration")))))
    (test-case "competing candidates remain available without granting an effect"
      (let* ((second (.cc proposal identity: "candidate-b" type: "fix"
                                     rationale: "Repairs the previous admission gap"))
             (result (assess naming (list source) (list proposal second))))
        (check-equal? (length (.get result titles)) 2)
        (check-equal? (length (.get result eligible)) 2)))
    (test-case "reasoning can explain the proposal beyond the title's length limit"
      (let* ((extended (.cc proposal rationale:
                       "The change introduces source-bound admission rather than changing only presentation.\nThe affected GitOps module owns that admission and the project document supplies its engineering reference."))
             (view (assess naming (list source) (list extended))))
        (check-equal? (.get view titles) (.get (assess) titles))
        (check-equal? (.get view open) '())))
    (test-case "ASCENT admits language from the recorded project"
      (let* ((project-language (.cc naming primary-language: "en"))
             (inferred (assess))
             (view (assess project-language)))
        (check-equal? (.get view titles) (.get inferred titles))
        (check-equal? (.get view languages) '(("candidate-a" "en" "docs/design.org")))
        (check-equal? (.get (assess project-language (list source)
                                    (list (.cc proposal language: "fr"))) open)
                      '(("candidate-a" "language-conflict")))
        (check-equal? (.get (assess naming (list source)
                                    (list (.cc proposal language-source: "unobserved.org"))) open)
                      '(("candidate-a" "missing-language-source")))
        (check (equal? (.get inferred context) (.get view context)) => #f)))
    (test-case "language evidence must belong to the current project revision"
      (let* ((language-source (.cc source path: "README.org" text: "The project uses English.\n"))
             (policy (.cc naming language-sources: '("README.org")))
             (candidate (.cc proposal language: "en" language-source: "README.org"
                             summary: "Verify the engineering reference"))
             (current (assess policy (list source language-source) (list candidate))))
        (check-equal? (.get current open) '())
        (check-equal? (.get current languages) '(("candidate-a" "en" "README.org")))
        (for-each
         (lambda (observations)
           (let (result (assess policy observations (list candidate)))
             (check-equal? (.get result titles) '())
             (check-equal? (.get result open) '(("candidate-a" "missing-language-source")))))
         (list (list source)
               (list source (.cc language-source cut: (.cc current-cut tree: "old-tree")))))
        (for-each
         (lambda (competing)
           (let (result (assess policy (list source language-source competing) (list candidate)))
             (check-equal? (.get result titles) '())
             (check-equal? (.get result languages) '())
             (check (equal? (.get result context) (.get current context)) => #f)
             (check-equal? (.get result open) '(("candidate-a" "conflicting-language-source")))))
         (list (.cc language-source cut: (.cc current-cut tree: "old-tree"))
               (.cc language-source text: "Conflicting observation\n")))))
    (test-case "duplicate proposal identities cannot hide competing intent"
      (check-equal? (.get (assess naming (list source)
                                  (list proposal (.cc proposal type: "fix"))) titles) '()))
    (test-case "conflicting engineering reference origins keep the proposal open"
      (let* ((other (.cc source path: "docs/other.org"))
             (policy (.cc naming references: (list reference (.cc reference source: "docs/other.org"))))
             (conflict (assess policy (list source other))))
        (check-equal? (.get conflict titles) '())
        (check-equal? (.get conflict open)
                      '(("candidate-a" "conflicting-reference")))
        (for-each
         (lambda (sources)
           (let (view (assess policy sources))
             (check-equal? (.get view titles) '())
             (check-equal? (.get view eligible) '())
             (check-equal? (.get view open) '(("candidate-a" "conflicting-reference")))
             (check-equal? (.get view unresolved-references) '(("RFC-7")))))
         (list (list source)
               (list source (.cc other cut: (.cc current-cut operation: "retired")))
               (list source (.cc other text: "* An unrelated record\n"))))
        (let* ((same-document
                (.cc naming references: (list reference (.cc reference element: "other"))))
               (view (assess same-document)))
          (check-equal? (.get view titles) '())
          (check-equal? (.get view open) '(("candidate-a" "conflicting-reference"))))
        (check-equal? (.get (assess (.cc naming references: (list reference reference))) titles)
                      (.get (assess) titles))))
    (test-case "duplicate observations of a source path cannot hide invalid evidence"
      (for-each
       (lambda (duplicate)
         (let (view (assess naming (list source duplicate)))
           (check-equal? (.get view titles) '())
           (check-equal? (length (.get view open)) 2)
           (check (not (not (member '("candidate-a" "missing-reference") (.get view open)))) => #t)
           (check (not (not (member '("candidate-a" "conflicting-language-source")
                                    (.get view open)))) => #t)))
       (list (.cc source text: "* A different element\n")
             (.cc source cut: (.cc current-cut operation: "retired")))))
    (test-case "source, policy and affected paths participate in the review context"
      (let (original (.get (assess) context))
        (check (equal? original (.get (assess (.cc naming project-key: "OTHER")) context)) => #f)
        (check (equal? original
                       (.get (assess naming (list source)
                                     (list (.cc proposal rationale: "A different proposed rationale"))) context)) => #f)
        (check (equal? original (.get (assess naming (list (.cc source text:
                                                   (string-append (.get source text) "Revised.\n")))) context)) => #f)
        (check (equal? original (.get (assess naming (list source) (list proposal)
                                            '("modules/gitops/types.ss")) context)) => #f)))
    (test-case "description admission requires the inferred title and current rule context"
      (let* ((catalog-fixture (.o source-lock-digest: "catalog-fixture"))
             (base-policy (.o standard: catalog-fixture primary: "SWE-084"
                              checks: '(("SWE-084" "jj.configuration-audit"))
                              rule-context: "build-a"))
             (semantic-view (assess))
             (policy (.cc base-policy semantics: semantic-view))
             (execution-value
              (.o observation: (.o cut: current-cut identity: "audit" obligation: "SWE-084" outcome: 'passed)
                  method: "jj.configuration-audit" producer: "test-host"
                  input-digest: "input" report-digest: "report"))
             (candidates (list (.o execution: execution-value
                                   source: (gitops-commit-check-receipt execution-value))))
             (org "* Evidence\n:PROPERTIES:\n:AITIA_SUPPORT: SWE-084\n:END:\n")
             (canonical (cadar (.get semantic-view titles)))
             (describe (lambda (selected title-text text context-text (assessment-org org))
                         (gitops-nasa-commit-description selected current-cut candidates
                           title-text text assessment-org context-text)))
             (body (.o change: "Review the current change."
                       evidence: '(("SWE-084" "The configured audit passed.")) open: '()))
             (preview (lambda (selected text (assessment-org org))
                        (gitops-nasa-commit-description selected current-cut candidates
                          canonical text assessment-org "unreviewed context" preview?: #t)))
             (context-value (.get (preview policy body) context)))
        (check-equal? (.get (describe policy canonical body context-value) description)
                      (string-append canonical "\n\nReview the current change.\n\nEvidence\n"
                                     "- SWE-084: The configured audit passed.\n"))
        (check-equal? (.get (describe policy "A plausible free-form title" body context-value) description) #f)
        (check-equal? (.get (describe policy canonical body "unreviewed context") description) #f)
        (let ((discovery (.get (gitops-nasa-draft-requirements policy current-cut candidates) context))
              (revised-body (.cc body change: "Add an unreviewed claim."))
              (revised-org (string-append org "Additional material.\n")))
          (check-equal? (.get (describe policy canonical body discovery) description) #f)
          (check-equal? (.get (describe policy canonical revised-body context-value) description) #f)
          (check-equal? (.get (describe policy canonical body context-value revised-org) description) #f)
          (check (string? (.get (describe policy canonical revised-body
                                           (.get (preview policy revised-body) context)) description)) => #t)
          (check-equal? (.get (preview policy body revised-org) description)
                        (.get (preview policy body) description)))
        (let* ((changed (.cc policy rule-context: "build-b"))
               (new-context (.get (preview changed body) context)))
          (check (equal? context-value new-context) => #f)
          (check-equal? (.get (describe changed canonical body context-value) description) #f)
          (check (string? (.get (describe changed canonical body new-context) description)) => #t))
        ;; A new source association may preserve the title and engineering ID.
        ;; Its earlier review must still be invalidated on the same project cut.
        (let* ((observations (list source (.cc source path: "docs/rebound.org")))
               (initial-view (assess naming observations))
               (rebound-view
                (assess (.cc naming references: (list (.cc reference source: "docs/rebound.org")))
                        observations))
               (initial-policy (.cc base-policy semantics: initial-view))
               (rebound-policy (.cc base-policy semantics: rebound-view))
               (initial-context (.get (preview initial-policy body) context))
               (rebound-context (.get (preview rebound-policy body) context)))
          (check-equal? (.get initial-view titles) (.get rebound-view titles))
          (check (equal? initial-context rebound-context) => #f)
          (check-equal? (.get (describe rebound-policy canonical body initial-context) description) #f)
          (check (string? (.get (describe rebound-policy canonical body rebound-context) description)) => #t))
        (let* ((withdrawn (.cc policy semantics: (assess naming '())))
               (new-context (.get (preview withdrawn body) context)))
          (check-equal? (.get (describe withdrawn canonical body new-context) description) #f))
        (let (unadmitted-context (.get (preview base-policy body) context))
          (check-equal? (.get (describe base-policy canonical body unadmitted-context) description) #f))
        (check-equal? (.get (describe policy canonical (.cc body change: "sha256:unreviewed")
                                      context-value) description) #f)))))
