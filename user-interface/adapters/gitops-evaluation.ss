;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Opt-in CLOS crossing; the evaluation semantics belong to the admitted Scope.
(import (only-in :clan/poo/object .o .get)
        (only-in :yuanxu/poo-clos/interface
                 poo-clos-generic-protocol poo-clos-method-bundle poo-clos-method
                 poo-clos-class-specializer poo-clos-any-specializer))
(export GitOpsEvaluation)

(def (make-default-methods protocol gitops evaluator-class)
  (let (evaluate (.get gitops evaluate))
    (poo-clos-method-bundle
     'GitOpsDefaultEvaluationMethods protocol
     (list
      (poo-clos-method
       'gitops/default-evaluation
       (list (poo-clos-class-specializer evaluator-class)
             (poo-clos-any-specializer) (poo-clos-any-specializer)
             (poo-clos-any-specializer))
       (lambda (_frame _evaluator composition change checks)
         (evaluate composition change checks)))))))

(def GitOpsEvaluation
  (.o (:: self)
      protocol: (poo-clos-generic-protocol 'gitops/evaluate)
      default-methods: (lambda (gitops evaluator-class)
                         (make-default-methods (.get self protocol) gitops evaluator-class))))
