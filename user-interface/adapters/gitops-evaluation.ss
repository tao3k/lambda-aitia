;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Opt-in CLOS crossing; the evaluation semantics belong to the admitted Scope.
(import (only-in :clan/poo/object .o .get)
        (only-in :clan/poo/mop
                 clos-generic-protocol clos-method-bundle clos-method
                 clos-class-specializer clos-any-specializer))
(export GitOpsEvaluation)

(def (make-default-methods protocol gitops evaluator-class)
  (let (evaluate (.get gitops evaluate))
    (clos-method-bundle
     'GitOpsDefaultEvaluationMethods protocol
     (list
      (clos-method
       'gitops/default-evaluation
       (list (clos-class-specializer evaluator-class)
             (clos-any-specializer) (clos-any-specializer)
             (clos-any-specializer))
       (lambda (_frame _evaluator composition change checks)
         (evaluate composition change checks)))))))

(def GitOpsEvaluation
  (.o (:: self)
      protocol: (clos-generic-protocol 'gitops/evaluate)
      default-methods: (lambda (gitops evaluator-class)
                         (make-default-methods (.get self protocol) gitops evaluator-class))))
