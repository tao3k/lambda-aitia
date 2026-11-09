;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .cc)
        (only-in :clan/poo/mop Any Function)
        (only-in :clan/poo/type Record String))
(export ProjectConfigScopeContract project-config-schema)

(def ProjectConfigScopeContract
  (.cc (Record resolve: [(Function (list Any) (list Any))]
               decode: [(Function (list Any) (list String))]
               checks: [(Function (list Any) (list Any))])
       identity: 'project-config/scope))

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
         ((assurance .
           ((type . "object")
            (additionalProperties . #f)
            (required . ("enable" "project" "profile"))
            (properties . ((enable . ((type . "boolean")))
                           (project . ((type . "string") (minLength . 1)))
                           (profile . ((enum . ("adr-0008"))))))))
          (commit .
           ((type . "object")
            (additionalProperties . #f)
            (required . ("project" "profile" "primary" "checks"))
            (properties . ((project . ((type . "string") (minLength . 1)))
                           (profile . ((enum . ("nasa/sdlc/npr-7150.2"))))
                           (primary . ((type . "string") (minLength . 1)))
                           (governance . ((enum . ("signed"))))
                           (checks . ((type . "array") (minItems . 1)
                                      (items . ((type . "object")
                                                (additionalProperties . #f)
                                                (required . ("requirement" "method"))
                                                (properties . ((requirement . ((type . "string") (minLength . 1)))
                                                               (method . ((type . "string") (minLength . 1)))))))))))))
          (sysml .
           ((type . "object")
            (additionalProperties . #f)
            (required . ("enable" "parse"))
            (properties . ((enable . ((type . "boolean")))
                           (parse . ((type . "boolean")))))))))))))))
