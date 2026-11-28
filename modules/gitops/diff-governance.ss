;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Scheme-driven, 100% POO + functional unified-diff governance framework:
;;;   - Composable Subdomain Rule-Pack DSL (`AuditRule.`, `RulePack.`, `compose-rule-packs`)
;;;     so 1,000+ subdomains and bounded LLM-proposed rule packs plug in with ZERO Rust changes.
;;;   - Strict monotone-tightening invariant: the core DE G2 floor (`+de-g2-core-rule-pack+`)
;;;     is always preserved and cannot be weakened or bypassed by subdomain or LLM packs.
;;;   - Lexer-backed code-only stripping (strings & comments stripped per language family) plus
;;;     multi-line Gerbil Scheme S-expr window scanning and per-file assertion conservation.
;;;   - First-class Causal Trajectory Chain (`CausalEvent.`), Temporal Causality DAG
;;;     (`happens-before`, `causal-lineage`, competing hypotheses, open questions), and
;;;     FunFlow `ChoiceFlowPlan` telemetry fusion. Always preserves `action-authorized?: #f`.

(import (only-in :clan/poo/object .def .get .o .ref .slot? object?)
        (only-in :gerbil/core string-contains string-prefix? string-suffix? string-split string-join)
        (only-in :std/list/list append-map delete-duplicates/hash filter filter-map foldl))

(export AuditRule.
        RulePack.
        CausalEvent.
        de-g2-core-rule-pack
        make-audit-rule
        make-rule-pack
        compose-rule-packs
        rule-pack-from-descriptor
        strip-code-only
        gitops-diff-defense-audit)

(def (opt-slot obj key default)
  (if (and (object? obj) (.slot? obj key))
    (.ref obj key)
    default))

(def (non-empty-string? value)
  (and (string? value) (> (string-length value) 0)))

(def (str-has? hay needle)
  (and (string? hay) (string? needle) (> (string-length needle) 0)
       (if (string-contains hay needle) #t #f)))

(def (str-has-any? hay needles)
  (let loop ((xs needles))
    (cond
     ((null? xs) #f)
     ((str-has? hay (car xs)) #t)
     (else (loop (cdr xs))))))

(def (str-has-all? hay needles)
  (let loop ((xs needles))
    (cond
     ((null? xs) #t)
     ((not (str-has? hay (car xs))) #f)
     (else (loop (cdr xs))))))

(def (take-chars str n)
  (if (<= (string-length str) n) str (substring str 0 n)))

(def (ascii-space? ch)
  (or (char=? ch #\space) (char=? ch #\tab) (char=? ch #\newline) (char=? ch #\return)))

(def (string-trim-both str)
  (let* ((n (string-length str))
         (start (let loop ((i 0))
                  (if (and (< i n) (ascii-space? (string-ref str i)))
                    (loop (+ i 1))
                    i)))
         (end (let loop ((j n))
                (if (and (> j start) (ascii-space? (string-ref str (- j 1))))
                  (loop (- j 1))
                  j))))
    (substring str start end)))

(def (string-downcase str)
  (let* ((n (string-length str))
         (out (make-string n)))
    (let loop ((i 0))
      (if (>= i n)
        out
        (begin
          (string-set! out i (char-downcase (string-ref str i)))
          (loop (+ i 1)))))))

(def (char-ident? ch)
  (or (char-alphabetic? ch) (char-numeric? ch) (char=? ch #\_) (char=? ch #\-)))

;; ── First-Class POO Subdomain Rule-Pack & Causal Trajectory Prototypes ─────

(.def AuditRule.
  kind: 'lambda-aitia.audit-rule.v1
  rule-id: ""
  subdomain: "de-g2-core"
  hallucination-class: "silent-fallback"
  languages: '("*")
  match-mode: 'code-only
  tokens-all: '()
  tokens-any: '()
  forbid-unless: '()
  exclude-test-files?: #f
  predicate: #f
  anti-pattern-id: "AP-SUBDOMAIN"
  detail: "Subdomain governance invariant violation"
  c2-replacement: "Replace defensive fallback with an explicit typed error and witness."
  anti-evasion-warning: "Do NOT bypass via skip annotations, silent catch blocks, or deleted assertions.")

(.def RulePack.
  kind: 'lambda-aitia.rule-pack.v1
  pack-id: ""
  subdomain: ""
  version: "1.0.0"
  source-mode: "subdomain-library"
  rules: '()
  monotone-tightening?: #t
  action-authorized?: #f)

(.def CausalEvent.
  kind: 'lambda-aitia.causal-event.v1
  event-id: ""
  epoch: 0
  stage: ""
  surface: ""
  rule-packs: '()
  findings-count: 0
  causal-parents: '()
  summary: ""
  action-authorized?: #f)

(def (make-audit-rule
      rule-id: rule-id
      subdomain: (subdomain "de-g2-core")
      hallucination-class: (hclass "silent-fallback")
      languages: (languages '("*"))
      match-mode: (match-mode 'code-only)
      tokens-all: (tokens-all '())
      tokens-any: (tokens-any '())
      forbid-unless: (forbid-unless '())
      exclude-test-files?: (exclude-tests? #f)
      predicate: (predicate #f)
      anti-pattern-id: (ap-id "AP-SUBDOMAIN")
      detail: (detail "Governance invariant violation")
      c2-replacement: (c2 "Fail closed with a typed boundary error and executable witness.")
      anti-evasion-warning: (warn "Do NOT evade by suppressing checks or deleting assertions."))
  (.o (:: @ AuditRule.)
      (rule-id := rule-id)
      (subdomain := subdomain)
      (hallucination-class := hclass)
      (languages := languages)
      (match-mode := match-mode)
      (tokens-all := tokens-all)
      (tokens-any := tokens-any)
      (forbid-unless := forbid-unless)
      (exclude-test-files? := (and exclude-tests? #t))
      (predicate := predicate)
      (anti-pattern-id := ap-id)
      (detail := detail)
      (c2-replacement := c2)
      (anti-evasion-warning := warn)))

(def (make-rule-pack
      pack-id: pack-id
      subdomain: subdomain
      version: (version "1.0.0")
      source-mode: (source-mode "subdomain-library")
      rules: (rules '()))
  (.o (:: @ RulePack.)
      (pack-id := pack-id)
      (subdomain := subdomain)
      (version := version)
      (source-mode := source-mode)
      (rules := rules)
      (monotone-tightening? := #t)
      (action-authorized? := #f)))

;; Strictly monotone additive composition: core DE G2 pack is ALWAYS prepended
;; and cannot be weakened, overridden, or disabled by any subdomain/LLM pack.
(def (compose-rule-packs core-pack extra-packs)
  (let* ((valid-extras (filter object? extra-packs))
         (all-packs (cons core-pack valid-extras))
         (all-rules (append-map (lambda (p) (opt-slot p 'rules '())) all-packs)))
    (.o (:: @ RulePack.)
        (pack-id := "composed-monotone-governance-pack")
        (subdomain := "composed")
        (version := "1.0.0")
        (source-mode := "monotone-composed")
        (rules := all-rules)
        (packs := all-packs)
        (monotone-tightening? := #t)
        (core-floor-preserved? := #t)
        (action-authorized? := #f))))

(def (rule-pack-from-descriptor desc)
  (let* ((pack-id (opt-slot desc 'pack-id "ephemeral-subdomain-pack"))
         (subdomain (opt-slot desc 'subdomain pack-id))
         (version (opt-slot desc 'version "1.0.0"))
         (source-mode (opt-slot desc 'source-mode "subdomain-library"))
         (raw-rules (opt-slot desc 'rules '()))
         (rules
          (map (lambda (r idx)
                 (let* ((rid (let ((s (opt-slot r 'rule-id "")))
                               (if (non-empty-string? s) s
                                   (string-append subdomain "-rule-" (number->string idx)))))
                        (mode-str (opt-slot r 'match-mode "code-only"))
                        (mode (cond
                               ((equal? mode-str "raw-line") 'raw-line)
                               ((equal? mode-str "scheme-sexpr") 'scheme-sexpr)
                               (else 'code-only))))
                   (make-audit-rule
                    rule-id: rid
                    subdomain: subdomain
                    hallucination-class: (opt-slot r 'hallucination-class "subdomain-invariant-violation")
                    languages: (let ((ls (opt-slot r 'languages '("*"))))
                                 (if (null? ls) '("*") ls))
                    match-mode: mode
                    tokens-all: (opt-slot r 'tokens-all '())
                    tokens-any: (opt-slot r 'tokens-any '())
                    forbid-unless: (opt-slot r 'forbid-unless '())
                    exclude-test-files?: (and (opt-slot r 'exclude-test-files? #f) #t)
                    anti-pattern-id: (opt-slot r 'anti-pattern-id "AP-SUBDOMAIN")
                    detail: (opt-slot r 'detail (string-append "Subdomain `" subdomain "` rule `" rid "` violated"))
                    c2-replacement: (opt-slot r 'c2-replacement "Satisfy subdomain invariant explicitly with typed contract and witness.")
                    anti-evasion-warning: (opt-slot r 'anti-evasion-warning "Subdomain rules are strictly additive; do NOT weaken the DE G2 core floor."))))
               raw-rules (iota (length raw-rules)))))
    (make-rule-pack
     pack-id: pack-id
     subdomain: subdomain
     version: version
     source-mode: source-mode
     rules: rules)))

;; ── Language Detection & Lexer-Backed String/Comment Stripping ─────────────

(def (detect-language file-path)
  (let ((p (string-downcase file-path)))
    (cond
     ((string-suffix? ".rs" p) "rust")
     ((string-suffix? ".go" p) "go")
     ((or (string-suffix? ".c" p) (string-suffix? ".h" p)) "c")
     ((or (string-suffix? ".cc" p) (string-suffix? ".cpp" p)
          (string-suffix? ".cxx" p) (string-suffix? ".hpp" p) (string-suffix? ".hh" p)) "cpp")
     ((or (string-suffix? ".ts" p) (string-suffix? ".tsx" p) (string-suffix? ".mts" p)) "typescript")
     ((or (string-suffix? ".js" p) (string-suffix? ".jsx" p)
          (string-suffix? ".mjs" p) (string-suffix? ".cjs" p)) "javascript")
     ((string-suffix? ".py" p) "python")
     ((or (string-suffix? ".ss" p) (string-suffix? ".scm" p)) "scheme")
     (else #f))))

(def (test-file-path? file-path)
  (let ((p (string-downcase file-path)))
    (or (string-prefix? "tests/" p)
        (string-prefix? "test/" p)
        (string-prefix? "t/" p)
        (string-prefix? "examples/" p)
        (str-has? p "/tests/")
        (str-has? p "/test/")
        (str-has? p "/t/")
        (str-has? p "/examples/")
        (string-suffix? "_test.rs" p)
        (string-suffix? "_test.go" p)
        (string-suffix? "-test.ss" p)
        (string-suffix? ".test.ts" p)
        (string-suffix? ".spec.ts" p)
        (string-suffix? ".test.js" p))))

;; Pure functional lexer stripping string literals and comments so docs,
;; error messages, and linter rules NEVER trigger false positives.
(def (strip-clike-line line allow-single-quote? allow-backtick?)
  (let* ((n (string-length line))
         (out (make-string n #\space)))
    (let loop ((i 0) (mode 'code))
      (if (>= i n)
        (string-trim-both out)
        (let ((ch (string-ref line i))
              (nx (and (< (+ i 1) n) (string-ref line (+ i 1)))))
          (case mode
            ((code)
             (cond
              ((and (char=? ch #\/) nx (char=? nx #\/))
               (string-trim-both out))
              ((and (char=? ch #\/) nx (char=? nx #\*))
               (loop (+ i 2) 'block-comment))
              ((char=? ch #\")
               ;; Preserve empty double-quote placeholder so `unwrap_or("")` shape stays distinct from ident
               (loop (+ i 1) 'dquote))
              ((and allow-single-quote? (char=? ch #\'))
               (loop (+ i 1) 'squote))
              ((and allow-backtick? (char=? ch #\`))
               (loop (+ i 1) 'bquote))
              (else
               (string-set! out i ch)
               (loop (+ i 1) 'code))))
            ((block-comment)
             (if (and (char=? ch #\*) nx (char=? nx #\/))
               (loop (+ i 2) 'code)
               (loop (+ i 1) 'block-comment)))
            ((dquote)
             (cond
              ((char=? ch #\\) (loop (+ i 2) 'dquote))
              ((char=? ch #\") (loop (+ i 1) 'code))
              (else (loop (+ i 1) 'dquote))))
            ((squote)
             (cond
              ((char=? ch #\\) (loop (+ i 2) 'squote))
              ((char=? ch #\') (loop (+ i 1) 'code))
              (else (loop (+ i 1) 'squote))))
            ((bquote)
             (cond
              ((char=? ch #\\) (loop (+ i 2) 'bquote))
              ((char=? ch #\`) (loop (+ i 1) 'code))
              (else (loop (+ i 1) 'bquote))))))))))

(def (strip-python-line line)
  (let* ((n (string-length line))
         (out (make-string n #\space)))
    (let loop ((i 0) (mode 'code))
      (if (>= i n)
        (string-trim-both out)
        (let ((ch (string-ref line i)))
          (case mode
            ((code)
             (cond
              ((char=? ch #\#) (string-trim-both out))
              ((char=? ch #\") (loop (+ i 1) 'dquote))
              ((char=? ch #\') (loop (+ i 1) 'squote))
              (else
               (string-set! out i ch)
               (loop (+ i 1) 'code))))
            ((dquote)
             (cond
              ((char=? ch #\\) (loop (+ i 2) 'dquote))
              ((char=? ch #\") (loop (+ i 1) 'code))
              (else (loop (+ i 1) 'dquote))))
            ((squote)
             (cond
              ((char=? ch #\\) (loop (+ i 2) 'squote))
              ((char=? ch #\') (loop (+ i 1) 'code))
              (else (loop (+ i 1) 'squote))))))))))

(def (strip-scheme-line line)
  (let* ((n (string-length line))
         (out (make-string n #\space)))
    (let loop ((i 0) (mode 'code))
      (if (>= i n)
        (string-trim-both out)
        (let ((ch (string-ref line i)))
          (case mode
            ((code)
             (cond
              ((char=? ch #\;) (string-trim-both out))
              ((char=? ch #\") (loop (+ i 1) 'dquote))
              (else
               (string-set! out i ch)
               (loop (+ i 1) 'code))))
            ((dquote)
             (cond
              ((char=? ch #\\) (loop (+ i 2) 'dquote))
              ((char=? ch #\") (loop (+ i 1) 'code))
              (else (loop (+ i 1) 'dquote))))))))))

(def (strip-code-only lang line)
  (cond
   ((equal? lang "python") (strip-python-line line))
   ((equal? lang "scheme") (strip-scheme-line line))
   ((or (equal? lang "typescript") (equal? lang "javascript"))
    (strip-clike-line line #t #t))
   ((equal? lang "go")
    (strip-clike-line line #f #t))
   (else
    ;; Rust / C / C++: single quote is char literal or Rust lifetime `'a`, so only strip `"..."`
    (strip-clike-line line #f #f))))

(def (extract-line-comment lang line)
  (let ((n (string-length line)))
    (cond
     ((equal? lang "python")
      (let loop ((i 0) (q #f))
        (cond
         ((>= i n) "")
         (q (let ((ch (string-ref line i)))
              (cond ((char=? ch #\\) (loop (+ i 2) q))
                    ((char=? ch q) (loop (+ i 1) #f))
                    (else (loop (+ i 1) q)))))
         ((or (char=? (string-ref line i) #\") (char=? (string-ref line i) #\'))
          (loop (+ i 1) (string-ref line i)))
         ((char=? (string-ref line i) #\#) (substring line i n))
         (else (loop (+ i 1) #f)))))
     ((equal? lang "scheme")
      (let loop ((i 0) (in-str? #f))
        (cond
         ((>= i n) "")
         (in-str? (let ((ch (string-ref line i)))
                    (cond ((char=? ch #\\) (loop (+ i 2) #t))
                          ((char=? ch #\") (loop (+ i 1) #f))
                          (else (loop (+ i 1) #t)))))
         ((char=? (string-ref line i) #\") (loop (+ i 1) #t))
         ((char=? (string-ref line i) #\;) (substring line i n))
         (else (loop (+ i 1) #f)))))
     (else
      (let loop ((i 0) (in-str? #f))
        (cond
         ((>= i n) "")
         (in-str? (let ((ch (string-ref line i)))
                    (cond ((char=? ch #\\) (loop (+ i 2) #t))
                          ((char=? ch #\") (loop (+ i 1) #f))
                          (else (loop (+ i 1) #t)))))
         ((char=? (string-ref line i) #\") (loop (+ i 1) #t))
         ((and (< (+ i 1) n) (char=? (string-ref line i) #\/) (char=? (string-ref line (+ i 1)) #\/))
          (substring line i n))
         (else (loop (+ i 1) #f))))))))

;; Recognizes benign Rust Option accessor chains (aligned with DE multi-lang-auditor.ts
;; `isRustOptionAccessorChain`) so `.get(...).unwrap_or_default()` doesn't false-positive,
;; while Result / standalone `.unwrap_or_default()` or `.ok().unwrap_or(...)` IS flagged.
(def (rust-option-accessor-chain? code)
  (and (not (str-has? code ".ok()"))
       (or (str-has-any? code '(".get(" ".as_str()" ".as_deref()" ".strip_prefix("
                                ".strip_suffix(" ".and_then(" ".first()" ".last()"
                                ".next()" ".file_name()" ".extension()" ".parent()"
                                ".find(" ".position(" ".cloned()" ".copied()"
                                ".to_str()" ".filter(" ".map("))
           ;; Indented continuation `.unwrap_or_default()` directly after an Option chain
           (string-prefix? ".unwrap_or_default()" code))))

(def (rust-silent-fallback-line? ctx)
  (let ((code (.get ctx code)))
    (and (non-empty-string? code)
         (or (and (str-has? code ".unwrap_or_default()")
                  (not (rust-option-accessor-chain? code)))
             (str-has-any? code '(".ok().unwrap_or("
                                  "Err(_) => Ok(())"
                                  "Err(_) => return Ok(())"
                                  "Err(_) => {}"))))))

(def (go-silent-fallback-line? ctx)
  (let ((code (.get ctx code)))
    (and (non-empty-string? code)
         (or (str-has? code "recover()")
             (and (str-has? code "if err != nil")
                  (str-has? code "return nil"))))))

(def (ts-js-silent-fallback-line? ctx)
  (let ((code (.get ctx code)))
    (and (non-empty-string? code)
         (or (str-has-any? code '("catch {}" "catch () {}" "catch (e) {}"
                                  "catch (err) {}" "catch (_) {}"))
             (and (str-has? code "catch")
                  (str-has-any? code '("return true" "return {}" "return []" "return null")))))))

(def (python-silent-fallback-line? ctx)
  (let ((code (.get ctx code)))
    (and (non-empty-string? code)
         (or (str-has-any? code '("except: pass" "except Exception: pass"
                                  "except BaseException: pass"))
             (and (str-has? code "except")
                  (str-has-any? code '("return True" "return None" "return {}" "return []")))))))

(def (scheme-silent-fallback-line? ctx)
  (let ((code (.get ctx code)))
    (and (non-empty-string? code)
         (or (str-has? code "(ignore-errors")
             (and (str-has? code "(with-catch")
                  (str-has-any? code '("(lambda (_) #f)" "(lambda (_) #t)"
                                       "(lambda (_) '())" "(lambda (_) (void))"
                                       "(lambda (e) #f)" "(lambda (e) '())")))))))

(def (c-cpp-silent-fallback-line? ctx)
  (let ((code (.get ctx code)))
    (and (non-empty-string? code)
         (or (str-has-any? code '("catch (...) {}" "catch(...) {}"))
             (and (str-has? code "catch (...)") (str-has? code "return 0"))))))

(def (floor-suppression-line? ctx)
  (let ((code (.get ctx code))
        (comment (.get ctx comment)))
    (or (str-has-any? code '("#[ignore]" "#[ignore =" "#define NDEBUG"
                             "test.skip(" "it.skip(" "pytest.mark.skip"
                             "unittest.skip" "allowGlobalPurge: true"
                             "allowGlobalPurge = true" "requireCountermodels: false"
                             "requireCountermodels = false"))
        (str-has-any? comment '("@ts-ignore" "@ts-expect-error")))))

(def (noop-catch-rethrow-line? ctx)
  (let ((code (.get ctx code)))
    (and (non-empty-string? code)
         (or (and (str-has? code "catch")
                  (or (str-has? code "throw ") (str-has? code "throw;")))
             (str-has-any? code '("Err(e) => return Err(e)"
                                  "Err(e) => Err(e)"
                                  "Err(err) => return Err(err)"
                                  "Err(err) => Err(err)"))))))

(def (fabricated-evidence-line? ctx)
  (let ((code (.get ctx code))
        (comment (.get ctx comment)))
    (and (non-empty-string? code)
         (str-has-any? code '("return true" "return True" "verified: true"
                              "passed: true" "admissible: true"))
         (str-has-any? comment '("TODO" "FIXME" "stub" "placeholder" "fake")))))

;; ── Core DE G2 Rule Pack (Immutable Floor) ─────────────────────────────────

(def de-g2-core-rule-pack
  (make-rule-pack
   pack-id: "de-g2-core"
   subdomain: "de-g2-core"
   version: "1.0.0"
   source-mode: "upstream-de-core"
   rules:
   (list
    (make-audit-rule
     rule-id: "rust-silent-fallback"
     subdomain: "de-g2-core"
     hallucination-class: "silent-fallback"
     languages: '("rust")
     exclude-test-files?: #t
     predicate: rust-silent-fallback-line?
     anti-pattern-id: "AP-01"
     detail: "Silent fallback collapses Rust Result/error into default or Ok(())"
     c2-replacement: "Propagate a typed domain error via `?` or structured `Result<T, DomainError>` with fail-closed boundary handling."
     anti-evasion-warning: "Do NOT replace with empty catch, `unwrap_or_default()`, or silent `Ok(())`.")
    (make-audit-rule
     rule-id: "go-silent-fallback"
     subdomain: "de-g2-core"
     hallucination-class: "silent-fallback"
     languages: '("go")
     exclude-test-files?: #t
     predicate: go-silent-fallback-line?
     anti-pattern-id: "AP-01"
     detail: "Silent fallback swallows Go error or panic via recover()/return nil"
     c2-replacement: "Return wrapped typed error (`fmt.Errorf(\"...: %w\", err)`) and let callers handle failure explicitly."
     anti-evasion-warning: "Do NOT suppress errors with `recover()` or `return nil`.")
    (make-audit-rule
     rule-id: "ts-js-silent-fallback"
     subdomain: "de-g2-core"
     hallucination-class: "silent-fallback"
     languages: '("typescript" "javascript")
     exclude-test-files?: #t
     predicate: ts-js-silent-fallback-line?
     anti-pattern-id: "AP-01"
     detail: "Silent catch block suppresses failure or returns fabricated truthy/empty fallback"
     c2-replacement: "Return a discriminated failure union or propagate the typed boundary error."
     anti-evasion-warning: "Do NOT hide failures in empty catch blocks or fallback truthy values.")
    (make-audit-rule
     rule-id: "python-silent-fallback"
     subdomain: "de-g2-core"
     hallucination-class: "silent-fallback"
     languages: '("python")
     exclude-test-files?: #t
     predicate: python-silent-fallback-line?
     anti-pattern-id: "AP-01"
     detail: "Bare/broad except silently swallows exception or returns fallback default"
     c2-replacement: "Catch only narrow expected exceptions and propagate typed failure state."
     anti-evasion-warning: "Do NOT swallow exceptions with `except: pass` or fallback `return True/None`.")
    (make-audit-rule
     rule-id: "scheme-silent-fallback"
     subdomain: "de-g2-core"
     hallucination-class: "silent-fallback"
     languages: '("scheme")
     exclude-test-files?: #t
     predicate: scheme-silent-fallback-line?
     anti-pattern-id: "AP-01"
     detail: "Scheme with-catch/ignore-errors silently collapses exception into #f/#t/'()/(void)"
     c2-replacement: "Return an explicit typed failure POO object or propagate the condition to the governed boundary."
     anti-evasion-warning: "Do NOT wrap arbitrary code in `(ignore-errors ...)` or `(with-catch (lambda (_) #f) ...)`.")
    (make-audit-rule
     rule-id: "c-cpp-silent-fallback"
     subdomain: "de-g2-core"
     hallucination-class: "silent-fallback"
     languages: '("c" "cpp")
     exclude-test-files?: #t
     predicate: c-cpp-silent-fallback-line?
     anti-pattern-id: "AP-01"
     detail: "C/C++ catch(...) silently swallows exception or returns 0"
     c2-replacement: "Return an explicit status enum error code and preserve failure context."
     anti-evasion-warning: "Do NOT silence unknown exceptions with `catch (...) {}`.")
    (make-audit-rule
     rule-id: "verification-floor-suppression"
     subdomain: "de-g2-core"
     hallucination-class: "floor-weakening"
     languages: '("*")
     exclude-test-files?: #f
     predicate: floor-suppression-line?
     anti-pattern-id: "AP-02"
     detail: "Verification floor weakened via skip/ignore/NDEBUG/countermodel-disable directive"
     c2-replacement: "Keep strict verification assertions, countermodel checks, and test execution intact."
     anti-evasion-warning: "Do NOT evade via @ts-ignore, #[ignore], #define NDEBUG, pytest.mark.skip, or test.skip.")
    (make-audit-rule
     rule-id: "noop-catch-rethrow"
     subdomain: "de-g2-core"
     hallucination-class: "redundant-defensive-glue"
     languages: '("*")
     exclude-test-files?: #t
     predicate: noop-catch-rethrow-line?
     anti-pattern-id: "AP-03"
     detail: "No-op error catch-and-rethrow glue adds defensive noise without boundary refinement"
     c2-replacement: "Parse once into sealed types at the single trust boundary; remove no-op catch-rethrow glue or prove necessity with DE F3 Quint guard-probe."
     anti-evasion-warning: "Do NOT rename or reorder redundant catch-rethrow blocks without an executable counterexample.")
    (make-audit-rule
     rule-id: "stub-positive-verdict"
     subdomain: "de-g2-core"
     hallucination-class: "fabricated-evidence"
     languages: '("*")
     exclude-test-files?: #f
     predicate: fabricated-evidence-line?
     anti-pattern-id: "AP-04"
     detail: "Stub/TODO code fabricates a positive/verified verdict without running real oracle"
     c2-replacement: "Fail closed (Refuted/PendingMethod) until real oracle verification executes."
     anti-evasion-warning: "Do NOT return stubbed `verified: true` or hardcoded positive verdicts."))))

;; ── Assertion / Governance-Floor Conservation Predicates (Per-File) ────────

(def (assertion-code-line? lang code)
  (and (non-empty-string? code)
       (cond
        ((equal? lang "rust")
         (str-has-any? code '("assert!(" "assert_eq!(" "assert_ne!(" "debug_assert!(")))
        ((equal? lang "scheme")
         (str-has-any? code '("(check " "(check-equal?" "(check-true" "(check-false"
                              "(assert!" "(unless ")))
        ((equal? lang "python")
         (or (string-prefix? "assert " code)
             (str-has-any? code '("assertEqual(" "assertTrue(" "assertFalse(" "assertRaises("))))
        ((equal? lang "go")
         (str-has-any? code '("t.Fatal(" "t.Fatalf(" "t.Error(" "t.Errorf(" "assert.")))
        ((or (equal? lang "typescript") (equal? lang "javascript"))
         (str-has-any? code '("expect(" "assert(" "assert." "assertEquals(")))
        ((or (equal? lang "c") (equal? lang "cpp"))
         (str-has-any? code '("assert(" "static_assert(" "EXPECT_" "ASSERT_")))
        (else #f))))

(def (governance-floor-line? code)
  (and (non-empty-string? code)
       (str-has-any? code '("actionAuthorized" "action-authorized?" "requireCountermodels"
                            "forbidFloorWeakening" "forbidUnwitnessedObligationDeletion"))))

(def (formal-guard-line? code comment)
  (or (str-has? code "(guard ")
      (str-has? comment "@countermodel")))

;; ── Multi-Line Gerbil Scheme `(with-catch ...)` S-Expr Window Scanner ──────

(def (collapse-spaces str)
  (let* ((n (string-length str))
         (out (open-output-string)))
    (let loop ((i 0) (prev-sp? #t))
      (if (>= i n)
        (string-trim-both (get-output-string out))
        (let ((ch (string-ref str i)))
          (if (or (char=? ch #\space) (char=? ch #\tab) (char=? ch #\newline) (char=? ch #\return))
            (begin
              (unless prev-sp? (write-char #\space out))
              (loop (+ i 1) #t))
            (begin
              (write-char ch out)
              (loop (+ i 1) #f))))))))

(def (scan-scheme-multiline-hunk file surface hunk-start-line added-pairs)
  ;; added-pairs is list of (line-no . code-only-str)
  (if (or (null? added-pairs) (test-file-path? file))
    '()
    (let* ((joined (collapse-spaces (string-join (map cdr added-pairs) " ")))
           (has-single-line-hit?
            (ormap (lambda (pair)
                     (scheme-silent-fallback-line?
                      (.o (code := (cdr pair)) (comment := ""))))
                   added-pairs)))
      (if (and (not has-single-line-hit?)
               (str-has? joined "(with-catch")
               (str-has-any? joined '("(with-catch (lambda (_) #f)"
                                      "(with-catch (lambda (_) #t)"
                                      "(with-catch (lambda (_) '())"
                                      "(with-catch (lambda (_) (void))"
                                      "(with-catch (lambda (e) #f)"
                                      "(with-catch (lambda (e) '())"
                                      "(with-catch (lambda (ex) #f)"
                                      "(with-catch (lambda (ex) '())")))
        (list (.o (file := file)
                  (language := "scheme")
                  (surface := surface)
                  (line := hunk-start-line)
                  (subdomain := "de-g2-core")
                  (pack-id := "de-g2-core")
                  (hallucination-class := "silent-fallback")
                  (rule := "scheme-multiline-silent-with-catch")
                  (anti-pattern-id := "AP-01")
                  (detail := "Multi-line Scheme (with-catch (lambda (_) <fallback>) ...) silently swallows exception")
                  (c2-replacement := "Return an explicit typed failure POO value or propagate the condition to the governed boundary.")
                  (anti-evasion-warning := "Do NOT split `(with-catch (lambda (_) #f) ...)` across lines to evade single-line checks.")
                  (excerpt := (take-chars joined 140))))
        '()))))

;; ── Rule Matching Engine ───────────────────────────────────────────────────

(def (rule-applies-to-lang? rule lang)
  (let ((langs (.get rule languages)))
    (or (member "*" langs) (member lang langs))))

(def (evaluate-rule-on-ctx rule ctx is-test-file?)
  (let ((lang (.get ctx language)))
    (and (rule-applies-to-lang? rule lang)
         (not (and (.get rule exclude-test-files?) is-test-file?))
         (let ((pred (.get rule predicate)))
           (if (procedure? pred)
             (pred ctx)
             (let* ((mode (.get rule match-mode))
                    (text (if (eq? mode 'raw-line) (.get ctx raw) (.get ctx code)))
                    (all-toks (.get rule tokens-all))
                    (any-toks (.get rule tokens-any))
                    (unless-toks (.get rule forbid-unless)))
               (and (non-empty-string? text)
                    (or (pair? all-toks) (pair? any-toks))
                    (or (null? all-toks) (str-has-all? text all-toks))
                    (or (null? any-toks) (str-has-any? text any-toks))
                    (or (null? unless-toks) (not (str-has-any? text unless-toks))))))))))

(def (parse-hunk-new-start line)
  ;; Parse `@@ -a,b +c,d @@` -> c
  (let ((plus-pos (string-contains line "+")))
    (if (not plus-pos)
      1
      (let* ((rest (substring line (+ plus-pos 1) (string-length line)))
             (n (string-length rest)))
        (let loop ((i 0))
          (if (and (< i n) (char-numeric? (string-ref rest i)))
            (loop (+ i 1))
            (or (and (> i 0) (string->number (substring rest 0 i))) 1)))))))

;; ── Unified Diff Parser & Multi-Pack Evaluator ─────────────────────────────

(def (audit-unified-diff-surface diff-text surface composed-pack)
  (if (not (non-empty-string? diff-text))
    '()
    (let* ((lines (string-split diff-text #\newline))
           (rules (.get composed-pack rules))
           (findings '())
           ;; Per-file conservation table: file -> (lang removed-a added-a first-a removed-f added-f first-f removed-g added-g first-g)
           (file-totals (make-hash-table))
           (ensure-totals!
            (lambda (file lang line-no)
              (or (hash-get file-totals file)
                  (let ((v (vector lang 0 0 line-no 0 0 line-no 0 0 line-no)))
                    (hash-put! file-totals file v)
                    v))))
           (cur-file "")
           (cur-lang #f)
           (cur-test? #f)
           (new-line 1)
           (hunk-start 1)
           (scheme-hunk-added '())
           (flush-scheme-hunk!
            (lambda ()
              (when (and (equal? cur-lang "scheme") (pair? scheme-hunk-added))
                (let ((ml (scan-scheme-multiline-hunk cur-file surface hunk-start (reverse scheme-hunk-added))))
                  (set! findings (append (reverse ml) findings))))
              (set! scheme-hunk-added '()))))
      (for-each
       (lambda (line)
         (cond
          ((string-prefix? "+++ b/" line)
           (flush-scheme-hunk!)
           (set! cur-file (substring line 6 (string-length line)))
           (set! cur-lang (detect-language cur-file))
           (set! cur-test? (test-file-path? cur-file))
           (set! new-line 1)
           (set! hunk-start 1))
          ((string-prefix? "+++ /dev/null" line)
           (flush-scheme-hunk!)
           (set! cur-file "")
           (set! cur-lang #f))
          ((string-prefix? "@@ " line)
           (flush-scheme-hunk!)
           (set! new-line (parse-hunk-new-start line))
           (set! hunk-start new-line))
          ((and cur-lang (string-prefix? "-" line) (not (string-prefix? "---" line)))
           (let* ((raw (substring line 1 (string-length line)))
                  (code (strip-code-only cur-lang raw))
                  (comment (extract-line-comment cur-lang raw))
                  (tot (ensure-totals! cur-file cur-lang new-line)))
             (when (assertion-code-line? cur-lang code)
               (when (= (vector-ref tot 1) 0) (vector-set! tot 3 new-line))
               (vector-set! tot 1 (+ (vector-ref tot 1) 1)))
             (when (governance-floor-line? code)
               (when (= (vector-ref tot 4) 0) (vector-set! tot 6 new-line))
               (vector-set! tot 4 (+ (vector-ref tot 4) 1)))
             (when (formal-guard-line? code comment)
               (when (= (vector-ref tot 7) 0) (vector-set! tot 9 new-line))
               (vector-set! tot 7 (+ (vector-ref tot 7) 1)))))
          ((and cur-lang (string-prefix? "+" line) (not (string-prefix? "+++" line)))
           (let* ((raw (substring line 1 (string-length line)))
                  (code (strip-code-only cur-lang raw))
                  (comment (extract-line-comment cur-lang raw))
                  (tot (ensure-totals! cur-file cur-lang new-line))
                  (ctx (.o (file := cur-file)
                           (language := cur-lang)
                           (surface := surface)
                           (line := new-line)
                           (raw := raw)
                           (code := code)
                           (comment := comment))))
             (when (assertion-code-line? cur-lang code)
               (vector-set! tot 2 (+ (vector-ref tot 2) 1)))
             (when (governance-floor-line? code)
               (vector-set! tot 5 (+ (vector-ref tot 5) 1)))
             (when (formal-guard-line? code comment)
               (vector-set! tot 8 (+ (vector-ref tot 8) 1)))
             (when (equal? cur-lang "scheme")
               (set! scheme-hunk-added (cons (cons new-line code) scheme-hunk-added)))
             (for-each
              (lambda (rule)
                (when (evaluate-rule-on-ctx rule ctx cur-test?)
                  (set! findings
                        (cons (.o (file := cur-file)
                                  (language := cur-lang)
                                  (surface := surface)
                                  (line := new-line)
                                  (subdomain := (.get rule subdomain))
                                  (pack-id := (.get rule subdomain))
                                  (hallucination-class := (.get rule hallucination-class))
                                  (rule := (.get rule rule-id))
                                  (anti-pattern-id := (.get rule anti-pattern-id))
                                  (detail := (.get rule detail))
                                  (c2-replacement := (.get rule c2-replacement))
                                  (anti-evasion-warning := (.get rule anti-evasion-warning))
                                  (excerpt := (take-chars (string-trim-both raw) 140)))
                              findings))))
              rules)
             (set! new-line (+ new-line 1))))
          ((and cur-lang (not (string-prefix? "\\" line)))
           (set! new-line (+ new-line 1)))))
       lines)
      (flush-scheme-hunk!)
      ;; Per-file conservation checks (matches DE multi-lang-auditor.ts!)
      (hash-for-each
       (lambda (file tot)
         (let ((lang (vector-ref tot 0))
               (rem-a (vector-ref tot 1))
               (add-a (vector-ref tot 2))
               (line-a (vector-ref tot 3))
               (rem-f (vector-ref tot 4))
               (add-f (vector-ref tot 5))
               (line-f (vector-ref tot 6))
               (rem-g (vector-ref tot 7))
               (add-g (vector-ref tot 8))
               (line-g (vector-ref tot 9)))
           (when (> rem-a add-a)
             (set! findings
                   (cons (.o (file := file)
                             (language := lang)
                             (surface := surface)
                             (line := line-a)
                             (subdomain := "de-g2-core")
                             (pack-id := "de-g2-core")
                             (hallucination-class := "floor-weakening")
                             (rule := "diff-deleted-assertion")
                             (anti-pattern-id := "AP-02")
                             (detail := (string-append "Diff deletes " (number->string (- rem-a add-a))
                                                       " verification assertion(s) without replacement in file"))
                             (c2-replacement := "Restore the deleted assertion or document an executable replacement witness.")
                             (anti-evasion-warning := "Do NOT evade by wrapping assertions inside conditional guards, skip directives, or silent deletion.")
                             (excerpt := (string-append "removed=" (number->string rem-a) " added=" (number->string add-a))))
                         findings)))
           (when (> rem-f add-f)
             (set! findings
                   (cons (.o (file := file)
                             (language := lang)
                             (surface := surface)
                             (line := line-f)
                             (subdomain := "de-g2-core")
                             (pack-id := "de-g2-core")
                             (hallucination-class := "floor-weakening")
                             (rule := "diff-deleted-governance-floor")
                             (anti-pattern-id := "AP-02")
                             (detail := (string-append "Diff removes " (number->string (- rem-f add-f))
                                                       " Band-5 governance floor guard(s) without preserving them"))
                             (c2-replacement := "Preserve actionAuthorized: false and governance floor invariants.")
                             (anti-evasion-warning := "Do NOT weaken or delete zero-authority or countermodel floor guards.")
                             (excerpt := (string-append "removed=" (number->string rem-f) " added=" (number->string add-f))))
                         findings)))
           (when (> rem-g add-g)
             (set! findings
                   (cons (.o (file := file)
                             (language := lang)
                             (surface := surface)
                             (line := line-g)
                             (subdomain := "de-g2-core")
                             (pack-id := "de-g2-core")
                             (hallucination-class := "floor-weakening")
                             (rule := "diff-deleted-formal-guard-or-countermodel")
                             (anti-pattern-id := "AP-02")
                             (detail := (string-append "Diff deletes " (number->string (- rem-g add-g))
                                                       " formal (guard ...) or @countermodel witness(es) without replacement"))
                             (c2-replacement := "Keep formal guards and @countermodel witnesses intact or replace with stronger verified witnesses.")
                             (anti-evasion-warning := "Do NOT drop formal guards or countermodel witnesses to make models vacuously pass.")
                             (excerpt := (string-append "removed=" (number->string rem-g) " added=" (number->string add-g))))
                         findings)))))
       file-totals)
      (reverse findings))))

;; ── Causal Trajectory Chain, Temporal Causality & Competing Hypotheses ─────

(def (build-competing-hypotheses findings)
  (if (null? findings)
    (list (.o (hypothesis-id := "hyp:clean-diff-under-active-packs")
              (status := "supported-under-bounded-packs")
              (summary := "No G2 or active subdomain rule-pack defects observed across audited Git diff surfaces.")
              (open-question := "Are additional subdomain rule packs or formal models required for domain-specific invariants?"))
          (.o (hypothesis-id := "hyp:unmodeled-subdomain-risk")
              (status := "open-competing")
              (summary := "Passing syntactic/structural G2 packs does not prove absence of deep semantic or protocol defects.")
              (open-question := "Dispatch independent multi-lens AI review and Quint/Lean formal oracles to test semantic invariants.")))
    (let ((has-del-assert? (ormap (lambda (f) (equal? (.get f rule) "diff-deleted-assertion")) findings))
          (has-fallback? (ormap (lambda (f) (equal? (.get f hallucination-class) "silent-fallback")) findings))
          (hyps '()))
      (when has-del-assert?
        (set! hyps
              (append hyps
                      (list (.o (hypothesis-id := "hyp:unwitnessed-floor-weakening")
                                (status := "contradicts-admission")
                                (summary := "Deleted assertions without in-file replacement may weaken the verification floor.")
                                (open-question := "Was the assertion accidentally dropped or intentionally relocated to another tested module?"))
                            (.o (hypothesis-id := "hyp:cross-file-assertion-relocation")
                                (status := "competing-unverified")
                                (summary := "Assertions may have moved to a dedicated test module during refactoring.")
                                (open-question := "Provide an executable witness linking the removed assertion to its new test coverage."))))))
      (when has-fallback?
        (set! hyps
              (append hyps
                      (list (.o (hypothesis-id := "hyp:silent-error-swallowing")
                                (status := "contradicts-admission")
                                (summary := "Fallback default or catch block may mask real boundary errors.")
                                (open-question := "Does a typed error or fail-closed boundary preserve caller safety?"))
                            (.o (hypothesis-id := "hyp:intentional-boundary-default")
                                (status := "competing-unverified")
                                (summary := "The default may represent an explicit optional domain value rather than an error.")
                                (open-question := "Make the Option/typed contract explicit or attach a DE F3 guard-probe witness."))))))
      (if (null? hyps)
        (list (.o (hypothesis-id := "hyp:rule-pack-violation")
                  (status := "contradicts-admission")
                  (summary := "Active DE G2 or subdomain rule-pack findings block admission until repaired or witnessed.")
                  (open-question := "Inspect C2 repair directives and resolve each finding with an executable witness.")))
        hyps))))

(def (build-causal-trajectory base-ref staged-only? pack-ids base-f unstaged-f staged-f all-f funflow-receipts)
  (let* ((ev-base
          (.o (:: @ CausalEvent.)
              (event-id := "evt:1:base-ref-diff")
              (epoch := 1)
              (stage := "git-base-ref-observation")
              (surface := "base-ref")
              (rule-packs := pack-ids)
              (findings-count := (length base-f))
              (causal-parents := '())
              (summary := (string-append "Observed base-ref diff relative to " base-ref))
              (action-authorized? := #f)))
         (ev-unstaged
          (.o (:: @ CausalEvent.)
              (event-id := "evt:2:unstaged-diff")
              (epoch := 2)
              (stage := "git-unstaged-observation")
              (surface := "unstaged")
              (rule-packs := pack-ids)
              (findings-count := (length unstaged-f))
              (causal-parents := '("evt:1:base-ref-diff"))
              (summary := (if staged-only? "Skipped unstaged surface (--staged mode)" "Observed working-tree unstaged git diff"))
              (action-authorized? := #f)))
         (ev-staged
          (.o (:: @ CausalEvent.)
              (event-id := "evt:3:staged-diff")
              (epoch := 3)
              (stage := "git-staged-observation")
              (surface := "staged")
              (rule-packs := pack-ids)
              (findings-count := (length staged-f))
              (causal-parents := '("evt:2:unstaged-diff"))
              (summary := "Observed pre-commit staged git diff (--cached)")
              (action-authorized? := #f)))
         (ev-eval
          (.o (:: @ CausalEvent.)
              (event-id := "evt:4:scheme-rule-pack-eval")
              (epoch := 4)
              (stage := "scheme-poo-rule-pack-derivation")
              (surface := "composed")
              (rule-packs := pack-ids)
              (findings-count := (length all-f))
              (causal-parents := '("evt:1:base-ref-diff" "evt:2:unstaged-diff" "evt:3:staged-diff"))
              (summary := (string-append "Evaluated " (number->string (length pack-ids))
                                         " monotone POO rule pack(s); funflow-receipts="
                                         (number->string (length funflow-receipts))))
              (action-authorized? := #f)))
         (events (list ev-base ev-unstaged ev-staged ev-eval))
         (happens-before
          (list '("evt:1:base-ref-diff" "evt:2:unstaged-diff")
                '("evt:2:unstaged-diff" "evt:3:staged-diff")
                '("evt:1:base-ref-diff" "evt:4:scheme-rule-pack-eval")
                '("evt:2:unstaged-diff" "evt:4:scheme-rule-pack-eval")
                '("evt:3:staged-diff" "evt:4:scheme-rule-pack-eval")))
         (lineage
          (map (lambda (f idx)
                 (let ((parent-evt
                        (cond
                         ((equal? (.get f surface) "staged") "evt:3:staged-diff")
                         ((equal? (.get f surface) "unstaged") "evt:2:unstaged-diff")
                         (else "evt:1:base-ref-diff"))))
                   (.o (finding-id := (string-append "g2-" (number->string (+ idx 1))))
                       (causal-ancestor := parent-evt)
                       (surface := (.get f surface))
                       (subdomain := (.get f subdomain))
                       (rule := (.get f rule))
                       (location := (string-append (.get f file) ":" (number->string (.get f line)))))))
               all-f (iota (length all-f)))))
    (.o (events := events)
        (temporal-causality := (.o (schema := "lambda-aitia.temporal-causality.v1")
                                   (acyclic? := #t)
                                   (happens-before := happens-before)
                                   (causal-lineage := lineage)
                                   (competing-hypotheses := (build-competing-hypotheses all-f))
                                   (reopened-obligations := (if (null? all-f) '() '("SWE-084" "SWE-146")))
                                   (action-authorized? := #f))))))

;; ── Pure POO Entry Point ───────────────────────────────────────────────────

(def (gitops-diff-defense-audit input)
  (let* ((base-ref (opt-slot input 'base-ref "HEAD"))
         (staged-only? (and (opt-slot input 'staged-only? #f) #t))
         (staged-diff (opt-slot input 'staged-diff ""))
         (unstaged-diff (opt-slot input 'unstaged-diff ""))
         (base-ref-diff (opt-slot input 'base-ref-diff ""))
         (extra-packs
          (map (lambda (p)
                 (if (and (object? p) (eq? (opt-slot p 'kind #f) 'lambda-aitia.rule-pack.v1))
                   p
                   (rule-pack-from-descriptor p)))
               (opt-slot input 'rule-packs '())))
         (funflow-receipts (opt-slot input 'funflow-receipts '()))
         (composed (compose-rule-packs de-g2-core-rule-pack extra-packs))
         (pack-ids (map (lambda (p) (.get p pack-id)) (.get composed packs)))
         (staged-f (audit-unified-diff-surface staged-diff "staged" composed))
         (unstaged-f (if staged-only? '() (audit-unified-diff-surface unstaged-diff "unstaged" composed)))
         (base-f (if (and (not staged-only?) (not (equal? base-ref "HEAD")))
                   (audit-unified-diff-surface base-ref-diff "base-ref" composed)
                   '()))
         (raw-all (append staged-f unstaged-f base-f))
         (all-f
          (map (lambda (f idx)
                 (.o (id := (string-append "g2-" (number->string (+ idx 1))))
                     (file := (.get f file))
                     (language := (.get f language))
                     (surface := (.get f surface))
                     (line := (.get f line))
                     (subdomain := (.get f subdomain))
                     (pack-id := (.get f pack-id))
                     (hallucination-class := (.get f hallucination-class))
                     (rule := (.get f rule))
                     (anti-pattern-id := (.get f anti-pattern-id))
                     (detail := (.get f detail))
                     (c2-replacement := (.get f c2-replacement))
                     (anti-evasion-warning := (.get f anti-evasion-warning))
                     (excerpt := (.get f excerpt))))
               raw-all (iota (length raw-all))))
         (count-class
          (lambda (cls)
            (length (filter (lambda (f) (equal? (.get f hallucination-class) cls)) all-f))))
         (diff-del-count
          (length (filter (lambda (f) (string-prefix? "diff-deleted-" (.get f rule))) all-f)))
         (passed? (null? all-f))
         (decision (if passed? "ADMIT" "REFUSE"))
         (traj (build-causal-trajectory base-ref staged-only? pack-ids base-f unstaged-f staged-f all-f funflow-receipts)))
    (.o (schema := "lambda-aitia.de-g2-diff-audit.v1")
        (engine-owner := "scheme-poo-ascent-framework")
        (passed? := passed?)
        (decision := decision)
        (staged-only? := staged-only?)
        (base-ref := base-ref)
        (staged-findings-count := (length staged-f))
        (unstaged-findings-count := (+ (length unstaged-f) (length base-f)))
        (base-ref-findings-count := (length base-f))
        (diff-deleted-assertions-count := diff-del-count)
        (total-findings := (length all-f))
        (counts-by-class := (.o (silent-fallback := (count-class "silent-fallback"))
                                (floor-weakening := (count-class "floor-weakening"))
                                (redundant-defensive-glue := (count-class "redundant-defensive-glue"))
                                (fabricated-evidence := (count-class "fabricated-evidence"))
                                (subdomain-invariant-violation := (count-class "subdomain-invariant-violation"))))
        (rule-packs-applied := pack-ids)
        (core-floor-preserved? := #t)
        (bounded-divergence-mode := "monotone-additive-subdomain-packs")
        (g2-findings := all-f)
        (causal-trajectory := (.get traj events))
        (temporal-causality := (.get traj temporal-causality))
        (funflow-receipts-count := (length funflow-receipts))
        (action-authorized? := #f))))
