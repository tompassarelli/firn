#lang racket/base

(require racket/string
         racket/list
         racket/math
         racket/path
         racket/system
         racket/file
         racket/port
         "util.rkt")

(provide node-edges)

(define (handle-host-rebuild leaf)
  ;; leaf may be "current" or "<host>" or "<host>+skip" (legacy alias sentinel)
  (define-values (host-token skip-checks?)
    (cond
      [(regexp-match #rx"^([^+]+)\\+skip$" leaf)
       => (λ (m) (values (cadr m) #t))]
      [else (values leaf #f)]))
  (define host (cond [(equal? host-token "current") (current-hostname)]
                     [else host-token]))

  ;; cd to ROOT so subshells (firn-build, firn-validate, nh) see the repo
  ;; even when the user invoked `firn rebuild` from another directory.
  (parameterize ([current-directory ROOT])
    (handle-host-rebuild* host skip-checks?)))

;; Modules whose own flake.nix references an absolute path outside the
;; flake source tree (e.g. gjoa's gitignored 5GB engine/ dir) and so
;; can't evaluate under pure-eval. If the host enables one of these,
;; firn rebuild auto-adds --impure so the rebuild doesn't die with the
;; cryptic "access to absolute path '/home' is forbidden" trace.
;;
;; NOTE: enabling a module in this list means a *full system-package
;; rebuild* of that project — gjoa is ~45 min cold. Daily development of
;; gjoa happens OUTSIDE firn rebuild, in the gjoa dev shell via
;; `mach build faster` (~30s). Only flip gjoa.enable to #t when you
;; actually want a release-quality binary installed system-wide.
(define IMPURE-MODULES '("gjoa"))

(define (host-impure-modules host)
  (define host-nix (in-repo "hosts" host "configuration.nix"))
  (cond
    [(not (file-exists? host-nix)) '()]
    [else
     (define text (file->string host-nix))
     (for/list ([m (in-list IMPURE-MODULES)]
                #:when
                (regexp-match?
                 (regexp
                  (format "(myConfig\\.modules\\.~a\\.enable|[ \t\n;{]~a\\.enable)[ \t]*=[ \t]*true"
                          m m))
                 text))
       m)]))

(define (host-needs-impure? host)
  (pair? (host-impure-modules host)))

;; Post-activation machine-drift gate (firn: gate once per rebuild, never poll
;; per session). The activation that just ran heals known drift (registerMcpServers
;; etc.); this verifies the heal actually took. Advisory by design — the system has
;; already switched, so a finding is surfaced loudly but never fails the rebuild.
(define (run-drift-check)
  (define checker (in-repo "scripts" "agent-config-check.sh"))
  (when (file-exists? checker)
    (printf "┌─ agent harness (--local)\n") (flush-output)
    (cond
      [(sh (path->string checker) "--local")
       (printf "└─ ✓ agent harness — shared, Claude, Codex, and North state match\n")]
      [else
       (printf "└─ ⚠ agent harness drift (see above) — system already switched; fix config + re-run `firn rebuild`\n")])
    (flush-output)))

(define (handle-host-rebuild* host skip-checks?)
  ;; Line-buffer so step headers print before each child process writes
  ;; to fd1. Otherwise (block-buffered pipes) headers appear after their
  ;; child output, making the sequence hard to read.
  (with-handlers ([exn:fail? (λ (_) (void))])
    (file-stream-buffer-mode (current-output-port) 'line))
  ;; Auto-impure when the host enables a module whose flake intrinsically
  ;; reads paths outside its source tree (currently: gjoa). For these
  ;; modules a `firn rebuild` is a full system-package rebuild — for gjoa,
  ;; ~45 minutes — and is intended only for release-time installs.
  (define auto-impure?
    (and host (host-needs-impure? host)))
  (when auto-impure?
    (printf "firn rebuild: passing --impure (host enables: ~a)\n"
            (string-join (host-impure-modules host) ", "))
    (printf "             this triggers a full ~~45 min Firefox compile.\n")
    (printf "             for daily gjoa dev use the gjoa dev shell + mach build faster.\n"))
  ;; Refresh sudo credentials upfront so the activation phase (which runs
  ;; after several minutes of build) doesn't wake the user for a password.
  ;; `sudo -v` validates and extends the cached timestamp; subsequent
  ;; sudo invocations within ~5 min (default sudo timeout) skip the prompt.
  (define on-linux? (not (equal? "Darwin" (string-trim (sh-out "uname" "-s")))))
  (define passwordless? #f)
  (when on-linux?
    ;; NOPASSWD-aware: when the scoped sudoers rule covers nixos-rebuild
    ;; (rebuild-nopasswd module), no credential cache is needed — skip the
    ;; interactive -v gate entirely so agent runs never cold-start on a prompt.
    (set! passwordless? (sh "sudo" "-n" "true" "2>/dev/null"))
    ;; quiet probe: blanket NOPASSWD only; no stdout side effects (the old
    ;; list-generations probe dumped 65 generations into the user's terminal).
    (unless passwordless?
      (set! passwordless?
        (parameterize ([current-output-port (open-output-nowhere)]
                       [current-error-port (open-output-nowhere)])
          (sh "sudo" "-n" "true"))))
    (unless passwordless?
      (printf "── sudo: caching credentials upfront (no prompt during build)\n")
      (flush-output)
      (unless (sh "sudo" "-v")
        (eprintf "firn rebuild: sudo authentication failed\n") (exit 1))))

  ;; Keep sudo timestamp warm for the duration of the build by re-validating
  ;; every 60 seconds in the background. nh's activation phase can land
  ;; anywhere from 30s (cached) to 45min (full firefox rebuild) later.
  (define sudo-keepalive
    (and on-linux?
         (thread
           (lambda ()
             (let loop ()
               (sleep 60)
               (parameterize ([current-output-port (open-output-nowhere)]
                              [current-error-port (open-output-nowhere)])
                 (system* (or (find-executable-path "sudo") "/usr/bin/sudo") "-n" "-v"))
               (loop))))))

  ;; ─── Phase helpers ───────────────────────────────────────────────────
  ;; Each phase prints a banner, runs the body, then OK/FAIL with elapsed.
  ;; Long phases (nh switch) stream child output live.
  (define total-start (current-inexact-milliseconds))
  (define lock-path (in-repo "flake.lock"))
  (define lock-backup #f)
  (define provisional-lock? #f)
  (define (restore-provisional-lock!)
    (when (and provisional-lock? lock-backup (file-exists? lock-backup))
      ;; A commit hook may fail after `git add`; restore both index and worktree.
      (sh "git" "-C" ROOT "reset" "--quiet" "HEAD" "--" "flake.lock")
      (copy-file lock-backup lock-path #t)
      (set! provisional-lock? #f)
      (eprintf "firn rebuild: restored previous flake.lock after failed verification.\n")))
  (define (discard-lock-backup!)
    (when (and lock-backup (file-exists? lock-backup)) (delete-file lock-backup))
    (set! lock-backup #f))
  (define (fmt-elapsed ms)
    (cond [(< ms 1000) (format "~ams" (exact-round ms))]
          [(< ms 60000) (format "~as" (exact-round (/ ms 1000.0)))]
          [else (format "~am~as"
                        (exact-floor (/ ms 60000))
                        (exact-round (/ (modulo (exact-round ms) 60000) 1000.0)))]))
  (define (phase name body)
    (define start (current-inexact-milliseconds))
    (printf "┌─ ~a\n" name) (flush-output)
    (define ok? (with-handlers ([exn:fail? (λ (_) #f)]) (body)))
    (define elapsed (- (current-inexact-milliseconds) start))
    (cond
      [ok? (printf "└─ ✓ ~a (~a)\n" name (fmt-elapsed elapsed))]
      [else
       (restore-provisional-lock!)
       (discard-lock-backup!)
       (printf "└─ ✗ ~a (~a)\n" name (fmt-elapsed elapsed))
       (eprintf "firn rebuild: ~a failed; aborting.\n" name)
       (exit 1)])
    (flush-output))

  ;; Normal rebuilds refresh local inputs provisionally. The old lock remains
  ;; recoverable until generation, validation, and a host closure build prove
  ;; the new sources. --skip-checks intentionally keeps the committed lock: it
  ;; may switch an already-known generation, but can never commit a new pointer.
  (cond
    [skip-checks?
     (printf "── local inputs unchanged (--skip-checks cannot refresh or commit unverified pointers)\n")]
    [else
     (set! lock-backup (make-temporary-file "firn-flake-lock-~a"))
     (copy-file lock-path lock-backup #t)
     (phase "local inputs (provisional)"
       (λ ()
         (define ok? (sh (path->string (in-repo "scripts" "firn-sync-local-inputs")) "--provisional"))
         (when ok?
           (set! provisional-lock?
             (not (sh "git" "-C" ROOT "diff" "--quiet" "--" "flake.lock"))))
         ok?))])

  (unless skip-checks?
    ;; Step 1: regenerate any out-of-date .nix from .bnix sources.
    (phase "firn-build"
      (λ () (sh (path->string (in-repo "scripts" "firn-build")))))

    ;; Step 1b: warn about untracked .bnix/.nix — Nix can't see them.
    (define untracked
      (let ([s (sh-out "git" "-C" ROOT "ls-files" "--others" "--exclude-standard")])
        (filter (λ (p) (regexp-match? #rx"\\.(bnix|rkt|nix)$" p))
                (string-split s "\n"))))
    (unless (null? untracked)
      (eprintf "✗ untracked files invisible to Nix — git add them first:\n")
      (for ([p (in-list untracked)]) (eprintf "  ~a\n" p))
      (restore-provisional-lock!)
      (discard-lock-backup!)
      (exit 1))

    ;; Step 2: validate paths and value types against the schema.
    (phase "firn-validate"
      (λ () (sh (path->string (in-repo "scripts" "firn-validate")))))

    ;; Step 2b: flake input purity.
    (if auto-impure?
        (printf "── flake-input-purity skipped (--impure)\n")
        (phase "flake-input-purity"
          (λ ()
            (define purity-issues (flake-input-purity-violations))
            (if (null? purity-issues)
                #t
                (begin
                  (eprintf "  flake has absolute-path inputs that break pure eval:\n")
                  (for ([line (in-list purity-issues)]) (eprintf "  ~a\n" line))
                  (eprintf "  fix: publish to a git remote (github:owner/repo), or override locally with --override-input.\n")
                  #f)))))

    ;; Step 2c: build the exact host closure before the derived lock commit.
    ;; The subsequent switch reuses this result, so the gate adds integrity,
    ;; not a second system build.
    (phase "source/package smoke"
      (λ ()
        (define attr
          (if on-linux?
              (format ".#nixosConfigurations.~a.config.system.build.toplevel" host)
              (format ".#darwinConfigurations.~a.system" host)))
        (apply sh (append (list "nix" "build" "--no-link" attr)
                          (if auto-impure? (list "--impure") '())))))

    ;; Only a verified pointer earns a mechanical commit. No-op refreshes do
    ;; not create empty commits.
    (when provisional-lock?
      (phase "commit verified local inputs"
        (λ ()
          (and (sh "git" "-C" ROOT "add" "flake.lock")
               (sh "git" "-C" ROOT "commit" "--only" "-m"
                   "refresh verified local inputs" "--" "flake.lock"))))
      (set! provisional-lock? #f))
    (discard-lock-backup!))

  ;; Step 3: actual rebuild. Dispatch by platform.
  (printf "┌─ rebuild\n") (flush-output)
  (define rebuild-start (current-inexact-milliseconds))
  (define on-darwin?
    (equal? "Darwin" (string-trim (sh-out "uname" "-s"))))
  (define extra (if auto-impure? (list "--impure") '()))
  (define rc
    (cond
      [on-darwin?
       (define flake-target (if host (string-append ROOT "#" host) ROOT))
       (apply sh (append (list "sudo" "darwin-rebuild" "switch" "--flake" flake-target)
                         extra))]
      [(find-executable-path "nh")
       ;; nh forwards everything after `--` to `nix build`, which is where
       ;; --impure lives.
       (define nh-tail (if (null? extra) '() (cons "--" extra)))
       (apply system* (find-executable-path "nh")
              (append (list "os" "switch" ROOT)
                      (if host (list "-H" host) '())
                      nh-tail))]
      [else
       (define flake-target (if host (string-append ROOT "#" host) ROOT))
       (apply sh (append (list "sudo" "nixos-rebuild" "switch" "--flake" flake-target)
                         extra))]))
  (when sudo-keepalive (kill-thread sudo-keepalive))
  (define rebuild-elapsed (- (current-inexact-milliseconds) rebuild-start))
  (define total-elapsed (- (current-inexact-milliseconds) total-start))
  (cond
    [(not rc)
     (printf "└─ ✗ rebuild (~a)\n" (fmt-elapsed rebuild-elapsed))
     (printf "\n  total: ~a — failed\n\n" (fmt-elapsed total-elapsed))
     (exit 1)]
    [on-darwin?
     (printf "└─ ✓ rebuild (~a)\n" (fmt-elapsed rebuild-elapsed))
     (printf "\n  ✓ rebuild complete — total ~a\n\n" (fmt-elapsed total-elapsed))]
    [else
     (printf "└─ ✓ rebuild (~a)\n" (fmt-elapsed rebuild-elapsed))
     (define gens (sh-out "nixos-rebuild" "list-generations"))
     (define cur-line
       (for/or ([line (in-list (string-split gens "\n"))]
                #:when (regexp-match? #rx"current" line))
         line))
     (define gen
       (and cur-line
            (let ([n (car (string-split (string-trim cur-line)))])
              (and (regexp-match? #rx"^[0-9]+$" n) n))))
     (when gen
       (sh "git" "-C" ROOT "tag" "-f" (string-append "gen-" gen) "HEAD"))
     (printf "\n  ✓ rebuild complete — total ~a~a\n\n"
             (fmt-elapsed total-elapsed)
             (if gen (format ", tagged gen-~a" gen) ""))])
  ;; Both success paths (darwin + linux) fall through here; the failure branch
  ;; exits above. Verify machine state once, now that activation has run.
  (run-drift-check))

;; firn host impact [<host>]  — dry-run rebuild impact prediction

(define (handle-host-impact leaf)
  (define host (cond [(equal? leaf "current") (current-hostname)]
                     [else leaf]))
  (printf ">> rebuild impact (~a)\n" host)
  (unless (sh (path->string (in-repo "scripts" "firn-rebuild-impact")) host)
    (eprintf "firn host impact: failed.\n") (exit 1)))

(define node-edges
  (list
   (walk-edge "host" "rebuild" "<host>" 'current-host
              handle-host-rebuild
              "refresh local inputs → build → validate → switch → tag generation")
   (walk-edge "host" "impact" "[<host>]" 'current-host
              handle-host-impact
              "dry-run impact prediction (what will rebuild, estimated time)")))
