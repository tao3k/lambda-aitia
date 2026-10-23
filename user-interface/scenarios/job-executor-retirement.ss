;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Synthetic qualification facts, not observations from a production service.
;;; Algorithms and receipt authority stay with Agentic AI Lab's public owners.
(import (only-in :yuanxu/graph/types
                 agentic-ai-lab-graph agentic-ai-lab-graph-node agentic-ai-lab-graph-edge)
        (only-in :agentic-ai-lab/modules/temporal-causality/interface
                 agentic-ai-lab-temporal-observation agentic-ai-lab-causal-event
                 agentic-ai-lab-causal-event-graph))

(export job-retirement-before job-retirement-candidate
        job-retirement-relations job-retirement-events
        job-retirement-event-graph job-retirement-incomplete-event-graph)

(def job-retirement-relations '(PRODUCED_UNDER USES_CAPABILITY VERIFIES))

(def job-retirement-before
  (agentic-ai-lab-graph
   'job-executor/before-retirement
   (map agentic-ai-lab-graph-node
        '(automatic-retry historical-result active-job queued-job
          verify-queued-retry unrelated-export))
   (list
    (agentic-ai-lab-graph-edge 'historical-result 'automatic-retry 'PRODUCED_UNDER)
    (agentic-ai-lab-graph-edge 'active-job 'automatic-retry 'USES_CAPABILITY)
    (agentic-ai-lab-graph-edge 'queued-job 'automatic-retry 'USES_CAPABILITY)
    (agentic-ai-lab-graph-edge 'verify-queued-retry 'queued-job 'VERIFIES))))

;;; Candidate topology only: moving these edges is not a migration receipt.
;;; Historical interpretation still binds job-retirement-before, not this graph.
(def job-retirement-candidate
  (agentic-ai-lab-graph
   'job-executor/candidate-after-retirement
   (map agentic-ai-lab-graph-node
        '(reviewed-recovery historical-result active-job queued-job
          verify-queued-retry unrelated-export))
   (list
    (agentic-ai-lab-graph-edge 'active-job 'reviewed-recovery 'USES_CAPABILITY)
    (agentic-ai-lab-graph-edge 'queued-job 'reviewed-recovery 'USES_CAPABILITY)
    (agentic-ai-lab-graph-edge 'verify-queued-retry 'queued-job 'VERIFIES))))

(def (fixture-event id kind position parents modality committed?)
  (agentic-ai-lab-causal-event
   id "job-executor/retirement-fixture" kind
   (agentic-ai-lab-temporal-observation
    (string-append id "/time") 'logical-version position
    "synthetic-retirement-fixture")
   (string-append id "/payload") parents modality committed?))

(def job-retirement-events
  (list
   (fixture-event "retry-enabled" 'capability-enabled 1 '() 'observed #t)
   (fixture-event "historical-result" 'job-completed 2
                  '("retry-enabled") 'observed #t)
   (fixture-event "job-started" 'job-started 2
                  '("retry-enabled") 'observed #t)
   ;; Current activity is explicitly observed; old creation time cannot infer it.
   (fixture-event "job-still-active" 'job-state-observed 4
                  '("job-started") 'observed #t)
   (fixture-event "retirement-review" 'review-requested 4
                  '("retry-enabled") 'observed #t)
   (fixture-event "queued-retry" 'planned-retry 6
                  '("retry-enabled") 'declared #f)
   (fixture-event "retire-retry" 'proposed-retirement 5
                  '("retirement-review") 'counterfactual #f)
   (fixture-event "later-retry" 'planned-retry 10
                  '("retry-enabled") 'declared #f)
   (fixture-event "unrelated-export" 'export-completed 4 '() 'observed #t)))

(def job-retirement-event-graph
  (agentic-ai-lab-causal-event-graph
   "job-executor/retirement-fixture" job-retirement-events))

(def job-retirement-incomplete-event-graph
  (agentic-ai-lab-causal-event-graph
   "job-executor/retirement-fixture"
   (append job-retirement-events
           (list (fixture-event "external-observation" 'consumer-observed 4
                                '("retry-enabled" "unknown-consumer-origin")
                                'observed #t)))))
