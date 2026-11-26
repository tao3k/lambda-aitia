;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: Pure functional Multi-Repo GitOps wave orchestrator over
;;; Lambda Aitia's 5-state Mixed-Initiative IoC protocol (RFC 0008 / RFC 0009).
;;;
;;; Invariants:
;;;   1. Strict canonical Kahn topological wave ordering (Church-Rosser confluence):
;;;      downstream fenced effects are NEVER emitted until all upstream dependencies
;;;      are quiescent, and permuting concurrent wave peers yields identical steps.
;;;   2. Dependency cycles, unknown upstream repo references, and transitive diamond
;;;      pin conflicts (Bazel Bzlmod / IOHK CHaP coherence) fail closed to
;;;      `need-human-decision` (`dependency-cycle` / `unknown-repo-dependency` /
;;;      `diamond-pin-conflict`).
;;;   3. Two-level bitemporal Early Cutoff (Bazel Skyframe Change Pruning):
;;;      when an upstream commit advances but its exported `interface-digest` is
;;;      unchanged, downstream repos are pruned via `early-cutoffs` and preserve
;;;      their CAS-verified support; only true interface/commit drift emits a
;;;      localized Schwarz `cross-repo-pin-drift` repairTask.
;;;   4. Read-only `HostRead` probes fan out in parallel across all repo
;;;      directories with repo-qualified `receiptKey` (`repo:<id>:<cap>`).
;;;   5. `action-authorized?: #f` at every planning boundary.

(import (only-in :gerbil/core list-sort string->utf8)
        (only-in :std/encoding/json json->string)
        (only-in :tao3k/yuanxu/module-system/feature/source-lock-feature source-lock-payload-digest)
        (only-in :clan/poo/object .o .get .ref .slot? object?)
        (only-in :std/list/list append-map delete-duplicates/hash every filter filter-map find))

(export workflow-plan-multi-repo-step)

(def (sort-strings lst)
  (list-sort string<? lst))

(def (sort-by-repo-id lst)
  (list-sort (lambda (a b) (string<? (.ref a 'repo-id) (.ref b 'repo-id))) lst))

(def (opt-ref obj key default)
  (if (and (object? obj) (.slot? obj key))
    (.ref obj key)
    default))

(def (repo-receipt-key rid cap)
  (string-append "repo:" rid ":" cap))

(def (repo-effective-commit repo-spec raw-receipts)
  (let* ((rid (.ref repo-spec 'repo-id))
         (override-commit (opt-ref repo-spec 'counterfactual-commit #f))
         (apply-rcpt (and (hash-table? raw-receipts)
                          (hash-get raw-receipts (repo-receipt-key rid "gitops.jj.apply-description"))))
         (obs-rcpt (and (hash-table? raw-receipts)
                        (hash-get raw-receipts (repo-receipt-key rid "gitops.jj.observe-cut"))))
         (cut-obj (opt-ref repo-spec 'cut #f)))
    (or override-commit
        (and (hash-table? apply-rcpt) (hash-get apply-rcpt "resulting_commit"))
        (and (hash-table? obs-rcpt)
             (let ((c (hash-get obs-rcpt "cut")))
               (and (hash-table? c) (hash-get c "commit"))))
        (and (object? cut-obj) (.slot? cut-obj 'commit) (.get cut-obj commit))
        (opt-ref repo-spec 'cut-commit #f))))

(def (repo-effective-interface repo-spec raw-receipts)
  (let* ((rid (.ref repo-spec 'repo-id))
         (override-iface (opt-ref repo-spec 'counterfactual-interface #f))
         (iface-rcpt (and (hash-table? raw-receipts)
                          (hash-get raw-receipts (repo-receipt-key rid "interface.project-digest"))))
         (obs-rcpt (and (hash-table? raw-receipts)
                        (hash-get raw-receipts (repo-receipt-key rid "gitops.jj.observe-cut")))))
    (or override-iface
        (and (hash-table? iface-rcpt) (hash-get iface-rcpt "interfaceDigest"))
        (opt-ref repo-spec 'interface-digest #f)
        (and (hash-table? obs-rcpt) (hash-get obs-rcpt "interfaceDigest")))))

;;; Adapton / Salsa / Buck2 DICE content-addressed verification memo key (RFC 0010).
;;; Depends ONLY on repo-id, effective-commit, profile, and the sorted list of
;;; `(upstream-id . upstream-interface-digest)` pairs (falling back to upstream commit
;;; when no interface digest is declared). Unchanged semantic/AST upstream interfaces
;;; yield the exact same SHA-256 verification key across upstream internal commits.
(def (repo-verification-key rid commit-val iface-val profile-val deps iface-map commit-map)
  (let ((profile-str (cond ((string? profile-val) profile-val)
                           ((symbol? profile-val) (symbol->string profile-val))
                           (else "")))
        (up-deps
         (map (lambda (dep-id)
                (let ((iface (let ((p (assoc dep-id iface-map))) (and p (cdr p))))
                      (cm (let ((p (assoc dep-id commit-map))) (and p (cdr p)))))
                  (vector dep-id (or iface cm ""))))
              (sort-strings deps))))
    (source-lock-payload-digest
     (string->utf8
      (json->string
       (vector "lambda-aitia.verification-key.v1"
               rid
               (or commit-val "")
               (or iface-val "")
               profile-str
               (list->vector up-deps)))))))

(def (find-unknown-dependency repos repo-ids)
  (let loop ((rest repos))
    (if (null? rest)
      #f
      (let* ((r (car rest))
             (rid (.ref r 'repo-id))
             (deps (sort-strings (opt-ref r 'depends-on '())))
             (bad (find (lambda (d) (not (member d repo-ids))) deps)))
        (if bad
          (cons rid bad)
          (loop (cdr rest)))))))

;;; Pure canonical Kahn topological wave partitioning.
;;; Returns `(values waves cycle-repos)` where every wave's repo-ids are sorted
;;; lexicographically so concurrent peer permutations yield identical schedules.
(def (compute-repo-waves repos)
  (let ((ordered-repos (sort-by-repo-id repos)))
    (let loop ((remaining ordered-repos) (done '()) (waves '()))
      (if (null? remaining)
        (values (reverse waves) '())
        (let ((ready (filter (lambda (r)
                               (every (lambda (d) (member d done))
                                      (opt-ref r 'depends-on '())))
                             remaining)))
          (if (null? ready)
            (values (reverse waves) (map (lambda (r) (.ref r 'repo-id)) remaining))
            (let* ((wave-ids (sort-strings (map (lambda (r) (.ref r 'repo-id)) ready)))
                   (next-done (append done wave-ids))
                   (next-rem (filter (lambda (r) (not (member (.ref r 'repo-id) wave-ids)))
                                     remaining)))
              (loop next-rem next-done (cons wave-ids waves)))))))))

;;; Compute transitive dependency closure of `start-id` (excluding `start-id` itself).
(def (transitive-deps start-id repo-index)
  (let loop ((queue (let ((r (assoc start-id repo-index)))
                      (if r (opt-ref (cdr r) 'depends-on '()) '())))
             (visited '()))
    (if (null? queue)
      (sort-strings visited)
      (let ((cur (car queue)))
        (if (member cur visited)
          (loop (cdr queue) visited)
          (let* ((entry (assoc cur repo-index))
                 (next-deps (if entry (opt-ref (cdr entry) 'depends-on '()) '())))
            (loop (append (cdr queue) next-deps) (cons cur visited))))))))

;;; Collect canonical pin declarations of a repo as `(upstream-id . canonical-ref)`.
;;; When a repo pins an `interface-digest`, that digest is the compatibility key;
;;; otherwise its `pinned-upstream-commits` entry is used.
(def (repo-canonical-pins repo-spec)
  (let* ((commit-pins (opt-ref repo-spec 'pinned-upstream-commits '()))
         (iface-pins (opt-ref repo-spec 'pinned-upstream-interfaces '()))
         (up-ids (sort-strings
                  (delete-duplicates/hash
                   (append (map car commit-pins) (map car iface-pins))))))
    (map (lambda (up-id)
           (let ((ip (assoc up-id iface-pins))
                 (cp (assoc up-id commit-pins)))
             (cons up-id
                   (if (and ip (string? (cdr ip)))
                     (string-append "iface:" (cdr ip))
                     (string-append "commit:" (cdr cp))))))
         up-ids)))

;;; Transitive Diamond Pin Coherence Law (Bazel Bzlmod / IOHK CHaP).
;;; For each consumer repo `c`, checks whether any two repos in `{c} U ancestors(c)`
;;; pin a shared upstream ancestor `u` to incompatible references. Never silently picks
;;; a winner; returns canonical `diamond-conflict` POO objects with full peer provenance.
(def (detect-diamond-conflicts repos)
  (let* ((ordered-repos (sort-by-repo-id repos))
         (repo-index (map (lambda (r) (cons (.ref r 'repo-id) r)) ordered-repos)))
    (append-map
     (lambda (r)
       (let* ((consumer-id (.ref r 'repo-id))
              (cone-ids (cons consumer-id (transitive-deps consumer-id repo-index)))
              (all-claims
               (append-map
                (lambda (member-id)
                  (let ((entry (assoc member-id repo-index)))
                    (if entry
                      (map (lambda (pin)
                             (list (car pin) member-id (cdr pin)))
                           (repo-canonical-pins (cdr entry)))
                      '())))
                cone-ids))
              (targets (sort-strings (delete-duplicates/hash (map car all-claims)))))
         (append-map
          (lambda (up-id)
            (let* ((claims-for-up
                    (list-sort (lambda (a b) (string<? (cadr a) (cadr b)))
                               (filter (lambda (c) (equal? (car c) up-id)) all-claims)))
                   (distinct-refs (delete-duplicates/hash (map caddr claims-for-up))))
              (if (> (length distinct-refs) 1)
                (list (.o (consumer-repo := consumer-id)
                          (upstream-repo := up-id)
                          (conflicting-pins :=
                           (map (lambda (c) (cons (cadr c) (caddr c))) claims-for-up))))
                '())))
          targets)))
     ordered-repos)))

;;; Two-level bitemporal pin classifier (Bazel Skyframe Early Cutoff / Change Pruning).
;;; Returns `(values drifts early-cutoffs)`:
;;;   - When an upstream commit changed, but downstream pinned an `interface-digest`
;;;     that STILL equals upstream's current `interface-digest`, emit an `early-cutoff`
;;;     and preserve downstream's CAS-cached support.
;;;   - When the commit changed without an unchanged interface pin, or when the
;;;     interface digest itself changed, emit a breaking `pin-drift`.
(def (classify-pin-transitions repos raw-receipts)
  (let* ((ordered-repos (sort-by-repo-id repos))
         (commit-map
          (map (lambda (r) (cons (.ref r 'repo-id) (repo-effective-commit r raw-receipts)))
               ordered-repos))
         (iface-map
          (map (lambda (r) (cons (.ref r 'repo-id) (repo-effective-interface r raw-receipts)))
               ordered-repos)))
    (let loop ((rest ordered-repos) (drifts '()) (cutoffs '()))
      (if (null? rest)
        (values (reverse drifts) (reverse cutoffs))
        (let* ((r (car rest))
               (rid (.ref r 'repo-id))
               (commit-pins (opt-ref r 'pinned-upstream-commits '()))
               (iface-pins (opt-ref r 'pinned-upstream-interfaces '()))
               (up-ids (sort-strings
                        (delete-duplicates/hash
                         (append (map car commit-pins) (map car iface-pins))))))
          (let inner ((ups up-ids) (d-acc drifts) (c-acc cutoffs))
            (if (null? ups)
              (loop (cdr rest) d-acc c-acc)
              (let* ((up-id (car ups))
                     (exp-commit (let ((p (assoc up-id commit-pins))) (and p (cdr p))))
                     (act-commit (let ((p (assoc up-id commit-map))) (and p (cdr p))))
                     (exp-iface (let ((p (assoc up-id iface-pins))) (and p (cdr p))))
                     (act-iface (let ((p (assoc up-id iface-map))) (and p (cdr p))))
                     (commit-changed? (and (string? exp-commit) (string? act-commit)
                                           (not (equal? exp-commit act-commit))))
                     (iface-same? (and (string? exp-iface) (string? act-iface)
                                       (equal? exp-iface act-iface)))
                     (iface-changed? (and (string? exp-iface) (string? act-iface)
                                          (not (equal? exp-iface act-iface)))))
                (cond
                 (iface-changed?
                  (inner (cdr ups)
                         (cons (.o (repo-id := rid)
                                   (upstream-repo := up-id)
                                   (expected-commit := (or exp-commit exp-iface))
                                   (actual-commit := (or act-commit act-iface))
                                   (expected-interface := exp-iface)
                                   (actual-interface := act-iface))
                               d-acc)
                         c-acc))
                 ((and commit-changed? iface-same?)
                  ;; Bazel Skyframe Early Cutoff: upstream commit advanced, interface digest unchanged!
                  (inner (cdr ups)
                         d-acc
                         (cons (.o (repo-id := rid)
                                   (upstream-repo := up-id)
                                   (expected-commit := exp-commit)
                                   (actual-commit := act-commit)
                                   (interface-digest := act-iface)
                                   (reason := 'interface-digest-unchanged))
                               c-acc)))
                 (commit-changed?
                  (inner (cdr ups)
                         (cons (.o (repo-id := rid)
                                   (upstream-repo := up-id)
                                   (expected-commit := exp-commit)
                                   (actual-commit := act-commit)
                                   (expected-interface := exp-iface)
                                   (actual-interface := act-iface))
                               d-acc)
                         c-acc))
                 (else
                  (inner (cdr ups) d-acc c-acc)))))))))))

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
        (python-observe-pytest := (hash-get raw-receipts (repo-receipt-key rid "python.observe-pytest")))
        (jj-prepare-description := (hash-get raw-receipts (repo-receipt-key rid "gitops.jj.prepare-description")))
        (jj-apply-description := (hash-get raw-receipts (repo-receipt-key rid "gitops.jj.apply-description")))
        (jj-push-reviewed := (hash-get raw-receipts (repo-receipt-key rid "gitops.jj.push-reviewed"))))))

;;; Pure functional RFC 0011 Counterfactual Competing-Branch Verification Matrix.
;;; Evaluates EVERY bounded POO branch proposed by investigators or Agents against
;;; the multi-repo diamond coherence laws and attested Adapton/Salsa verification keys,
;;; preserving competing hypotheses, contradictions, and open questions WITHOUT
;;; collapsing to a single favored path or granting execution authority.
(def (apply-counterfactual-overlay repos overrides)
  (map (lambda (r)
         (let* ((rid (.ref r 'repo-id))
                (ov (find (lambda (o) (equal? (.ref o 'repo-id) rid)) overrides)))
           (if (not ov)
             r
             (let ((ov-iface (opt-ref ov 'interface-digest #f))
                   (ov-commit (opt-ref ov 'cut-commit #f))
                   (ov-pins (opt-ref ov 'pinned-upstream-commits #f))
                   (ov-iface-pins (opt-ref ov 'pinned-upstream-interfaces #f))
                   (base-prof (opt-ref r 'profile #f))
                   (base-deps (opt-ref r 'depends-on '()))
                   (base-cut (opt-ref r 'cut #f))
                   (base-cut-commit (opt-ref r 'cut-commit #f))
                   (base-iface (opt-ref r 'interface-digest #f))
                   (base-cf-iface (opt-ref r 'counterfactual-interface #f))
                   (base-cf-commit (opt-ref r 'counterfactual-commit #f))
                   (base-pins (opt-ref r 'pinned-upstream-commits '()))
                   (base-iface-pins (opt-ref r 'pinned-upstream-interfaces '())))
               (.o (repo-id := rid)
                   (profile := base-prof)
                   (depends-on := base-deps)
                   (cut := base-cut)
                   (cut-commit := base-cut-commit)
                   (interface-digest := base-iface)
                   (counterfactual-interface := (or ov-iface base-cf-iface))
                   (counterfactual-commit := (or ov-commit base-cf-commit))
                   (pinned-upstream-commits := (or ov-pins base-pins))
                   (pinned-upstream-interfaces := (or ov-iface-pins base-iface-pins)))))))
       repos))

(def (evaluate-counterfactual-branch branch repos raw-receipts attested-keys default-profile)
  (let* ((bid (opt-ref branch 'branch-id "branch-unnamed"))
         (hyp (opt-ref branch 'hypothesis ""))
         (overrides (opt-ref branch 'repo-overrides '()))
         (b-repos (apply-counterfactual-overlay repos overrides))
         (b-conflicts (detect-diamond-conflicts b-repos)))
    (let-values (((b-drifts b-cutoffs) (classify-pin-transitions b-repos raw-receipts)))
      (let* ((drifted-ids (map (lambda (d) (.ref d 'repo-id)) b-drifts))
             (commit-map (map (lambda (r) (cons (.ref r 'repo-id) (repo-effective-commit r raw-receipts))) b-repos))
             (iface-map (map (lambda (r) (cons (.ref r 'repo-id) (repo-effective-interface r raw-receipts))) b-repos))
             (repo-evals
              (map (lambda (r)
                     (let* ((rid (.ref r 'repo-id))
                            (deps (sort-strings (opt-ref r 'depends-on '())))
                            (r-prof (opt-ref r 'profile default-profile))
                            (eff-commit (repo-effective-commit r raw-receipts))
                            (eff-iface (repo-effective-interface r raw-receipts))
                            (vkey (repo-verification-key rid eff-commit eff-iface r-prof deps iface-map commit-map))
                            (attested-key (and (hash-table? attested-keys) (hash-get attested-keys rid)))
                            (hit? (and (string? attested-key)
                                       (equal? attested-key vkey)
                                       (not (member rid drifted-ids)))))
                       (list rid vkey hit?)))
                   b-repos))
             (cache-hits
              (filter-map (lambda (e)
                            (and (caddr e)
                                 (.o (repo-id := (car e)) (verification-key := (cadr e)))))
                          repo-evals))
             (invalidated
              (filter-map (lambda (e) (and (not (caddr e)) (car e))) repo-evals))
             (res-state
              (cond
               ((pair? b-conflicts) 'need-human-decision)
               ((pair? b-drifts) 'need-agent-synthesis)
               (else 'quiescent)))
             (res-esc
              (cond
               ((pair? b-conflicts) 'diamond-pin-conflict)
               ((pair? b-drifts) 'cross-repo-pin-drift)
               (else #f)))
             (contradictions
              (append
               (map (lambda (c)
                      (string-append "diamond-pin-conflict:" (.ref c 'consumer-repo) "<-" (.ref c 'upstream-repo)))
                    b-conflicts)
               (map (lambda (d)
                      (string-append "cross-repo-pin-drift:" (.ref d 'repo-id) "<-" (.ref d 'upstream-repo)))
                    b-drifts)))
             (open-questions
              (append
               (map (lambda (rid) (string-append "reverify-repo:" rid)) invalidated)
               (if (pair? b-conflicts)
                 (list "human-decision-required:diamond-pin-conflict")
                 '()))))
        (.o (branch-id := bid)
            (hypothesis := hyp)
            (hypothetical? := #t)
            (action-authorized? := #f)
            (resulting-state := res-state)
            (escalation-reason := res-esc)
            (pin-drifts := b-drifts)
            (diamond-conflicts := b-conflicts)
            (early-cutoffs := b-cutoffs)
            (verification-cache-hits := cache-hits)
            (invalidated-repos := invalidated)
            (contradictions := contradictions)
            (open-questions := open-questions))))))

(def (evaluate-counterfactual-branches branches repos raw-receipts attested-keys default-profile)
  (map (lambda (b)
         (evaluate-counterfactual-branch b repos raw-receipts attested-keys default-profile))
       branches))

(def (make-multi-repo-step
      case-id profile state escalation-reason repair-round max-repair-rounds
      waves repo-summaries frames repair-tasks drifts early-cutoffs diamond-conflicts
      (counterfactual-matrix '()))
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
                                  (world-count := (if (pair? diamond-conflicts)
                                                    (max 2 (length diamond-conflicts))
                                                    1))
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
        (early-cutoffs := early-cutoffs)
        (diamond-conflicts := diamond-conflicts)
        (verification-cache-hits :=
         (filter-map (lambda (rs)
                       (and (.slot? rs 'cache-hit?) (.ref rs 'cache-hit?)
                            (.o (repo-id := (.ref rs 'repo-id))
                                (verification-key := (.ref rs 'verification-key)))))
                     repo-summaries))
        (counterfactual-matrix := counterfactual-matrix)
        (graph := #f)
        (initial-frontier := #f)
        (report := #f)
        (final-frontier := #f)
        (proposal-admission := #f)
        (action-authorized? := #f))))

(def (workflow-plan-multi-repo-step ctx single-repo-planner)
  (let* ((case-id (opt-ref ctx 'case-id 'aitia/case/multi-repo-gitops))
         (profile (opt-ref ctx 'profile "lambda-aitia/sdlc"))
         (repos (sort-by-repo-id (opt-ref ctx 'repos '())))
         (raw-receipts (opt-ref ctx 'raw-receipts (hash)))
         (attested-keys (opt-ref ctx 'attested-verification-keys (hash)))
         (cf-branches (opt-ref ctx 'counterfactual-branches '()))
         (repair-round (opt-ref ctx 'repair-round 0))
         (max-repair-rounds (opt-ref ctx 'max-repair-rounds 3))
         (repo-ids (map (lambda (r) (.ref r 'repo-id)) repos))
         (unknown-dep (find-unknown-dependency repos repo-ids)))
    (if unknown-dep
      (make-multi-repo-step
       case-id profile 'need-human-decision 'unknown-repo-dependency
       repair-round max-repair-rounds '() '() '() '() '() '() '())
      (let-values (((waves cycle-repos) (compute-repo-waves repos)))
        (if (pair? cycle-repos)
          (make-multi-repo-step
           case-id profile 'need-human-decision 'dependency-cycle
           repair-round max-repair-rounds waves '() '() '() '() '() '())
          (let ((diamond-conflicts (detect-diamond-conflicts repos)))
            (if (pair? diamond-conflicts)
              (make-multi-repo-step
               case-id profile 'need-human-decision 'diamond-pin-conflict
               repair-round max-repair-rounds waves '() '() '() '() '() diamond-conflicts)
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
                                                 (python-check := (opt-ref r 'python-check #f))
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
                      (append
                       (append-map
                        (lambda (entry)
                          (let ((rid (car entry))
                                (step (cddr entry)))
                            (if (eq? (.get step state) 'need-host-frames)
                              (map (lambda (f) (qualify-frame rid f)) (.get step frames))
                              '())))
                        repo-results)
                       (append-map
                        (lambda (r)
                          (let* ((rid (.ref r 'repo-id))
                                 (iface-paths (opt-ref r 'interface-paths '()))
                                 (rkey (repo-receipt-key rid "interface.project-digest"))
                                 (has-rcpt? (and (hash-table? raw-receipts)
                                                 (hash-get raw-receipts rkey))))
                            (if (and (pair? iface-paths) (not has-rcpt?))
                              (list (.o (capability := "interface.project-digest")
                                        (effect-class := 'host-read)
                                        (receipt-key := rkey)
                                        (repo-id := rid)
                                        (fence-token := #f)
                                        (payload := (.o (directory := (opt-ref r 'directory "."))
                                                        (interface-paths := (sort-strings iface-paths))))))
                              '())))
                        repos))))
                (let-values (((drifts early-cutoffs) (classify-pin-transitions repos raw-receipts)))
                  (let* ((drifted-ids (map (lambda (d) (.ref d 'repo-id)) drifts))
                         (cutoff-ids (map (lambda (c) (.ref c 'repo-id)) early-cutoffs))
                         (commit-map
                          (map (lambda (r) (cons (.ref r 'repo-id) (repo-effective-commit r raw-receipts)))
                               repos))
                         (iface-map
                          (map (lambda (r) (cons (.ref r 'repo-id) (repo-effective-interface r raw-receipts)))
                               repos))
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
                                        (deps (sort-strings (opt-ref r 'depends-on '())))
                                        (deps-ready? (every (lambda (d) (member d quiescent-ids)) deps))
                                        (drifted? (member rid drifted-ids))
                                        (eff-commit (repo-effective-commit r raw-receipts))
                                        (eff-iface (repo-effective-interface r raw-receipts))
                                        (vkey (repo-verification-key
                                               rid eff-commit eff-iface (.get step profile)
                                               deps iface-map commit-map))
                                        (attested-key (and (hash-table? attested-keys)
                                                           (hash-get attested-keys rid)))
                                        (cache-hit-val (and (string? attested-key)
                                                            (equal? attested-key vkey)
                                                            (not drifted?)))
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
                                       (effective-commit := eff-commit)
                                       (interface-digest := eff-iface)
                                       (verification-key := vkey)
                                       (cache-hit? := cache-hit-val)
                                       (state := eff-state)
                                       (upstream-ready? := deps-ready?)
                                       (pin-drifted? := (and drifted? #t))
                                       (early-cutoff? := (and (member rid cutoff-ids) #t))
                                       (applied-receipt := (.get step applied-receipt))
                                       (pushed-receipt := (.get step pushed-receipt)))))
                               repo-results)))
                    (let ((cf-matrix
                           (if (pair? cf-branches)
                             (evaluate-counterfactual-branches
                              cf-branches repos raw-receipts attested-keys profile)
                             '())))
                    (cond
                     ;; Phase 1: Fan out all read-only HostRead probes across all repos in parallel.
                     ((pair? host-frames)
                      (make-multi-repo-step
                       case-id profile 'need-host-frames #f repair-round max-repair-rounds
                       waves repo-summaries host-frames '() drifts early-cutoffs '() cf-matrix))
                     ;; Phase 2: Breaking pin drift -> localized Schwarz repair (or human escalation).
                     ((pair? drifts)
                      (let ((preserved (filter (lambda (id) (not (member id drifted-ids))) repo-ids)))
                        (if (>= repair-round max-repair-rounds)
                          (make-multi-repo-step
                           case-id profile 'need-human-decision 'repair-budget-exhausted
                           repair-round max-repair-rounds waves repo-summaries '() '() drifts early-cutoffs '() cf-matrix)
                          (make-multi-repo-step
                           case-id profile 'need-agent-synthesis 'cross-repo-pin-drift
                           repair-round max-repair-rounds waves repo-summaries '()
                           (build-pin-drift-repair-tasks drifts preserved repair-round)
                           drifts early-cutoffs '() cf-matrix))))
                     ;; Phase 3: All repos quiescent -> global quiescence (retaining Early Cutoff audit proof!).
                     ((every (lambda (rs) (eq? (.ref rs 'state) 'quiescent)) repo-summaries)
                      (make-multi-repo-step
                       case-id profile 'quiescent #f repair-round max-repair-rounds
                       waves repo-summaries '() '() '() early-cutoffs '() cf-matrix))
                     ;; Phase 4: Active-wave fenced frames, synthesis repair tasks, or human gates.
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
                           waves repo-summaries fenced-frames '() '() early-cutoffs '() cf-matrix))
                         ((pair? synth-tasks)
                          (make-multi-repo-step
                           case-id profile 'need-agent-synthesis #f repair-round max-repair-rounds
                           waves repo-summaries '() synth-tasks '() early-cutoffs '() cf-matrix))
                         (else
                          (make-multi-repo-step
                           case-id profile 'need-human-decision human-esc repair-round max-repair-rounds
                           waves repo-summaries '() '() '() early-cutoffs '() cf-matrix)))))))))))))))))
