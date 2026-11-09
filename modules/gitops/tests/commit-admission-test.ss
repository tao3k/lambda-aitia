;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test :std/error
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :clan/poo/object .o .get .cc)
        (only-in :agentic-ai-lab/modules/temporal-causality/runtime/durable-journal
                 journal-open journal-close! journal-cut! journal-verify!)
        (only-in "../../../init.ss" lambda-aitia.init.exports))
(export commit-admission-test)

(def (with-journal path check)
  (let (journal (journal-open path))
    (dynamic-wind void
      (lambda () (check journal) (journal-verify! journal))
      (lambda () (journal-close! journal)))))

(def commit-admission-test
  (test-suite "GitOps durable commit admission"
    (test-case "order revocation and one-shot consumption in the same journal"
      (call-with-temporary-directory "aitia-commit-admission"
        (lambda (dir)
          (let* ((path (path-expand "journal.sqlite" dir))
                 (gitops (.get lambda-aitia.init.exports modules gitops))
                 (compute-intent (.get gitops commit-intent))
                 (approve (.get gitops record-commit-approval!))
                 (revoke (.get gitops revoke-commit-approval!))
                 (consume (.get gitops consume-commit-admission!))
                 (admission (.get gitops commit-admission))
                 (approval (.o identity: "review-a" project: "test-project"
                               intent: (compute-intent "test-project" "attempt-a")
                               policy-revision: "policy-a" not-before: 10 expires-at: 20)))
            (def (submit journal (review "review-a") (attempt "attempt-a")
                         (now 15) (revision "policy-a"))
              (consume journal "test-project" attempt review revision (lambda () now)))
            (with-journal path
              (lambda (journal)
                (check-equal? (submit journal) #f)
                (check-equal? (revoke journal "test-project" "review-early") #t)
                (check-equal? (approve journal (.cc approval identity: "review-early")) #f)
                (check-equal? (approve journal (.cc approval project: "other")) #t)
                (check-equal? (submit journal) #f)
                (check-equal? (approve journal approval) #t)
                (check-equal? (approve journal (.cc approval expires-at: 30)) #f)
                (check-equal? (submit journal "review-a" "attempt-a" 20) #f)
                (check-equal? (submit journal "review-a" "attempt-a" 9) #f)
                (check-equal? (submit journal "review-a" "attempt-a" 15 "old") #f)
                (check-equal? (submit journal "review-a" "other-attempt") #f)
                (check-equal? (revoke journal "test-project" "review-a") #t)
                (check-equal? (submit journal) #f)
                (check-equal? (approve journal approval) #f)
                (check-equal? (approve journal (.cc approval identity: "review-b")) #t)
                (let* ((reads 0)
                       (receipt (consume journal "test-project" "attempt-a" "review-b" "policy-a"
                                  (lambda () (set! reads (+ reads 1)) (if (= reads 1) 19 20)))))
                  (check-equal? reads 2)
                  (check-equal? receipt #f))
                (let (receipt (submit journal "review-b"))
                  (check-equal? (.get receipt phase) 'admitted)
                  (check-equal? (.get receipt attempt) "attempt-a"))
                (check-equal? (revoke journal "test-project" "review-b") #t)))
            (with-journal path
              (lambda (journal)
                (check-equal? (submit journal "review-b") #f)
                (check-equal? (submit journal) #f)
                (let (record (admission journal "test-project" "review-b"))
                  (check-equal? (.get record attempt) "attempt-a")
                  (check-equal? (.get record approval) "review-b"))
                (check-equal? (admission journal "other" "review-b") #f)
                (check-equal? (admission journal "test-project" "review-a") #f)
                (check-equal? (approve journal (.cc approval identity: "review-c")) #t)
                (check-equal? (submit journal "review-c") #f)
                (check-equal?
                 (approve journal (.cc approval identity: "review-b"
                                    intent: (compute-intent "test-project" "attempt-b")))
                 #f)
                (check-equal? (submit journal "review-b" "attempt-b") #f)
                (check-equal?
                 (approve journal (.cc approval identity: "review-d"
                                    intent: (compute-intent "test-project" "attempt-b")))
                 #t)
                (let (cut-observed #f)
                  (journal-cut! journal
                    (lambda (stage _)
                      (when (eq? stage 'after-receive)
                        (with-journal path
                          (lambda (owner)
                            (set! cut-observed (revoke owner "test-project" "review-d")))))))
                  (check-exception (submit journal "review-d" "attempt-b") Error?)
                  (check-equal? cut-observed #t))))
            (with-journal path
              (lambda (journal)
                (check-equal? (submit journal "review-d" "attempt-b") #f)
                (check-equal? (admission journal "test-project" "review-d") #f)))))))))
