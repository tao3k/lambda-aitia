;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: Scheme-owned 5-state AI-Native Mixed-Initiative Inversion-of-Control
;;; protocol (RFC 0008):
;;;   1. `need-host-frames` (`host-probe` / `model-reality-gap`): missing read-only HostRead
;;;      observations; Rust dispatches automatically without interrupting the human.
;;;   2. `need-agent-synthesis` (`agent-synthesis` / `model-check-gap`): machine-checkable
;;;      synthesis holes (unscoped paths, missing narration/reference, profile obligations)
;;;      emitted as bounded Schwarz-style local repair tasks for the AI Agent.
;;;   3. `need-human-decision` (`human-decision` / `requirement-gap`): irreducible competing
;;;      worlds, unsatisfiable contradiction, exhausted/rejected repair rounds, PR route
;;;      mismatch, or explicit human governance approval gate.
;;;   4. `need-fenced-frames` (`host-fenced-effect` / `none`): unique grounded world with live
;;;      approval awaiting a fenced effect frame (`prepare-description` -> `apply-description`
;;;      -> optional `push-reviewed`, `action-authorized?: #f` at plan boundary).
;;;   5. `quiescent` (`none` / `none`): all obligations discharged with zero open holes or gates.

(import (only-in :clan/poo/object .o .get .ref .slot? object?)
        (only-in :std/list/list delete-duplicates/hash)
        (only-in :tao3k/agentic-ai-lab/modules/graph-engine/obligation-graph
                 make-evidence-fact)
        (only-in "./reconcile.ss"
                 workflow-gitops-commit-graph
                 workflow-sdlc-lifecycle-graph
                 workflow-reconcile-frontier
                 workflow-admit-proposal
                 workflow-reconcile)
        (only-in "./multi-repo.ss"
                 workflow-plan-multi-repo-step))

(export workflow-plan-protocol-step)

(def (opt-ref obj key default)
  (if (and (object? obj) (.slot? obj key))
    (.ref obj key)
    default))

(def (build-agent-repair-tasks
      holes semantics naming repair-round decayed-obligations preserved-supported)
  (let ((allowed-scopes (if naming (map (lambda (s) (.get s name)) (.get naming scopes)) '()))
        (allowed-refs (if naming (map (lambda (r) (.get r identity)) (.get naming references)) '()))
        (allowed-types (if naming (.get naming types) '()))
        (unscoped (if semantics (.get semantics unscoped-paths) '()))
        (sem-open (if semantics (.get semantics open) '()))
        (recompute-scope (if (pair? decayed-obligations) 'localized-decay 'synthesis-hole)))
    (map (lambda (h)
           (.o (kind := 'lambda-aitia.workflow.repair-task.v1)
               (hole-id := (.ref h 'hole-id))
               (obligation-id := (.ref h 'obligation-id))
               (gap-kind := 'model-check-gap)
               (target := 'agent-synthesis)
               (repair-round := repair-round)
               (recompute-scope := recompute-scope)
               (decayed-obligations := decayed-obligations)
               (preserved-supported-obligations := preserved-supported)
               (unscoped-paths := unscoped)
               (open-diagnostics := sem-open)
               (allowed-scopes := allowed-scopes)
               (allowed-references := allowed-refs)
               (allowed-types := allowed-types)
               (max-branches := (.ref h 'max-branches))
               (action-authorized? := #f)))
         holes)))

(def (missing-host-frames receipts directory requested-paths model-check-enabled? include-pr?)
  (let ((has-jj-cut? (and (object? receipts) (opt-ref receipts 'jj-observe-cut #f) #t))
        (has-sysml-scopes? (and (object? receipts)
                                (.slot? receipts 'sysml-project-scopes)
                                (list? (.ref receipts 'sysml-project-scopes))))
        (has-pr? (and (object? receipts) (opt-ref receipts 'github-observe-pr #f) #t)))
    (append
     (if has-jj-cut?
       '()
       (list (.o (capability := "gitops.jj.observe-cut")
                 (effect-class := 'host-read)
                 (receipt-key := "gitops.jj.observe-cut")
                 (payload := (.o (directory := directory)
                                 (requested-paths := requested-paths))))))
     (if has-sysml-scopes?
       '()
       (list (.o (capability := "sysml.project-scopes")
                 (effect-class := 'host-read)
                 (receipt-key := "sysml.project-scopes")
                 (payload := (.o (directory := directory)
                                 (enabled := model-check-enabled?))))))
     (if (and include-pr? (not has-pr?))
       (list (.o (capability := "gitops.github.observe-pr")
                 (effect-class := 'host-read)
                 (receipt-key := "gitops.github.observe-pr")
                 (payload := (.o (directory := directory)))))
       '()))))

(def (pr-route-mismatch? pr-receipt push-target)
  (let* ((pr (and push-target
                  (hash-table? pr-receipt)
                  (let ((v (or (hash-get pr-receipt "pullRequest")
                               (let ((p (hash-get pr-receipt "provider")))
                                 (and (hash-table? p) (hash-get p "pullRequest"))))))
                    (and (hash-table? v) v)))))
    (and pr
         (let ((pr-remote (hash-get pr "remote"))
               (pr-source (hash-get pr "source"))
               (target-remote (.ref push-target 'remote))
               (target-bookmark (.ref push-target 'bookmark)))
           (or (and (string? pr-remote) (not (equal? pr-remote target-remote)))
               (and (string? pr-source) (not (equal? pr-source target-bookmark))))))))

(def (fenced-effect-frames
      state directory commit-id fenced-spec prepare-receipt apply-receipt push-target push-receipt)
  (cond
   ((not (eq? state 'need-fenced-frames))
    '())
   ((and apply-receipt push-target (not push-receipt))
    (let* ((applied-commit (or (and (hash-table? apply-receipt)
                                    (hash-get apply-receipt "resulting_commit"))
                               commit-id))
           (applied-op (and (hash-table? apply-receipt)
                            (hash-get apply-receipt "resulting_operation")))
           (applied-desc (or (and (hash-table? apply-receipt)
                                  (hash-get apply-receipt "description"))
                             (and fenced-spec (.ref fenced-spec 'description))))
           (fence-tok (and fenced-spec (.ref fenced-spec 'review-context)))
           (exp-head (opt-ref push-target 'expected-remote-head #f)))
      (list (.o (capability := "gitops.jj.push-reviewed")
                (effect-class := 'fenced-effect)
                (receipt-key := "gitops.jj.push-reviewed")
                (fence-token := (or fence-tok (string-append "push:" applied-commit)))
                (payload := (.o (directory := directory)
                                (remote := (.ref push-target 'remote))
                                (bookmark := (.ref push-target 'bookmark))
                                (expected-commit := applied-commit)
                                (expected-operation := applied-op)
                                (description := applied-desc)
                                (expected-remote-head := exp-head)))))))
   ((and fenced-spec (not prepare-receipt) (not (opt-ref fenced-spec 'attempt #f)))
    (list (.o (capability := "gitops.jj.prepare-description")
              (effect-class := 'fenced-effect)
              (receipt-key := "gitops.jj.prepare-description")
              (fence-token := (.ref fenced-spec 'review-context))
              (payload := (.o (directory := directory)
                              (expected-commit := (.ref fenced-spec 'expected-commit))
                              (expected-operation := (.ref fenced-spec 'expected-operation))
                              (description := (.ref fenced-spec 'description))
                              (review-context := (.ref fenced-spec 'review-context))
                              (proposal-binding := (.ref fenced-spec 'proposal-binding)))))))
   (fenced-spec
    (let ((attempt-val (or prepare-receipt (opt-ref fenced-spec 'attempt #f))))
      (list (.o (capability := "gitops.jj.apply-description")
                (effect-class := 'fenced-effect)
                (receipt-key := "gitops.jj.apply-description")
                (fence-token := (.ref fenced-spec 'review-context))
                (payload := (.o (directory := directory)
                                (expected-commit := (.ref fenced-spec 'expected-commit))
                                (expected-operation := (.ref fenced-spec 'expected-operation))
                                (description := (.ref fenced-spec 'description))
                                (review-context := (.ref fenced-spec 'review-context))
                                (proposal-binding := (.ref fenced-spec 'proposal-binding))
                                (attempt := attempt-val)))))))
   (else
    (list (.o (capability := "gitops.jj.apply-description")
              (effect-class := 'fenced-effect)
              (receipt-key := "gitops.jj.apply-description")
              (payload := (.o (directory := directory)
                              (commit := commit-id))))))))

(def (classify-protocol-state
      unsat blocked holes approval-live? apply-receipt push-target push-receipt
      route-mismatch? choice-sol proposal-res repair-round max-repair-rounds)
  (cond
   ((and apply-receipt push-target (not push-receipt) route-mismatch?)
    (values 'need-human-decision 'push-route-mismatch))
   ((and apply-receipt push-target (not push-receipt) approval-live?
         (null? blocked) (null? holes))
    (values 'need-fenced-frames #f))
   ((and (null? unsat) (null? blocked) (null? holes)
         (or (not push-target) push-receipt))
    (values 'quiescent #f))
   ((and approval-live?
         (not apply-receipt)
         (= (.get choice-sol world-count) 1)
         (eq? (.get (car (.get choice-sol worlds)) dispatch-decision) 'fenced-apply)
         (null? blocked)
         (null? holes))
    (values 'need-fenced-frames #f))
   ((and (pair? holes)
         (not (eq? (.get choice-sol choice-status) 'unsatisfiable)))
    (cond
     ((and proposal-res (not (.get proposal-res admitted?)))
      (values 'need-human-decision 'repair-proposal-rejected))
     ((>= repair-round max-repair-rounds)
      (values 'need-human-decision 'repair-budget-exhausted))
     (else
      (values 'need-agent-synthesis #f))))
   (else
    (values 'need-human-decision #f))))

(def (handoff-for-state state)
  (case state
    ((quiescent) 'none)
    ((need-fenced-frames) 'host-fenced-effect)
    ((need-agent-synthesis) 'agent-synthesis)
    (else 'human-decision)))

(def (gap-for-state state)
  (case state
    ((quiescent need-fenced-frames) 'none)
    ((need-agent-synthesis) 'model-check-gap)
    (else 'requirement-gap)))

(def (plan-sdlc-lifecycle-step ctx)
  (let* ((case-id (opt-ref ctx 'case-id 'aitia/case/sdlc-lifecycle))
         (profile (opt-ref ctx 'profile "lambda-aitia/sdlc"))
         (change-id (opt-ref ctx 'change-id "change:sdlc-default"))
         (design-alts (opt-ref ctx 'design-alternatives '(design-a)))
         (extra-obs (opt-ref ctx 'extra-obligations '()))
         (observed-obs (opt-ref ctx 'observed-obligations '()))
         (req-traced? (opt-ref ctx 'requirements-traced? #t))
         (verified? (opt-ref ctx 'verified? #f))
         (ret-clear? (opt-ref ctx 'retirement-clear? #t))
         (approval-live? (and (opt-ref ctx 'approval-live? #f) #t))
         (release-published? (and (opt-ref ctx 'release-published? #f) #t))
         (refuted (opt-ref ctx 'refuted-designs '()))
         (required-design (opt-ref ctx 'required-design #f))
         (run-reconcile? (opt-ref ctx 'reconcile? #t))
         (proposal (opt-ref ctx 'proposal #f))
         (repair-round (opt-ref ctx 'repair-round 0))
         (max-repair-rounds (opt-ref ctx 'max-repair-rounds 3))
         (graph (workflow-sdlc-lifecycle-graph
                 change-id design-alts
                 profile: profile
                 extra-obligations: extra-obs
                 observed-obligations: observed-obs
                 requirements-traced?: req-traced?
                 verified?: verified?
                 retirement-clear?: ret-clear?
                 approval-live?: approval-live?
                 release-published?: release-published?
                 refuted-designs: refuted
                 required-design: required-design))
         (initial (workflow-reconcile-frontier graph))
         (proposal-res (and proposal (workflow-admit-proposal graph proposal)))
         (report (if run-reconcile? (workflow-reconcile graph) #f))
         (final-frontier (if report (.ref report 'final-frontier) (.get initial frontier)))
         (choice-sol (.get graph choice-solution))
         (unsat (.ref final-frontier 'unsatisfied-obligations))
         (blocked (.ref final-frontier 'blocked-on-human-obligations))
         (holes (.ref final-frontier 'ready-synthesis-holes))
         (discharged (map (lambda (o) (.ref o 'obligation-id))
                          (.ref final-frontier 'discharged-obligations))))
    (let-values (((state escalation-reason)
                  (classify-protocol-state
                   unsat blocked holes approval-live? release-published?
                   #f #f #f choice-sol proposal-res repair-round max-repair-rounds)))
      (let* ((repair-tasks
              (if (eq? state 'need-agent-synthesis)
                (build-agent-repair-tasks holes #f #f repair-round '() discharged)
                '()))
             (epistemic-summary
              (.o (profile := profile)
                  (choice-status := (.get choice-sol choice-status))
                  (world-count := (.get choice-sol world-count))
                  (supported-count := (length discharged))
                  (stale-count := 0)
                  (open-count := (length unsat))
                  (reopened-count := 0)
                  (decayed-obligations := '())
                  (stale-evidence-ids := '())
                  (evidence-decay-detected? := #f)))
             (fenced-frames
              (if (eq? state 'need-fenced-frames)
                (list (.o (capability := "sdlc.release.publish")
                          (effect-class := 'fenced-effect)
                          (receipt-key := "sdlc.release.publish")
                          (fence-token := (string-append "sdlc-release:" change-id))
                          (payload := (.o (change-id := change-id)
                                          (profile := profile)))))
                '())))
        (.o (kind := 'lambda-aitia.workflow.protocol-step.v1)
            (schema := "lambda-aitia.workflow-protocol-step.v1")
            (profile := profile)
            (state := state)
            (handoff-target := (handoff-for-state state))
            (gap-kind := (gap-for-state state))
            (case-id := case-id)
            (repair-round := repair-round)
            (max-repair-rounds := max-repair-rounds)
            (escalation-reason := escalation-reason)
            (frames := fenced-frames)
            (repair-tasks := repair-tasks)
            (epistemic-summary := epistemic-summary)
            (applied-receipt := (and release-published?
                                     (hash ("changeId" change-id) ("profile" profile))))
            (pushed-receipt := #f)
            (graph := graph)
            (initial-frontier := initial)
            (report := report)
            (final-frontier := final-frontier)
            (proposal-admission := proposal-res)
            (action-authorized? := #f))))))

(def (workflow-plan-protocol-step ctx)
  (unless (object? ctx)
    (error "workflow-plan-protocol-step expects a POO protocol context" ctx))
  (let ((case-id (opt-ref ctx 'case-id 'aitia/case/gitops-commit)))
    (cond
     ((or (eq? case-id 'aitia/case/sdlc-lifecycle)
          (equal? case-id "aitia/case/sdlc-lifecycle"))
      (plan-sdlc-lifecycle-step ctx))
     ((or (eq? case-id 'aitia/case/multi-repo-gitops)
          (equal? case-id "aitia/case/multi-repo-gitops"))
      (workflow-plan-multi-repo-step ctx workflow-plan-protocol-step))
     (else
      (let* ((profile (opt-ref ctx 'profile "lambda-aitia/sdlc"))
             (required-checks (opt-ref ctx 'required-checks #f))
             (directory (opt-ref ctx 'directory "."))
             (requested-paths (opt-ref ctx 'requested-paths '()))
             (model-check-enabled? (opt-ref ctx 'model-check-enabled? #t))
             (push-target (opt-ref ctx 'push-target #f))
             (include-pr? (or (and (opt-ref ctx 'include-pr-observation? #f) #t)
                              (and push-target #t)))
             (repair-round (opt-ref ctx 'repair-round 0))
             (max-repair-rounds (opt-ref ctx 'max-repair-rounds 3))
             (receipts (opt-ref ctx 'receipts (.o)))
             (missing-frames
              (missing-host-frames
               receipts directory requested-paths model-check-enabled? include-pr?)))
        (if (pair? missing-frames)
          (.o (kind := 'lambda-aitia.workflow.protocol-step.v1)
              (schema := "lambda-aitia.workflow-protocol-step.v1")
              (profile := profile)
              (state := 'need-host-frames)
              (handoff-target := 'host-probe)
              (gap-kind := 'model-reality-gap)
              (case-id := case-id)
              (repair-round := repair-round)
              (max-repair-rounds := max-repair-rounds)
              (escalation-reason := #f)
              (frames := missing-frames)
              (repair-tasks := '())
              (epistemic-summary := #f)
              (applied-receipt := #f)
              (pushed-receipt := #f)
              (graph := #f)
              (initial-frontier := #f)
              (report := #f)
              (final-frontier := #f)
              (proposal-admission := #f)
              (action-authorized? := #f))
          (let* ((naming (.ref ctx 'naming))
                 (cut (.ref ctx 'cut))
                 (commit-id (.get cut commit))
                 (cut-premise (string-append "premise:cut:" commit-id))
                 (sources (opt-ref ctx 'sources '()))
                 (paths (opt-ref ctx 'paths '()))
                 (proposals (opt-ref ctx 'proposals '()))
                 (observations (opt-ref ctx 'observations '()))
                 (approval-live? (and (opt-ref ctx 'approval-live? #f) #t))
                 (candidate-offers (opt-ref ctx 'candidate-offers '()))
                 (forbidden-scopes (opt-ref ctx 'forbidden-scopes '()))
                 (run-reconcile? (opt-ref ctx 'reconcile? #t))
                 (proposal (opt-ref ctx 'proposal #f))
                 (fenced-spec (opt-ref ctx 'fenced-commit-spec #f))
                 (pr-receipt (and (object? receipts) (opt-ref receipts 'github-observe-pr #f)))
                 (prepare-receipt (and (object? receipts) (opt-ref receipts 'jj-prepare-description #f)))
                 (apply-receipt (and (object? receipts) (opt-ref receipts 'jj-apply-description #f)))
                 (push-receipt (and (object? receipts) (opt-ref receipts 'jj-push-reviewed #f)))
                 (applied-evidence
                  (if apply-receipt
                    (list (make-evidence-fact
                           "ev:gitops-commit-receipt"
                           (.o (kind := 'commit-applied-receipt) (commit := commit-id))
                           cut: 1
                           premise-ids: (list cut-premise)
                           origin-tier: 'observed-fact))
                    '()))
                 (graph (workflow-gitops-commit-graph
                         naming cut sources paths proposals
                         profile: profile
                         required-checks: required-checks
                         observations: observations
                         approval-live?: approval-live?
                         candidate-offers: candidate-offers
                         forbidden-scopes: forbidden-scopes
                         extra-evidence: applied-evidence))
                 (initial (workflow-reconcile-frontier graph))
                 (proposal-res (and proposal (workflow-admit-proposal graph proposal)))
                 (report (if run-reconcile? (workflow-reconcile graph) #f))
                 (final-frontier (if report (.ref report 'final-frontier) (.get initial frontier)))
                 (choice-sol (.get graph choice-solution))
                 (semantics (.get graph semantics-assessment))
                 (evidence-view (.get graph evidence-assessment))
                 (decayed-obligations (map car (.get evidence-view reopened)))
                 (stale-evidence-ids (map car (.get evidence-view stale)))
                 (preserved-supported
                  (delete-duplicates/hash (map cadr (.get evidence-view supported))))
                 (unsat (.ref final-frontier 'unsatisfied-obligations))
                 (blocked (.ref final-frontier 'blocked-on-human-obligations))
                 (holes (.ref final-frontier 'ready-synthesis-holes))
                 (route-mismatch? (pr-route-mismatch? pr-receipt push-target)))
            (let-values (((state escalation-reason)
                          (classify-protocol-state
                           unsat blocked holes approval-live? apply-receipt
                           push-target push-receipt route-mismatch?
                           choice-sol proposal-res repair-round max-repair-rounds)))
              (let* ((repair-tasks
                      (if (eq? state 'need-agent-synthesis)
                        (build-agent-repair-tasks
                         holes semantics naming repair-round
                         decayed-obligations preserved-supported)
                        '()))
                     (epistemic-summary
                      (.o (profile := profile)
                          (choice-status := (.get choice-sol choice-status))
                          (world-count := (.get choice-sol world-count))
                          (supported-count := (length (.get evidence-view supported)))
                          (stale-count := (length (.get evidence-view stale)))
                          (open-count := (length (.get evidence-view open)))
                          (reopened-count := (length (.get evidence-view reopened)))
                          (decayed-obligations := decayed-obligations)
                          (stale-evidence-ids := stale-evidence-ids)
                          (evidence-decay-detected? := (or (pair? decayed-obligations)
                                                           (pair? stale-evidence-ids)))))
                     (fenced-frames
                      (fenced-effect-frames
                       state directory commit-id fenced-spec
                       prepare-receipt apply-receipt push-target push-receipt)))
                (.o (kind := 'lambda-aitia.workflow.protocol-step.v1)
                    (schema := "lambda-aitia.workflow-protocol-step.v1")
                    (profile := profile)
                    (state := state)
                    (handoff-target := (handoff-for-state state))
                    (gap-kind := (gap-for-state state))
                    (case-id := case-id)
                    (repair-round := repair-round)
                    (max-repair-rounds := max-repair-rounds)
                    (escalation-reason := escalation-reason)
                    (frames := fenced-frames)
                    (repair-tasks := repair-tasks)
                    (epistemic-summary := epistemic-summary)
                    (applied-receipt := apply-receipt)
                    (pushed-receipt := push-receipt)
                    (graph := graph)
                    (initial-frontier := initial)
                    (report := report)
                    (final-frontier := final-frontier)
                    (proposal-admission := proposal-res)
                    (action-authorized? := #f)))))))))))
