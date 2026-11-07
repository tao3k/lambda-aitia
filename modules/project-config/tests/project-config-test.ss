;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        (only-in :std/misc/ports read-file-string)
        (only-in :clan/poo/object .get .o)
        (only-in "../../../init.ss" lambda-aitia.init.exports))
(export project-config-test)

(def project-config-test
  (test-suite "Project configuration and check selection"
    (test-case "Scheme and JSON use the same project configuration Contract"
      (let* ((scope (.get lambda-aitia.init.exports modules project-config))
             (configure (.get scope resolve))
             (decode (.get scope decode))
             (manifest (read-file-string ".agents/aita/project.json"))
             (effective (decode manifest))
             (scheme (configure
                      (.o schemaVersion: 1
                          services: (hash (sysml (hash (enable #t) (parse #t)))))))
             (checks (.get scope checks))
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
        (check-equal? (decode "{}") #f)
        (check-equal? (decode "{\"schemaVersion\":1,\"models\":{}}") #f)
        (check-equal? (decode "{\"schemaVersion\":1,\"services\":{\"sysml\":{\"enable\":true}}}") #f)))))
