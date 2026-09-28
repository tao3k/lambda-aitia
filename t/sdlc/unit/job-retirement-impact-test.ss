;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :clan/poo/object .ref)
        (only-in :poo-flow/src/graph/types poo-flow-graph-id)
        (only-in :poo-flow/src/modules/temporal-causality/interface
                 poo-flow-structural-impact-analyze
                 poo-flow-causal-cut poo-flow-temporal-causal-classify)
        :poo-flow/lambda-aitia/user-interface/scenarios/job-executor-retirement)

(export job-retirement-impact-test)

(def (impact graph (complete? #t))
  (poo-flow-structural-impact-analyze
   graph '(automatic-retry) job-retirement-relations 'dependents complete?))

(def (classify graph)
  (poo-flow-temporal-causal-classify
   graph (poo-flow-causal-cut graph 4) "retry-enabled" 7))

(def job-retirement-impact-test
  (test-suite "Job-executor retirement Impact qualification"
    (test-case "old dependents survive analysis of a proposed removal"
      (let* ((receipt (impact job-retirement-before))
             (affected (.ref receipt 'affected-node-ids))
             (witness
              (car (filter (lambda (value)
                             (eq? (.ref value 'target-node-id) 'verify-queued-retry))
                           (.ref receipt 'relation-trajectories)))))
        (check (length affected) => 5)
        (for-each (lambda (id) (check (if (memq id affected) #t #f) => #t))
                  '(automatic-retry historical-result active-job queued-job
                    verify-queued-retry))
        (check (memq 'unrelated-export affected) => #f)
        (check (.ref witness 'node-path)
               => '(automatic-retry queued-job verify-queued-retry))
        (check (.ref witness 'relation-path) => '(USES_CAPABILITY VERIFIES))
        (check (.ref receipt 'release-authorized?) => #f)
        (check (.ref receipt 'runtime-executed?) => #f)))
    (test-case "candidate graph cannot turn missing retired identity into no impact"
      (let (before (impact job-retirement-before))
        (check-exception (impact job-retirement-candidate) true)
        (check (poo-flow-graph-id job-retirement-before)
               => 'job-executor/before-retirement)
        (check (.ref (impact job-retirement-before) 'affected-node-ids)
               => (.ref before 'affected-node-ids))))
    (test-case "unknown external inventory prevents scoped completeness"
      (let (receipt (impact job-retirement-before #f))
        (check (.ref receipt 'status) => 'partial-impact)
        (check (.ref receipt 'release-authorized?) => #f)))
    (test-case "past occurrence and current activity remain separate facts"
      (let* ((cut (poo-flow-causal-cut job-retirement-event-graph 4))
             (receipt (classify job-retirement-event-graph)))
        (check (.ref receipt 'past-event-ids)
               => '("retry-enabled" "historical-result" "job-started"))
        (check (.ref receipt 'current-event-ids)
               => '("job-still-active" "retirement-review"))
        (check (.ref receipt 'future-event-ids) => '("queued-retry"))
        (check (.ref receipt 'counterfactual-event-ids) => '("retire-retry"))
        (check (.ref receipt 'outside-horizon-event-ids) => '("later-retry"))
        (check (.ref receipt 'hypothesized-event-ids) => '())
        (check (member "retire-retry"
                       (map (lambda (event) (.ref event 'identity))
                            (.ref cut 'events))) => #f)
        (check (.ref receipt 'assurance-closed?) => #f)
        (check (.ref receipt 'runtime-executed?) => #f)))
    (test-case "later review does not rewrite the earlier historical cut"
      (let* ((old (poo-flow-causal-cut job-retirement-event-graph 2))
             (current (poo-flow-causal-cut job-retirement-event-graph 4))
             (old-events (.ref old 'events))
             (historical (cadr old-events)))
        (check (map (lambda (event) (.ref event 'identity)) old-events)
               => '("retry-enabled" "historical-result" "job-started"))
        (check (.ref historical 'payload-identity) => "historical-result/payload")
        (check (.ref historical 'modality) => 'observed)
        (check (.ref historical 'committed?) => #t)
        (check (if (memq historical (.ref current 'events)) #t #f) => #t)
        (check (map (lambda (event) (.ref event 'identity)) (.ref old 'events))
               => '("retry-enabled" "historical-result" "job-started"))))
    (test-case "a missing causal parent remains an unknown frontier"
      (let (receipt (classify job-retirement-incomplete-event-graph))
        (check (.ref receipt 'status) => 'partial-temporal-classification)
        (check (.ref receipt 'unknown-frontier) => '("unknown-consumer-origin"))
        (check (.ref receipt 'release-authorized?) => #f)))
    (test-case "a proposal cannot be promoted to the observed change trigger"
      (check-exception
       (poo-flow-temporal-causal-classify
        job-retirement-event-graph (poo-flow-causal-cut job-retirement-event-graph 4)
        "retire-retry" 7)
       true))))
