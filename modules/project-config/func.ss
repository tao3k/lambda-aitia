;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/encoding/json JSONReadOptions string->json)
        (only-in :clan/poo/object .all-slots .call .ref object?)
        (only-in :yuanxu/modules/json-schema/config JsonSchemaScope)
        (only-in :yuanxu/modules/json-schema/json-schema-validate
                 yuanxu-json-schema-object-contract-validation-valid?)
        "types.ss")
(export resolve-project-config decode-project-config project-checks)

;; Both Scheme declarations and decoded JSON pass the same Yuanxu Contract.
(def (resolve-project-config defaults declaration)
  (let* ((artifact (.call JsonSchemaScope compile project-config-schema))
         (validation (.call JsonSchemaScope validate artifact declaration)))
    (and (yuanxu-json-schema-object-contract-validation-valid? validation)
         (let* ((effective (make-hash-table))
                (declared (if (object? declaration)
                            (map (lambda (key) (cons key (.ref declaration key)))
                                 (.all-slots declaration))
                            (hash->list declaration))))
           (for-each (lambda (key) (hash-put! effective key (.ref defaults key)))
                     (.all-slots defaults))
           (for-each (lambda (row) (hash-put! effective (car row) (cdr row))) declared)
           effective))))

(def (decode-project-config defaults source)
  (resolve-project-config defaults
   (string->json source
     (JSONReadOptions key-as-symbol: #t object-as-hash: #t array-as-vector: #t))))

;; Work selection belongs to the declaration owner. The runtime only
;; dispatches the operation identities returned by this projection.
(def (project-checks effective)
  (let* ((services (hash-get effective 'services))
         (sysml (hash-get services 'sysml)))
    (if (and sysml (hash-get sysml 'enable) (hash-get sysml 'parse))
        #("sysml.parse")
        #())))
