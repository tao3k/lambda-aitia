;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/encoding/json JSONReadOptions string->json)
        (only-in :clan/poo/object .all-slots .call .ref object? object<-alist)
        (only-in :tao3k/yuanxu/configuration/json config-defaults)
        (only-in :tao3k/yuanxu/modules/json-schema/config JsonSchemaScope)
        (only-in :tao3k/yuanxu/modules/json-schema/json-schema-validate
                 yuanxu-json-schema-object-contract-validation-valid?)
        "types.ss")
(export resolve-project-config decode-project-config extend-project-config project-checks project-commit-settings)

;; Higher-order Scheme configuration evaluates to POO values. The transport
;; projection recursively lowers those values; JSON does not own policy.
(def (config-value value)
  (cond
   ((object? value)
    (list->hash-table
     (map (lambda (key) (cons key (config-value (.ref value key)))) (.all-slots value))))
   ((hash-table? value)
    (list->hash-table (map (lambda (row) (cons (car row) (config-value (cdr row))))
                          (hash->list value))))
   ((vector? value) (list->vector (map config-value (vector->list value))))
   ((list? value) (list->vector (map config-value value)))
   (else value)))

;; The Module owns one immutable schema. Compile its Contract on first use;
;; each declaration still gets a separate validation and effective value.
(def project-config-contract
  (delay (.call JsonSchemaScope compile project-config-schema)))

;; Both Scheme declarations and decoded JSON pass the same Yuanxu Contract.
(def (resolve-project-config defaults declaration)
  (let* ((declared-value (config-value declaration))
         (artifact (force project-config-contract))
         (validation (.call JsonSchemaScope validate artifact declared-value)))
    (and (yuanxu-json-schema-object-contract-validation-valid? validation)
         (let* ((effective (make-hash-table))
                (declared (hash->list declared-value)))
           (for-each (lambda (key) (hash-put! effective key (config-value (.ref defaults key))))
                     (.all-slots defaults))
           (for-each (lambda (row) (hash-put! effective (car row) (cdr row))) declared)
           effective))))

(def (parse-project-json source)
  (string->json source
    (JSONReadOptions key-as-symbol: #t object-as-hash: #t array-as-vector: #t)))

(def (decode-project-config defaults source)
  (resolve-project-config defaults (parse-project-json source)))

;; Keep arrays and explicit scalar values intact when converting JSON objects
;; to POO data. Yuanxu owns recursive inheritance of omitted object slots.
(def (json-config-object value)
  (if (hash-table? value)
    (object<-alist (map (lambda (row)
                          (cons (car row) (json-config-object (cdr row))))
                        (hash->list value)))
    value))

(def (extend-project-config defaults declaration source)
  (let (overlay (parse-project-json source))
    (and (object? declaration) (hash-table? overlay)
         (resolve-project-config defaults
           (config-defaults declaration (json-config-object overlay))))))

;; Work selection belongs to the declaration owner. The runtime only
;; dispatches the operation identities returned by this projection.
(def (project-checks effective)
  (let* ((services (hash-get effective 'services))
         (sysml (hash-get services 'sysml))
         (assurance (hash-get services 'assurance)))
    (list->vector
     (append
      (if (and sysml (hash-get sysml 'enable) (hash-get sysml 'parse))
          '("sysml.parse") '())
      (if (and assurance (hash-get assurance 'enable))
          '("assurance.replay") '())))))

;; Program policy is distinct from long-running service selection.
(def (project-commit-settings effective)
  (let* ((programs (hash-get effective 'programs))
         (jj (and programs (hash-get programs 'jj))))
    (and jj (hash-get jj 'enable) (hash-ref jj 'settings))))
