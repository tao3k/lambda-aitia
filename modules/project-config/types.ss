;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .all-slots .cc .get .o .ref)
        (only-in :clan/poo/type Any Function Record String))
(export ProjectConfigScopeContract project-config-schema)

(def ProjectConfigScopeContract
  (.cc (Record resolve: [(Function (list Any) (list Any))]
               decode: [(Function (list Any) (list String))]
               extend: [(Function (list Any) (list Any String))]
               checks: [(Function (list Any) (list Any))]
               commit: [(Function (list Any) (list Any))])
       identity: 'project-config/scope))

;; Project POO schema descriptors onto the JsonSchemaScope wire contract so the
;; schema stays value-first without hand-authored nested dotted alists.
(def (poo-properties->alist properties)
  (map (lambda (slot) (cons slot (.ref properties slot)))
       (.all-slots properties)))

(def (schema-string) '((type . "string") (minLength . 1)))
(def (schema-boolean) '((type . "boolean")))
(def (schema-enum values) `((enum . ,values)))
(def (schema-array item)
  `((type . "array") (minItems . 1) (items . ,item)))
(def (schema-object required properties)
  `((type . "object")
    (additionalProperties . #f)
    (required . ,required)
    (properties . ,(poo-properties->alist properties))))

(def commit-scope-schema
  (schema-object '("name" "paths")
    (.o name: (schema-string)
        paths: (schema-array (schema-string)))))

(def commit-reference-schema
  (schema-object '("identity" "source" "element")
    (.o identity: (schema-string)
        source: (schema-string)
        element: (schema-string))))

(def commit-naming-schema
  (schema-object '("projectKey" "types" "references" "languageSources")
    (.o projectKey: (schema-string)
        primaryLanguage: (schema-string)
        languageSources: (schema-array (schema-string))
        types: (schema-array (schema-string))
        scopes: (schema-array commit-scope-schema)
        references: (schema-array commit-reference-schema))))

(def commit-check-schema
  (schema-object '("requirement" "method")
    (.o requirement: (schema-string)
        method: (schema-string))))

(def commit-settings-schema
  (schema-object '("project" "profile" "primary" "checks" "naming")
    (.o project: (schema-string)
        profile: (schema-enum '("nasa/sdlc/npr-7150.2"))
        primary: (schema-string)
        governance: (schema-enum '("signed"))
        naming: commit-naming-schema
        checks: (schema-array commit-check-schema))))

(def replay-case-schema
  (schema-object '("obligation" "selector" "expected")
    (.o obligation: (schema-string)
        selector: (schema-string)
        expected: (schema-enum '("passed" "failed")))))

(def assurance-service-schema
  (schema-object '("enable" "project" "profile")
    (.o enable: (schema-boolean)
        project: (schema-string)
        profile: (schema-enum '("adr-0008"))
        paths: (schema-array (schema-string))
        cases: (schema-array replay-case-schema))))

(def sysml-service-schema
  (schema-object '("enable" "parse")
    (.o enable: (schema-boolean)
        parse: (schema-boolean))))

(def project-config-schema
  (schema-object '("schemaVersion")
    (.o schemaVersion: (schema-enum '(1))
        programs: (schema-object '()
                    (.o jj: (schema-object '("enable" "settings")
                              (.o enable: (schema-boolean)
                                  settings: commit-settings-schema))))
        services: (schema-object '()
                    (.o assurance: assurance-service-schema
                        sysml: sysml-service-schema)))))
