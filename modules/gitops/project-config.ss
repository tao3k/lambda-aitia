;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/encoding/json JSONReadOptions string->json)
        (only-in :clan/poo/object .all-slots .call .o .ref object?)
        (only-in :yuanxu/modules/json-schema/config JsonSchemaScope)
        (only-in :yuanxu/modules/json-schema/json-schema-validate
                 yuanxu-json-schema-object-contract-validation-valid?))
(export gitops-project-config gitops-project-config-json)

(def project-config-schema
  '((type . "object")
    (additionalProperties . #f)
    (required . ("schemaVersion"))
    (properties .
     ((schemaVersion . ((enum . (1))))
      (services .
       ((type . "object")
        (additionalProperties . #f)
        (properties .
         ((sysml .
           ((type . "object")
            (additionalProperties . #f)
            (required . ("enable" "parse"))
            (properties . ((enable . ((type . "boolean")))
                           (parse . ((type . "boolean")))))))))))))))

(def (project-config-defaults)
  (.o services: (hash)))

;; Both Scheme declarations and decoded JSON pass the same Yuanxu Contract.
(def (gitops-project-config declaration)
  (let* ((artifact (.call JsonSchemaScope compile project-config-schema))
         (validation (.call JsonSchemaScope validate artifact declaration)))
    (and (yuanxu-json-schema-object-contract-validation-valid? validation)
         (let* ((defaults (project-config-defaults))
                (effective (make-hash-table))
                (declared (if (object? declaration)
                            (map (lambda (key) (cons key (.ref declaration key)))
                                 (.all-slots declaration))
                            (hash->list declaration))))
           (for-each (lambda (key) (hash-put! effective key (.ref defaults key)))
                     (.all-slots defaults))
           (for-each (lambda (row) (hash-put! effective (car row) (cdr row))) declared)
           effective))))

(def (gitops-project-config-json source)
  (gitops-project-config
   (string->json source
     (JSONReadOptions key-as-symbol: #t object-as-hash: #t array-as-vector: #t))))
