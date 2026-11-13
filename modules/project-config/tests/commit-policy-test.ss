;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/misc/ports read-file-string)
        (only-in :clan/poo/object .get .o .cc)
        (only-in "../config.ss" Config))
(export commit-policy-test)

(def commit-policy-test
  (test-suite "Commit configuration value projection"
    (test-case "POO declarations normalize through the same Contract as project JSON"
      (let* ((configured-settings
              (.o project: "example" profile: "nasa/sdlc/npr-7150.2" primary: "SWE-084"
                  checks: (list (.o requirement: "SWE-084" method: "jj.configuration-audit"))
                  naming: (.o self: self projectKey: "EXAMPLE" primaryLanguage: "en"
                              (languageSources
                               (if (equal? (.get self primaryLanguage) "en")
                                   '("README.org") '("README.fr.org")))
                              types: '("feat" "fix")
                              scopes: (list (.o name: "gitops" paths: '("modules/gitops")))
                              references: (list (.o identity: "RFC-7" source: "design.org" element: "work")))))
             (configured-program (.o enable: #t settings: configured-settings))
             (declaration (.o schemaVersion: 1
                              programs: (.o jj: configured-program)
                              services: (.o sysml: (.o enable: #t parse: #t))))
             (extend (.get Config extend))
             (configure (.get Config resolve))
             (decode (.get Config decode))
             (select (.get Config commit))
             (configured (select (configure declaration))))
        (let* ((effective (extend declaration
                           "{\"programs\":{\"jj\":{\"settings\":{\"naming\":{\"types\":[\"perf\"]}}}},\"services\":{\"sysml\":{\"enable\":false}}}"))
               (settings (select effective))
               (naming (hash-ref settings 'naming)))
          (check-equal? (hash-ref settings 'project) "example")
          (check-equal? (hash-ref naming 'types) #("perf"))
          (check-equal? (hash-ref naming 'languageSources) #("README.org"))
          (check-equal? ((.get Config checks) effective) #()))
        (let* ((effective (extend declaration
                          "{\"programs\":{\"jj\":{\"settings\":{\"naming\":{\"primaryLanguage\":\"fr\"}}}}}"))
               (naming (hash-ref (select effective) 'naming)))
          (check-equal? (hash-ref naming 'languageSources) #("README.fr.org")))
        (check-equal? (select (extend declaration "{\"programs\":{\"jj\":{\"enable\":false}}}")) #f)
        (for-each (lambda (source) (check-equal? (extend declaration source) #f))
          '("[]" "{\"schemaVersion\":2}" "{\"services\":{\"sysml\":null}}"
            "{\"programs\":{\"jj\":{\"settings\":{\"naming\":{\"types\":[]}}}}}"
            "{\"programs\":{\"jj\":{\"settings\":{\"pullRequest\":2}}}}"))

        (check-equal? (hash-ref configured 'project) "example")
        (check-equal? (hash-ref (hash-ref configured 'naming) 'projectKey) "EXAMPLE")
        (check-equal? (hash-ref (select (decode (read-file-string ".agents/aita/project.json"))) 'primary)
                      "SWE-084")
        (check-equal? (select (configure (.o schemaVersion: 1 programs:
                                              (.o jj: (.cc configured-program enable: #f))))) #f)
        (check-equal? (select (decode "{\"schemaVersion\":1}")) #f)
        (check-equal? (decode "{\"schemaVersion\":1,\"services\":{\"commit\":{}}}") #f)
        (check-equal? (configure (.o schemaVersion: 1 programs: (.o jj:
                                       (.o enable: #t settings: (.cc configured-settings naming: (.o)))))) #f)))))
