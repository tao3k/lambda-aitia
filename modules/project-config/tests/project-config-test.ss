;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/misc/ports read-file-string)
        (only-in :clan/poo/object .get .o .cc)
        (only-in "../config.ss" Config))
(export project-config-test)

(def project-config-test
  (test-suite "Project configuration and check selection"
    (test-case "JJ is a configured program and engineering references are distinct from NASA obligations"
      (let* ((decode (.get Config decode))
             (select (.get Config commit))
             (configure (.get Config resolve))
             (configured-settings
              (.o project: "example" profile: "nasa/sdlc/npr-7150.2" primary: "SWE-084"
                  checks: (list (.o requirement: "SWE-084" method: "jj.configuration-audit"))
                  naming: (.o projectKey: "EXAMPLE" languageSources: '("README.org") types: '("feat" "fix")
                              scopes: (list (.o name: "gitops" paths: '("modules/gitops")))
                              references: (list (.o identity: "RFC-7" source: "design.org" element: "work")))))
             (declaration (.o schemaVersion: 1 programs: (.o jj: (.o enable: #t settings: configured-settings))))
             (configured (select (configure declaration)))
             (recorded (select (decode (read-file-string ".agents/aita/project.json")))))
        (check-equal? (hash-ref configured 'primary) "SWE-084")
        (check-equal? (hash-ref (hash-ref configured 'naming) 'projectKey) "EXAMPLE")
        (check-equal? (hash-ref recorded 'project) "tao3k/lambda-aitia")
        (check-equal? (select (decode "{\"schemaVersion\":1}")) #f)
        (check-equal? (decode "{\"schemaVersion\":1,\"services\":{\"commit\":{}}}") #f)))
    (test-case "Scheme and JSON use the same project configuration Contract"
      (let* ((configure (.get Config resolve))
             (decode (.get Config decode))
             (manifest (read-file-string ".agents/aita/project.json"))
             (effective (decode manifest))
             (scheme (configure
                      (.o schemaVersion: 1
                          services: (hash (sysml (hash (enable #t) (parse #t)))))))
             (checks (.get Config checks))
             (minimal (decode "{\"schemaVersion\":1}")))
        (check-equal? (hash-get (hash-get (hash-get effective 'services) 'sysml) 'enable) #t)
        (check-equal? (hash-get (hash-get (hash-get scheme 'services) 'sysml) 'parse) #t)
        (check-equal? (checks effective) #("sysml.parse"))
        (check-equal? (checks scheme) #("sysml.parse"))
        (check-equal? (checks minimal) #())
        (check-equal?
         (checks (decode "{\"schemaVersion\":1,\"services\":{\"sysml\":{\"enable\":false,\"parse\":true}}}"))
         #())
        (check-equal?
         (checks (decode "{\"schemaVersion\":1,\"services\":{\"sysml\":{\"enable\":true,\"parse\":false}}}"))
         #())
        (check-equal?
         (checks (decode "{\"schemaVersion\":1,\"services\":{\"assurance\":{\"enable\":true,\"project\":\"example\",\"profile\":\"adr-0008\"}}}"))
         #("assurance.replay"))
        (check-equal?
         (checks (configure
                  (.o schemaVersion: 1
                      services: (hash (assurance (hash (enable #f) (project "example")
                                                       (profile "adr-0008")))))))
         #())
        (check-equal?
         (decode "{\"schemaVersion\":1,\"services\":{\"assurance\":{\"enable\":true,\"project\":\"example\",\"profile\":\"unknown\"}}}")
         #f)
        (check-equal? (decode "{}") #f)
        (check-equal? (decode "{\"schemaVersion\":1,\"models\":{}}") #f)
        (check-equal? (decode "{\"schemaVersion\":1,\"services\":{\"sysml\":{\"enable\":true}}}") #f)))))
