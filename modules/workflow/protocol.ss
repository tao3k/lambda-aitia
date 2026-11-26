;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: Scheme-owned 5-state AI-Native Mixed-Initiative Inversion-of-Control
;;; protocol (RFC 0008):
;;;   1. `need-host-frames` (`host-probe` / `model-reality-gap`): missing read-only HostRead
;;;      observations; Rust dispatches automatically without interrupting the human.
;;;   2. `need-agent-synthesis` (`agent-synthesis` / `model-check-gap`): machine-checkable
;;;      synthesis holes (unscoped paths, missing narration/reference) emitted as Schwarz-style
;;;      local repair tasks for the AI Agent.
;;;   3. `need-human-decision` (`human-decision` / `requirement-gap`): irreducible competing
;;;      worlds, unsatisfiable contradiction, or explicit human governance approval gate.
;;;   4. `need-fenced-frames` (`host-fenced-effect` / `none`): unique grounded world with live
;;;      approval awaiting a fenced effect frame (`action-authorized?: #f` at plan boundary).
;;;   5. `quiescent` (`none` / `none`): all obligations discharged with zero open holes or gates.

(import (only-in :clan/poo/object .o .get .ref .slot? object?)
        (only-in :tao3k/agentic-ai-lab/modules/graph-engine/obligation-graph
                 make-evidence-fact)
        (only-in "./reconcile.ss"
                 workflow-gitops-commit-graph
                 workflow-reconcile-frontier
                 workflow-admit-proposal
                 workflow-reconcile))

(export workflow-plan-protocol-step)

(def (opt-ref obj key default)
  (if (and (object? obj) (.slot? obj key))
    (.ref obj key)
    default))

(def (build-agent-repair-tasks holes semantics naming)
  (let ((allowed-scopes (map (lambda (s) (.get s name)) (.get naming scopes)))
        (allowed-refs (map (lambda (r) (.get r identity)) (.get naming references)))
        (allowed-types (.get naming types))
        (unscoped (.get semantics unscoped-paths))
        (sem-open (.get semantics open)))
    (map (lambda (h)
           (.o (kind := 'lambda-aitia.workflow.repair-task.v1)
               (hole-id := (.ref h 'hole-id))
               (obligation-id := (.ref h 'obligation-id))
               (gap-kind := 'model-check-gap)
               (target := 'agent-synthesis)
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

(def (fenced-effect-frames state directory commit-id fenced-spec prepare-receipt)
  (cond
   ((not (eq? state 'need-fenced-frames))
    '())
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

(def (protocol-step-state unsat blocked holes approval-live? apply-receipt choice-sol)
  (cond
   ((and (null? unsat) (null? blocked) (null? holes))
    'quiescent)
   ((and approval-live?
         (not apply-receipt)
         (= (.get choice-sol world-count) 1)
         (eq? (.get (car (.get choice-sol worlds)) dispatch-decision) 'fenced-apply)
         (null? blocked)
         (null? holes))
    'need-fenced-frames)
   ((and (pair? holes)
         (not (eq? (.get choice-sol choice-status) 'unsatisfiable)))
    'need-agent-synthesis)
   (else
    'need-human-decision)))

(def (workflow-plan-protocol-step ctx)
  (unless (object? ctx)
    (error "workflow-plan-protocol-step expects a POO protocol context" ctx))
  (let* ((case-id (opt-ref ctx 'case-id 'aitia/case/gitops-commit))
         (profile (opt-ref ctx 'profile "lambda-aitia/sdlc"))
         (required-checks (opt-ref ctx 'required-checks #f))
         (directory (opt-ref ctx 'directory "."))
         (requested-paths (opt-ref ctx 'requested-paths '()))
         (model-check-enabled? (opt-ref ctx 'model-check-enabled? #t))
         (include-pr? (and (opt-ref ctx 'include-pr-observation? #f) #t))
         (receipts (opt-ref ctx 'receipts (.o)))
         (missing-frames
          (missing-host-frames receipts directory requested-paths model-check-enabled? include-pr?)))
    (if (pair? missing-frames)
      (.o (kind := 'lambda-aitia.workflow.protocol-step.v1)
          (schema := "lambda-aitia.workflow-protocol-step.v1")
          (profile := profile)
          (state := 'need-host-frames)
          (handoff-target := 'host-probe)
          (gap-kind := 'model-reality-gap)
          (case-id := case-id)
          (frames := missing-frames)
          (repair-tasks := '())
          (epistemic-summary := #f)
          (applied-receipt := #f)
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
             (prepare-receipt (and (object? receipts) (opt-ref receipts 'jj-prepare-description #f)))
             (apply-receipt (and (object? receipts) (opt-ref receipts 'jj-apply-description #f)))
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
             (unsat (.ref final-frontier 'unsatisfied-obligations))
             (blocked (.ref final-frontier 'blocked-on-human-obligations))
             (holes (.ref final-frontier 'ready-synthesis-holes))
             (state (protocol-step-state unsat blocked holes approval-live? apply-receipt choice-sol))
             (handoff-target
              (case state
                ((quiescent) 'none)
                ((need-fenced-frames) 'host-fenced-effect)
                ((need-agent-synthesis) 'agent-synthesis)
                (else 'human-decision)))
             (gap-kind
              (case state
                ((quiescent need-fenced-frames) 'none)
                ((need-agent-synthesis) 'model-check-gap)
                (else 'requirement-gap)))
             (repair-tasks
              (if (eq? state 'need-agent-synthesis)
                (build-agent-repair-tasks holes semantics naming)
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
              (fenced-effect-frames state directory commit-id fenced-spec prepare-receipt)))
        (.o (kind := 'lambda-aitia.workflow.protocol-step.v1)
            (schema := "lambda-aitia.workflow-protocol-step.v1")
            (profile := profile)
            (state := state)
            (handoff-target := handoff-target)
            (gap-kind := gap-kind)
            (case-id := case-id)
            (frames := fenced-frames)
            (repair-tasks := repair-tasks)
            (epistemic-summary := epistemic-summary)
            (applied-receipt := apply-receipt)
            (graph := graph)
            (initial-frontier := initial)
            (report := report)
            (final-frontier := final-frontier)
            (proposal-admission := proposal-res)
            (action-authorized? := #f))))))
