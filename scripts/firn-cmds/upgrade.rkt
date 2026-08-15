#lang racket/base

;; firn-cmds/upgrade — bump nixpkgs (and other flake inputs), re-extract
;; the schema, diff vs the previous snapshot, surface deprecated paths
;; that this repo references, and offer to apply auto-fixes.
;;
;; Pipeline:
;;   1. snapshot current schema → .beagle-cache/schema.json.prev
;;   2. nix flake update
;;   3. firn-extract-schema (regenerates .beagle-cache/schema.json)
;;   4. diff: list paths removed, paths added, type changes
;;   5. for each removed path that the repo references → flag (or
;;      auto-rename if the new schema has a clear replacement)
;;   6. run firn-validate to surface anything still broken

(require racket/string
         racket/list
         racket/path
         racket/file
         racket/system
         json
         "util.rkt")

(provide node-edges)

(define CACHE-DIR (build-path ROOT ".beagle-cache"))
(define SCHEMA-PATH (build-path CACHE-DIR "schema.json"))
(define PREV-SCHEMA-PATH (build-path CACHE-DIR "schema.json.prev"))

(define (load-schema-paths path)
  ;; Returns a hash: path-string → entry.
  (define h (make-hash))
  (when (file-exists? path)
    (for ([e (in-list (call-with-input-file path read-json))])
      (hash-set! h (hash-ref e 'name) e)))
  h)

;; Skip these dirs during descent — re-walking .git/.direnv (full of
;; /nix/store symlinks) is the slow part, and none hold .bnix sources.
(define (prune-dir? d)
  (define s (path->string d))
  (or (regexp-match? #rx"/\\.git($|/)" s)
      (regexp-match? #rx"/\\.direnv($|/)" s)
      (regexp-match? #rx"/\\.beagle-cache($|/)" s)
      (regexp-match? #rx"/\\.firn-build($|/)" s)
      (regexp-match? #rx"/result($|/)" s)))

;; Read every .bnix source ONCE — the diff checks 100s of removed paths,
;; so the old per-path tree walk was O(paths × repo). Now O(repo) once +
;; O(paths × files) in-memory. Cached for the whole upgrade run.
(define repo-bnix-cache #f)
(define (repo-bnix-files)
  (or repo-bnix-cache
      (begin
        (set! repo-bnix-cache
              (for/list ([f (in-directory ROOT (λ (d) (not (prune-dir? d))))]
                         #:when (let ([s (path->string f)])
                                  (and (regexp-match? #rx"\\.bnix$" s)
                                       (not (regexp-match? #rx"/scripts/" s))
                                       (not (regexp-match? #rx"/tests/" s)))))
                (cons (relative-to-repo f) (file->string f))))
        repo-bnix-cache)))

(define (find-references-in-repo path)
  (define re (regexp (regexp-quote path)))
  (sort
   (for/list ([entry (in-list (repo-bnix-files))]
              #:when (regexp-match? re (cdr entry)))
     (car entry))
   string<?))

(define (handle-repo-upgrade leaf)
  (define dry-run? (equal? leaf "dry-run"))

  ;; 1. Snapshot current schema (if exists)
  (printf ">> snapshotting current schema for diff...\n")
  (cond
    [(file-exists? SCHEMA-PATH)
     (copy-file SCHEMA-PATH PREV-SCHEMA-PATH #:exists-ok? #t)]
    [else
     (eprintf "firn upgrade: no current schema at ~a; skipping diff.\n" SCHEMA-PATH)])

  ;; 2. Update flake inputs (skipped on --dry-run)
  (cond
    [dry-run?
     (printf ">> [dry-run] would run: nix flake update\n")]
    [else
     (printf ">> nix flake update\n")
     ;; anchor to ROOT — `nix flake update` reads cwd's flake; lets `firn
     ;; update` run from anywhere (helpers self-anchor, schema paths absolute).
     (unless (parameterize ([current-directory ROOT]) (sh "nix" "flake" "update"))
       (eprintf "firn upgrade: nix flake update failed\n") (exit 1))])

  ;; 3. Re-extract schema
  (cond
    [dry-run?
     (printf ">> [dry-run] would run: firn-extract-schema\n")]
    [else
     (printf ">> firn-extract-schema\n")
     (unless (sh (path->string (in-repo "scripts" "firn-extract-schema")))
       (eprintf "firn upgrade: firn-extract-schema failed\n") (exit 1))])

  ;; 4. Diff schemas
  (cond
    [(not (file-exists? PREV-SCHEMA-PATH))
     (printf "(no previous schema to diff against)\n")]
    [else
     (printf "\n>> schema diff:\n")
     (define prev (load-schema-paths PREV-SCHEMA-PATH))
     (define cur  (load-schema-paths SCHEMA-PATH))
     (define removed (sort (filter (λ (p) (not (hash-has-key? cur p)))
                                   (hash-keys prev)) string<?))
     (define added (sort (filter (λ (p) (not (hash-has-key? prev p)))
                                 (hash-keys cur)) string<?))
     (define type-changed
       (sort
        (filter values
                (for/list ([(p e) (in-hash prev)]
                           #:when (let ([cur-e (hash-ref cur p #f)])
                                    (and cur-e
                                         (not (equal? (hash-ref e 't #f)
                                                      (hash-ref cur-e 't #f))))))
                  (list p (hash-ref e 't "?") (hash-ref (hash-ref cur p) 't "?"))))
        string<? #:key car))

     (printf "  removed: ~a   added: ~a   type-changed: ~a\n"
             (length removed) (length added) (length type-changed))

     ;; 5. Removed paths referenced in this repo are the actionable items
     (define this-repo-removed
       (filter-map
        (λ (p)
          (define refs (find-references-in-repo p))
          (and (pair? refs) (cons p refs)))
        removed))
     (cond
       [(null? this-repo-removed)
        (printf "\n  ✓ no removed paths are referenced in this repo.\n")]
       [else
        (printf "\n  ✗ ~a removed path(s) are referenced in this repo:\n"
                (length this-repo-removed))
        (for ([entry (in-list this-repo-removed)])
          (printf "    ~a\n" (car entry))
          (for ([f (in-list (cdr entry))])
            (printf "      → ~a\n" f)))])

     ;; Type changes also matter — same path but different type can break.
     (define this-repo-type-changed
       (filter-map
        (λ (tc)
          (define p (car tc))
          (define refs (find-references-in-repo p))
          (and (pair? refs) (list p (cadr tc) (caddr tc) refs)))
        type-changed))
     (when (pair? this-repo-type-changed)
       (printf "\n  ⚠ ~a type-changed path(s) referenced in this repo:\n"
               (length this-repo-type-changed))
       (for ([entry (in-list this-repo-type-changed)])
         (printf "    ~a: ~a → ~a\n"
                 (car entry) (cadr entry) (caddr entry))
         (for ([f (in-list (cadddr entry))])
           (printf "      → ~a\n" f))))])

  ;; 6. Run validator
  (cond
    [dry-run? (void)]
    [else
     (printf "\n>> firn-validate\n")
     (unless (sh (path->string (in-repo "scripts" "firn-validate")))
       (eprintf "firn upgrade: validation failed — check the schema diff above for clues\n")
       (exit 1))])

  (printf "\nfirn upgrade: done. Apply the committed lock with `firn rebuild`.\n"))

(define node-edges
  (list
   (walk-edge "repo" "upgrade" "now|dry-run" 'now
              handle-repo-upgrade
              "flake update + schema diff + validate (use dry-run leaf to preview)")))
