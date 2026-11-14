;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; NPR 7150.2D project/institution baseline policy construction.
(import (only-in :clan/poo/mop validate)
        (only-in :clan/poo/object .get .o .ref)
        "../types.ss"
        "nasa-7150-2d.ss"
        :std/list/list)

(export nasa-stage-policy nasa-baseline-policy)

(def (nasa-stage-policy id requirements-value scope: (scope-value 'project))
  (let (result
        (validate
         SdlcStagePolicy
         (.o (:: @ (.ref SdlcStagePolicy 'proto))
             identity: id assessment-scope: scope-value
             requirements: requirements-value)))
    (when (equal? id "unstarted")
      (error "reserved lifecycle stage"))
    (for-each
     (lambda (requirement-id)
       (nasa-requirement-by-id requirement-id)
       (unless (eq? (eq? (nasa-rule-mode requirement-id) 'institutional)
                    (eq? scope-value 'institution))
         (error "NASA stage mixes project and institutional duties"
                requirement-id)))
     requirements-value)
    result))

(def (nasa-baseline-policy id scope: (scope-value 'project))
  (nasa-stage-policy
   id
   (map (lambda (row) (.ref row 'identity))
        (filter
         (lambda (row)
           (eq? (eq? (nasa-rule-mode (.ref row 'identity)) 'institutional)
                (eq? scope-value 'institution)))
         (.get Nasa7150_2D requirements)))
   scope: scope-value))
