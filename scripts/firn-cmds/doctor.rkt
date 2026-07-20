#lang racket/base

;; firn-cmds/doctor — repo health check. Walks a battery of
;; common-trouble checks and prints a status report.
;;
;; Checks:
;;   1. Untracked .bnix/.nix files (invisible to Nix's flake reader)
;;   2. Stale .nix files (sibling .bnix newer)
;;   3. Schema cache freshness (schema-producing input fingerprints)
;;   4. Orphaned modules (not enabled directly by any host or via tags)
;;   5. Validator clean
;;   6. Flake inputs use no absolute paths (pure-eval safe)
;;
;; Exits 0 if all pass, 1 if any fail.

(require racket/file
         racket/list
         racket/path
         racket/string
         racket/system
         "util.rkt"
         (only-in "list.rkt" live-modules))

(provide node-edges)

(define (check-status name predicate-thunk)
  ;; predicate-thunk returns (values pass? detail-lines)
  (define-values (ok? details) (predicate-thunk))
  (cond
    [ok?
     (printf "  ✓ ~a\n" name)
     #t]
    [else
     (printf "  ✗ ~a\n" name)
     (for ([line (in-list details)])
       (printf "      ~a\n" line))
     #f]))

(define (check-warning name predicate-thunk)
  ;; Like check-status but non-blocking — prints a warning, always returns #t.
  (define-values (ok? details) (predicate-thunk))
  (cond
    [ok?
     (printf "  ✓ ~a\n" name)
     #t]
    [else
     (printf "  ⚠ ~a\n" name)
     (for ([line (in-list details)])
       (printf "      ~a\n" line))
     #t]))

;; ---------- individual checks ----------

(define (check-untracked)
  (define s (sh-out "git" "-C" ROOT "ls-files" "--others" "--exclude-standard"))
  (define files
    (filter (λ (p) (regexp-match? #rx"\\.(bnix|nix)$" p))
            (string-split s "\n")))
  (cond
    [(null? files) (values #t '())]
    [else (values #f (cons "untracked .bnix/.nix files (invisible to Nix):"
                           (map (λ (f) (string-append "  " f)) files)))]))

(define (relative-to-root root p)
  (path->string (find-relative-path (simplify-path root) (simplify-path p))))

(define (build-walk-directory? root p)
  ;; Keep this traversal aligned with scripts/firn-build. In particular,
  ;; never descend into the direnv input mirror: it contains another copy of
  ;; this repository and made doctor report every resolver input twice.
  (define rel (relative-to-root root p))
  (not (or (regexp-match? #rx"^(?:\\.direnv|\\.git|result[^/]*|scripts|tests)(?:/|$)" rel)
           (regexp-match? #rx"^docs/fixtures(?:/|$)" rel))))

(define (generated-bnix-source? root p)
  (define rel (relative-to-root root p))
  (and (file-exists? p)
       (regexp-match? #rx"\\.bnix$" rel)
       ;; enabled-tags.bnix is resolver input, not a compilable module.
       (not (regexp-match? #rx"(?:^|/)enabled-tags\\.bnix$" rel))))

(define (check-stale-nix [root ROOT])
  ;; Use the same source set as firn-build: every .bnix except pruned fixture,
  ;; build-result, direnv, and resolver-input paths.
  (define stale '())
  (define missing '())
  (for ([f (in-directory root (λ (p) (build-walk-directory? root p)))])
    (define s (path->string f))
    (when (generated-bnix-source? root f)
      (let ()
        (define nix-path (regexp-replace #rx"\\.bnix$" s ".nix"))
        (cond
          [(not (file-exists? nix-path))
           (set! missing (cons (relative-to-root root f) missing))]
          [(< (file-or-directory-modify-seconds nix-path)
              (file-or-directory-modify-seconds f))
           (set! stale (cons (relative-to-root root f) stale))]))))
  (define issues '())
  (when (pair? missing)
    (set! issues
          (append issues
                  (list (format "missing .nix output for: ~a" (length missing)))
                  (map (λ (f) (string-append "  " f)) (sort missing string<?)))))
  (when (pair? stale)
    (set! issues
          (append issues
                  (list (format "stale .nix (older than .bnix): ~a" (length stale)))
                  (map (λ (f) (string-append "  " f)) (sort stale string<?)))))
  (cond
    [(null? issues) (values #t '())]
    [else (values #f issues)]))

(define (current-schema-fingerprint root mode)
  (define helper (build-path root "scripts" "firn-schema-input-fingerprint"))
  (define lock (build-path root "flake.lock"))
  (define beagle-path
    (or (getenv "BEAGLE_PATH") (build-path root ".." "beagle")))
  (cond
    [(not (file-exists? helper))
     (values #f "" (format "fingerprint helper missing: ~a" helper))]
    [(not (file-exists? lock))
     (values #f "" "flake.lock is missing")]
    [else
     (define out (open-output-string))
     (define err (open-output-string))
     (define ok?
       (parameterize ([current-output-port out] [current-error-port err])
         (system* (path->string helper)
                  "--mode" mode
                  "--lock" (path->string lock)
                  "--beagle-path" (path->string beagle-path))))
     (values ok?
             (string-trim (get-output-string out))
             (string-trim (get-output-string err)))]))

(define (check-schema-cache* schema-name fingerprint-name mode refresh-command [root ROOT])
  (define cache-dir (build-path root ".beagle-cache"))
  (define schema-path (build-path cache-dir schema-name))
  (define fingerprint-path (build-path cache-dir fingerprint-name))
  (cond
    [(not (file-exists? schema-path))
     (values #f (list (format "schema cache missing — run ~a" refresh-command)))]
    [(not (file-exists? fingerprint-path))
     (values #f (list (format "schema input fingerprint missing — run ~a" refresh-command)))]
    [else
     (define-values (ok? current error) (current-schema-fingerprint root mode))
     (cond
       [(not ok?)
        (values #f (list (format "could not fingerprint schema inputs: ~a" error)))]
       [(equal? current (string-trim (file->string fingerprint-path)))
        (values #t '())]
       [else
        (values #f
                (list (format "schema-producing inputs changed — run ~a"
                              refresh-command)))])]))

(define (check-schema-cache)
  (check-schema-cache* "schema.json" "schema.inputs.sha256"
                       "nixos" "firn-extract-schema"))

(define (darwin-configured? [root ROOT])
  (define source
    (cond
      [(file-exists? (build-path root "flake.bnix")) (build-path root "flake.bnix")]
      [(file-exists? (build-path root "flake.rkt")) (build-path root "flake.rkt")]
      [else #f]))
  (and source
       (with-handlers ([exn:fail? (λ (_) #f)])
         (regexp-match? #rx"darwinConfigurations" (file->string source)))))

(define (check-darwin-schema-cache)
  (cond
    [(not (darwin-configured?)) (values #t '())]
    [else (check-schema-cache* "schema-darwin.json" "schema-darwin.inputs.sha256"
                               "darwin" "firn-extract-schema --darwin")]))

(define (module-referenced? m live)
  ;; A module is "referenced" if either:
  ;;   - it's in the live set computed by list.rkt's live-modules
  ;;     (tag-resolved active modules across all hosts), OR
  ;;   - some host's configuration.bnix or enabled-tags.bnix mentions
  ;;     myConfig.modules.<m>.enable / -m / +m directly. The grep is a
  ;;     safety net for direct references that the AST-based path
  ;;     extractor in util.rkt can't see (it reads via Racket's reader,
  ;;     which stumbles on bnix-specific syntax in some files).
  ;; Excludes _generated-enables.bnix — that's just the resolver output.
  (cond
    [(hash-has-key? live m) #t]
    [else
     (define dotted-re (pregexp (format "modules\\.~a[.\\s)]" (regexp-quote m))))
     (define tag-edit-re
       (pregexp (format "[+\\-]~a[\\s\\]]" (regexp-quote m))))
     ;; grep-files walks both .rkt and .nix; we want host source only.
     (or (pair? (filter (λ (p) (not (regexp-match? #rx"_generated-enables\\." p)))
                        (grep-files "hosts" dotted-re)))
         (pair? (filter (λ (p) (regexp-match? #rx"enabled-tags\\.bnix$" p))
                        (grep-files "hosts" tag-edit-re))))]))

(define (list->hash xs)
  (define h (make-hash))
  (for ([x (in-list xs)]) (hash-set! h x #t))
  h)

(define (check-orphaned-modules)
  (define live (list->hash (live-modules)))
  (define orphans
    (for/list ([m (in-list (modules))]
               #:when (not (module-referenced? m live)))
      m))
  (cond
    [(null? orphans) (values #t '())]
    [else (values #f (cons (format "~a unreferenced module(s) (config rot?):" (length orphans))
                           (map (λ (m) (string-append "  modules/" m "/"))
                                orphans)))]))

(define (check-flake-input-purity)
  ;; Flake inputs declared as "path:/abs/..." resolve to an absolute filesystem
  ;; path. Pure-eval (default for flakes) forbids reading outside the flake's
  ;; own source tree, so any module that *references* such an input — directly
  ;; or via flake-lock resolution — fails the rebuild with: "access to absolute
  ;; path '/...' is forbidden in pure evaluation mode". firn-validate is
  ;; schema-only and can't see this; firn rebuild runs the same check
  ;; pre-flight.
  (define offenders (flake-input-purity-violations))
  (cond
    [(null? offenders) (values #t '())]
    [else (values #f
                  (cons "absolute path: inputs break pure eval when referenced:"
                        (append offenders
                                (list "fix: publish to a git remote (github:owner/repo), or override locally with --override-input"))))]))

(define (check-validator)
  (define out (open-output-string))
  (define err (open-output-string))
  (define ok?
    (parameterize ([current-output-port out] [current-error-port err])
      (system* (path->string (in-repo "scripts" "firn-validate")))))
  (cond
    [ok? (values #t '())]
    [else
     (define lines (regexp-split #rx"\n" (get-output-string err)))
     (define filtered (filter (λ (l) (not (regexp-match? #rx"^\\s*$" l))) lines))
     (values #f (take filtered (min 5 (length filtered))))]))

;; ---------- main ----------

(define (handle-doctor _leaf)
  (printf "firn doctor: running checks on ~a\n\n"
          (if (path? ROOT) (path->string ROOT) ROOT))
  (define passes
    (list
     (check-status "no untracked .bnix/.nix files" check-untracked)
     (check-status ".nix outputs are up-to-date with .bnix sources" check-stale-nix)
     (check-status "schema cache is fresh" check-schema-cache)
     (check-status "darwin schema cache is fresh (if applicable)" check-darwin-schema-cache)
     (check-warning "no dead (unreferenced) modules" check-orphaned-modules)
     (check-status "flake inputs are pure-eval safe (no absolute paths)" check-flake-input-purity)
     (check-status "validator passes" check-validator)))
  (define total (length passes))
  (define passed (length (filter values passes)))
  (printf "\nfirn doctor: ~a/~a checks passed.\n" passed total)
  (exit (if (= passed total) 0 1)))

(define node-edges
  (list
   (walk-edge "repo" "doctor" "all" 'all
              handle-doctor
              "repo health check (untracked, stale, schema, orphans, validator)")
   (walk-edge "host" "doctor" "<host>" 'current-host
              handle-doctor
              "alias for repo doctor (host arg ignored)")))

(module+ test
  (require rackunit)

  (define scratch (make-temporary-file "firn-doctor-test~a" 'directory))
  (define (write-test-file relative [content ""])
    (define path (build-path scratch relative))
    (make-directory* (path-only path))
    (call-with-output-file path
      (λ (out) (display content out))
      #:exists 'truncate)
    path)

  (dynamic-wind
    void
    (λ ()
      ;; Every real build source has a sibling output.
      (for ([relative (in-list '("flake" "hardware-configuration"
                                 "modules/alpha/default"
                                 "hosts/whiterabbit/configuration"
                                 "template/hosts/my-machine/configuration"))])
        (write-test-file (string-append relative ".bnix"))
        (write-test-file (string-append relative ".nix")))

      ;; These are intentionally not build outputs and must never be reported.
      (for ([relative (in-list '("hosts/whiterabbit/enabled-tags.bnix"
                                 "template/hosts/my-machine/enabled-tags.bnix"
                                 ".direnv/flake-inputs/firn/hosts/x/enabled-tags.bnix"
                                 "result-source/modules/x/default.bnix"
                                 "scripts/fixture.bnix"
                                 "tests/fixture.bnix"
                                 "docs/fixtures/example.bnix"))])
        (write-test-file relative))

      (define-values (clean? clean-details) (check-stale-nix scratch))
      (check-true clean?)
      (check-equal? clean-details '())

      (write-test-file "modules/missing/default.bnix")
      (define-values (missing? missing-details) (check-stale-nix scratch))
      (check-false missing?)
      (check-not-false
       (member "  modules/missing/default.bnix" missing-details))

      (define stale-source (write-test-file "modules/stale/default.bnix"))
      (define stale-output (write-test-file "modules/stale/default.nix"))
      (define now (current-seconds))
      (file-or-directory-modify-seconds stale-source now)
      (file-or-directory-modify-seconds stale-output (- now 10))
      (define-values (stale? stale-details) (check-stale-nix scratch))
      (check-false stale?)
      (check-not-false
       (member "  modules/stale/default.bnix" stale-details))

      (write-test-file "flake.bnix" ":darwinConfigurations {}")
      (check-true (darwin-configured? scratch)))
    (λ () (delete-directory/files scratch #:must-exist? #f))))
