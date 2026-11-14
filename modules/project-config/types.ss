;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .cc)
        (only-in :clan/poo/mop Any Function)
        (only-in :clan/poo/type Record String))
(export ProjectConfigScopeContract project-config-schema)

(def ProjectConfigScopeContract
  (.cc (Record resolve: [(Function (list Any) (list Any))]
               decode: [(Function (list Any) (list String))]
               extend: [(Function (list Any) (list Any String))]
               checks: [(Function (list Any) (list Any))]
               commit: [(Function (list Any) (list Any))])
       identity: 'project-config/scope))

(def config-string '((type . "string") (minLength . 1)))
(def (config-array item)
  `((type . "array") (minItems . 1) (items . ,item)))
(def (config-object required properties)
  `((type . "object") (additionalProperties . #f)
    (required . ,required) (properties . ,properties)))

(def commit-naming-schema
  (config-object '("projectKey" "types" "scopes" "references" "languageSources")
   `((projectKey . ,config-string)
     (primaryLanguage . ,config-string)
     (languageSources . ,(config-array config-string))
     (types . ,(config-array config-string))
     (scopes . ,(config-array
                 (config-object '("name" "paths")
                  `((name . ,config-string) (paths . ,(config-array config-string))))))
     (references . ,(config-array
                     (config-object '("identity" "source" "element")
                      `((identity . ,config-string) (source . ,config-string)
                        (element . ,config-string))))))))

(def commit-settings-schema
  (config-object '("project" "profile" "primary" "checks" "naming")
   `((project . ,config-string)
     (profile . ((enum . ("nasa/sdlc/npr-7150.2"))))
     (primary . ,config-string)
     (governance . ((enum . ("signed"))))
     (naming . ,commit-naming-schema)
     (checks . ,(config-array
                 (config-object '("requirement" "method")
                  `((requirement . ,config-string) (method . ,config-string))))))))

(def project-config-schema
  (config-object '("schemaVersion")
   `((schemaVersion . ((enum . (1))))
     (programs . ,(config-object '()
                   `((jj . ,(config-object '("enable" "settings")
                             `((enable . ((type . "boolean")))
                               (settings . ,commit-settings-schema)))))))
     (services . ,(config-object '()
                   `((assurance . ,(config-object '("enable" "project" "profile")
                                    `((enable . ((type . "boolean")))
                                      (project . ,config-string)
                                      (profile . ((enum . ("adr-0008")))))))
                     (sysml . ,(config-object '("enable" "parse")
                                '((enable . ((type . "boolean")))
                                  (parse . ((type . "boolean"))))))))))))
