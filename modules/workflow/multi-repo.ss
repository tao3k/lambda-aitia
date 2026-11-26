;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: Pure functional Multi-Repo GitOps wave orchestrator over
;;; Lambda Aitia's 5-state Mixed-Initiative IoC protocol (RFC 0008).
;;;
;;; Invariants:
;;;   1. Strict topological wave ordering (Kahn's algorithm): downstream fenced
;;;      effects are NEVER emitted until all upstream dependencies are quiescent.
;;;   2. Dependency cycles and unknown upstream repo references fail closed to
;;;      `need-human-decision` (`dependency-cycle` / `unknown-repo-dependency`).
;;;   3. Cross-repo bitemporal pin-drift detection: when an upstream repo's live
;;;      or applied commit diverges from a downstream repo's pinned commit, a
;;;      localized Schwarz `cross-repo-pin-drift` repairTask is emitted while
;;;      disjoint unaffected repos stay preserved.
;;;   4. Read-only `HostRead` probes fan out in parallel across all repo
;;;      directories with repo-qualified `receiptKey` (`repo:<id>:<cap>`).
;;;   5. `action-authorized?: #f` at every planning boundary.

(import (only-in :clan/poo/object .o .get .ref .slot? object?)
        (only-in :std/list/list append-map every filter find))

(export workflow-plan-multi-repo-step)

(def (opt-ref obj key default)
  (if (and (object? obj) (.slot? obj key))
    (.ref obj key)
    default))

(def (repo-receipt-key rid cap)
  (string-append "repo:" rid ":" cap))

(def (repo-effective-commit repo-spec raw-receipts)
  (let* ((rid (.ref repo-spec 'repo-id))
         (apply-rcpt (and (hash-table? raw-receipts)
                          (hash-get raw-receipts (repo-receipt-key rid "gitops.jj.apply-description"))))
         (obs-rcpt (and (hash-table? raw-receipts)
                        (hash-get raw-receipts (repo-receipt-key rid "gitops.jj.observe-cut"))))
         (cut-obj (opt-ref repo-spec 'cut #f)))
    (or (and (hash-table? apply-rcpt) (hash-get apply-rcpt "resulting_commit"))
        (and (hash-table? obs-rcpt)
             (let ((c (hash-get obs-rcpt "cut")))
               (and (hash-table? c) (hash-get c "commit"))))
        (and (object? cut-obj) (.slot? cut-obj 'commit) (.get cut-obj commit))
        (opt-ref repo-spec 'cut-commit #f))))

(def (find-unknown-dependency repos repo-ids)
  (let loop ((rest repos))
    (if (null? rest)
      #f
      (let* ((r (car rest))
             (rid (.ref r 'repo-id))
             (deps (opt-ref r 'depends-on '()))
             (bad (find (lambda (d) (not (member d repo-ids))) deps)))
        (if bad
          (cons rid bad)
          (loop (cdr rest)))))))

;;; Pure Kahn topological wave partitioning.
;;; Returns `(values waves cycle-repos)` where `waves` is a list of lists of repo-ids
;;; (each wave's members have disjoint upstream prerequisites) and `cycle-repos` is
;;; non-empty iff the dependency graph contains a cycle.
(def (compute-repo-waves repos)
  (let loop ((remaining repos) (done '()) (waves '()))
    (if (null? remaining)
      (values (reverse waves) '())
      (let ((ready (filter (lambda (r)
                             (every (lambda (d) (member d done))
                                    (opt-ref r 'depends-on '())))
                           remaining)))
        (if (null? ready)
          (values (reverse waves) (map (lambda (r) (.ref r 'repo-id)) remaining))
          (let* ((wave-ids (map (lambda (r) (.ref r 'repo-id)) ready))
                 (next-done (append done wave-ids))
                 (next-rem (filter (lambda (r) (not (member (.ref r 'repo-id) wave-ids)))
                                   remaining)))
            (loop next-rem next-done (cons wave-ids waves))))))))

(def (detect-pin-drifts repos raw-receipts)
  (let ((commit-map
         (map (lambda (r) (cons (.ref r 'repo-id) (repo-effective-commit r raw-receipts)))
              repos)))
    (append-map
     (lambda (r)
       (let ((rid (.ref r 'repo-id))
             (pins (opt-ref r 'pinned-upstream-commits '())))
         (append-map
          (lambda (pin)
            (let* ((up-id (car pin))
                   (expected (cdr pin))
                   (entry (assoc up-id commit-map))
                   (actual (and entry (cdr entry))))
              (if (and (string? expected) (string? actual) (not (equal? expected actual)))
                (list (.o (repo-id := rid)
                          (upstream-repo := up-id)
                          (expected-commit := expected)
                          (actual-commit := actual)))
                '())))
          pins)))
     repos)))

(def (qualify-frame rid frame)
  (let ((cap (.get frame capability))
        (rkey (repo-receipt-key rid (.get frame receipt-key))))
    (.o (capability := cap)
        (effect-class := (.get frame effect-class))
        (receipt-key := rkey)
        (repo-id := rid)
        (fence-token := (opt-ref frame 'fence-token #f))
        (payload := (.get frame payload)))))

(def (build-pin-drift-repair-tasks drifts preserved-repos repair-round)
  (map (lambda (d)
         (let ((rid (.ref d 'repo-id))
               (up (.ref d 'upstream-repo))
               (exp (.ref d 'expected-commit))
               (act (.ref d 'actual-commit)))
           (.o (kind := 'lambda-aitia.workflow.repair-task.v1)
               (hole-id := (string-append "hole:pin-drift:" rid ":" up))
               (obligation-id := (string-append "multi-repo.pin-aligned:" rid ":" up))
               (repo-id := rid)
               (upstream-repo := up)
               (expected-commit := exp)
               (actual-commit := act)
               (gap-kind := 'model-check-gap)
               (target := 'agent-synthesis)
               (repair-round := repair-round)
               (recompute-scope := 'cross-repo-pin-drift)
               (decayed-obligations := (list (string-append "multi-repo.pin-aligned:" rid ":" up)))
               (preserved-supported-obligations := preserved-repos)
               (unscoped-paths := '())
               (open-diagnostics := (list (list "pin-drift" rid up exp act)))
               (allowed-scopes := '())
               (allowed-references := '())
               (allowed-types := '())
               (max-branches := 2)
               (action-authorized? := #f))))
       drifts))

(def (repo-sub-receipts rid raw-receipts)
  (if (not (hash-table? raw-receipts))
    (.o)
    (.o (jj-observe-cut := (hash-get raw-receipts (repo-receipt-key rid "gitops.jj.observe-cut")))
        (sysml-project-scopes := (let ((v (hash-get raw-receipts (repo-receipt-key rid "sysml.project-scopes"))))
                                   (cond
                                    ((vector? v) (vector->list v))
                                    ((list? v) v)
                                    (else #f))))
        (github-observe-pr := (hash-get raw-receipts (repo-receipt-key rid "gitops.github.observe-pr")))
        (jj-prepare-description := (hash-get raw-receipts (repo-receipt-key rid "gitops.jj.prepare-description")))
        (jj-apply-description := (hash-get raw-receipts (repo-receipt-key rid "gitops.jj.apply-description")))
        (jj-push-reviewed := (hash-get raw-receipts (repo-receipt-key rid "gitops.jj.push-reviewed"))))))

(def (make-multi-repo-step
      case-id profile state escalation-reason repair-round max-repair-rounds
      waves repo-summaries frames repair-tasks drifts)
  (let* ((handoff (case state
                    ((quiescent) 'none)
                    ((need-host-frames) 'host-probe)
                    ((need-fenced-frames) 'host-fenced-effect)
                    ((need-agent-synthesis) 'agent-synthesis)
                    (else 'human-decision)))
         (gap (case state
                ((quiescent need-fenced-frames) 'none)
                ((need-host-frames) 'model-reality-gap)
                ((need-agent-synthesis) 'model-check-gap)
                (else 'requirement-gap)))
         (quiescent-count (length (filter (lambda (rs) (eq? (.ref rs 'state) 'quiescent)) repo-summaries)))
         (open-count (- (length repo-summaries) quiescent-count)))
    (.o (kind := 'lambda-aitia.workflow.protocol-step.v1)
        (schema := "lambda-aitia.workflow-protocol-step.v1")
        (profile := profile)
        (state := state)
        (handoff-target := handoff)
        (gap-kind := gap)
        (case-id := case-id)
        (repair-round := repair-round)
        (max-repair-rounds := max-repair-rounds)
        (escalation-reason := escalation-reason)
        (frames := frames)
        (repair-tasks := repair-tasks)
        (epistemic-summary := (.o (profile := profile)
                                  (choice-status := (if (eq? state 'quiescent) 'unique-deduction 'competing-worlds))
                                  (world-count := 1)
                                  (supported-count := quiescent-count)
                                  (stale-count := (length drifts))
                                  (open-count := open-count)
                                  (reopened-count := (length drifts))
                                  (decayed-obligations :=
                                   (map (lambda (d)
                                          (string-append "multi-repo.pin-aligned:"
                                                         (.ref d 'repo-id) ":"
                                                         (.ref d 'upstream-repo)))
                                        drifts))
                                  (stale-evidence-ids := '())
                                  (evidence-decay-detected? := (pair? drifts))))
        (applied-receipt := #f)
        (pushed-receipt := #f)
        (waves := waves)
        (repo-summaries := repo-summaries)
        (pin-drifts := drifts)
        (graph := #f)
        (initial-frontier := #f)
        (report := #f)
        (final-frontier := #f)
        (proposal-admission := #f)
        (action-authorized? := #f))))

(def (workflow-plan-multi-repo-step ctx single-repo-planner)
  (let* ((case-id (opt-ref ctx 'case-id 'aitia/case/multi-repo-gitops))
         (profile (opt-ref ctx 'profile "lambda-aitia/sdlc"))
         (repos (opt-ref ctx 'repos '()))
         (raw-receipts (opt-ref ctx 'raw-receipts (hash)))
         (repair-round (opt-ref ctx 'repair-round 0))
         (max-repair-rounds (opt-ref ctx 'max-repair-rounds 3))
         (repo-ids (map (lambda (r) (.ref r 'repo-id)) repos))
         (unknown-dep (find-unknown-dependency repos repo-ids)))
    (if unknown-dep
      (make-multi-repo-step
       case-id profile 'need-human-decision 'unknown-repo-dependency
       repair-round max-repair-rounds '() '() '() '() '())
      (let-values (((waves cycle-repos) (compute-repo-waves repos)))
        (if (pair? cycle-repos)
          (make-multi-repo-step
           case-id profile 'need-human-decision 'dependency-cycle
           repair-round max-repair-rounds waves '() '() '() '())
          (let* ((repo-results
                  (map (lambda (r)
                         (let* ((rid (.ref r 'repo-id))
                                (r-profile (opt-ref r 'profile profile))
                                (sub-rcpts (or (opt-ref r 'receipts #f)
                                               (repo-sub-receipts rid raw-receipts)))
                                (sub-ctx (.o (case-id := 'aitia/case/gitops-commit)
                                             (profile := r-profile)
                                             (required-checks := (opt-ref r 'required-checks #f))
                                             (directory := (opt-ref r 'directory "."))
                                             (requested-paths := (opt-ref r 'requested-paths '()))
                                             (model-check-enabled? := (opt-ref r 'model-check-enabled? #t))
                                             (include-pr-observation? := (opt-ref r 'include-pr-observation? #f))
                                             (fenced-commit-spec := (opt-ref r 'fenced-commit-spec #f))
                                             (push-target := (opt-ref r 'push-target #f))
                                             (repair-round := repair-round)
                                             (max-repair-rounds := max-repair-rounds)
                                             (receipts := sub-rcpts)
                                             (naming := (opt-ref r 'naming #f))
                                             (cut := (opt-ref r 'cut #f))
                                             (sources := (opt-ref r 'sources '()))
                                             (paths := (opt-ref r 'paths '()))
                                             (proposals := (opt-ref r 'proposals '()))
                                             (observations := (opt-ref r 'observations '()))
                                             (proposal := (opt-ref r 'proposal #f))
                                             (approval-live? := (opt-ref r 'approval-live? #f))
                                             (candidate-offers := (opt-ref r 'candidate-offers '()))
                                             (forbidden-scopes := (opt-ref r 'forbidden-scopes '()))
                                             (reconcile? := (opt-ref r 'reconcile? #t))))
                                (step (single-repo-planner sub-ctx)))
                           (cons rid (cons r step))))
                       repos))
                 (host-frames
                  (append-map
                   (lambda (entry)
                     (let ((rid (car entry))
                           (step (cddr entry)))
                       (if (eq? (.get step state) 'need-host-frames)
                         (map (lambda (f) (qualify-frame rid f)) (.get step frames))
                         '())))
                   repo-results))
                 (drifts (detect-pin-drifts repos raw-receipts))
                 (drifted-ids (map (lambda (d) (.ref d 'repo-id)) drifts))
                 (quiescent-ids
                  (map car (filter (lambda (e)
                                     (and (eq? (.get (cddr e) state) 'quiescent)
                                          (not (member (car e) drifted-ids))))
                                   repo-results)))
                 (repo-summaries
                  (map (lambda (entry)
                         (let* ((rid (car entry))
                                (r (cadr entry))
                                (step (cddr entry))
                                (deps (opt-ref r 'depends-on '()))
                                (deps-ready? (every (lambda (d) (member d quiescent-ids)) deps))
                                (drifted? (member rid drifted-ids))
                                (eff-state
                                 (cond
                                  ((eq? (.get step state) 'need-host-frames) 'need-host-frames)
                                  (drifted? 'need-agent-synthesis)
                                  ((not deps-ready?) 'blocked-on-upstream)
                                  (else (.get step state)))))
                           (.o (repo-id := rid)
                               (directory := (opt-ref r 'directory "."))
                               (profile := (.get step profile))
                               (depends-on := deps)
                               (effective-commit := (repo-effective-commit r raw-receipts))
                               (state := eff-state)
                               (upstream-ready? := deps-ready?)
                               (pin-drifted? := (and drifted? #t))
                               (applied-receipt := (.get step applied-receipt))
                               (pushed-receipt := (.get step pushed-receipt)))))
                       repo-results)))
            (cond
             ;; Phase 1: Fan out all read-only HostRead probes across all repos in parallel.
             ((pair? host-frames)
              (make-multi-repo-step
               case-id profile 'need-host-frames #f repair-round max-repair-rounds
               waves repo-summaries host-frames '() drifts))
             ;; Phase 2: Cross-repo pin drift detected -> localized Schwarz repair (or human escalation).
             ((pair? drifts)
              (let ((preserved (filter (lambda (id) (not (member id drifted-ids))) repo-ids)))
                (if (>= repair-round max-repair-rounds)
                  (make-multi-repo-step
                   case-id profile 'need-human-decision 'repair-budget-exhausted
                   repair-round max-repair-rounds waves repo-summaries '() '() drifts)
                  (make-multi-repo-step
                   case-id profile 'need-agent-synthesis 'cross-repo-pin-drift
                   repair-round max-repair-rounds waves repo-summaries '()
                   (build-pin-drift-repair-tasks drifts preserved repair-round)
                   drifts))))
             ;; Phase 3: All repos quiescent -> global quiescence!
             ((every (lambda (rs) (eq? (.ref rs 'state) 'quiescent)) repo-summaries)
              (make-multi-repo-step
               case-id profile 'quiescent #f repair-round max-repair-rounds
               waves repo-summaries '() '() '()))
             ;; Phase 4: Collect active-wave fenced frames, synthesis repair tasks, or human gates.
             (else
              (let* ((active-entries
                      (filter (lambda (entry)
                                (let* ((r (cadr entry))
                                       (deps (opt-ref r 'depends-on '())))
                                  (and (every (lambda (d) (member d quiescent-ids)) deps)
                                       (not (eq? (.get (cddr entry) state) 'quiescent)))))
                              repo-results))
                     (fenced-frames
                      (append-map
                       (lambda (entry)
                         (let ((rid (car entry))
                               (step (cddr entry)))
                           (if (eq? (.get step state) 'need-fenced-frames)
                             (map (lambda (f) (qualify-frame rid f)) (.get step frames))
                             '())))
                       active-entries))
                     (synth-tasks
                      (append-map
                       (lambda (entry)
                         (let ((rid (car entry))
                               (step (cddr entry)))
                           (if (eq? (.get step state) 'need-agent-synthesis)
                             (map (lambda (t)
                                    (.o (:: @ t) (repo-id := rid)))
                                  (.get step repair-tasks))
                             '())))
                       active-entries))
                     (human-esc
                      (let ((h (find (lambda (e) (eq? (.get (cddr e) state) 'need-human-decision))
                                     active-entries)))
                        (and h (.get (cddr h) escalation-reason)))))
                (cond
                 ((pair? fenced-frames)
                  (make-multi-repo-step
                   case-id profile 'need-fenced-frames #f repair-round max-repair-rounds
                   waves repo-summaries fenced-frames '() '()))
                 ((pair? synth-tasks)
                  (make-multi-repo-step
                   case-id profile 'need-agent-synthesis #f repair-round max-repair-rounds
                   waves repo-summaries '() synth-tasks '()))
                 (else
                  (make-multi-repo-step
                   case-id profile 'need-human-decision human-esc repair-round max-repair-rounds
                   waves repo-summaries '() '() '()))))))))))))
