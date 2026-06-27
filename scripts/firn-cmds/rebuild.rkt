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

;; Post-activation machine-drift gate (firnos: gate once per rebuild, never poll
;; per session). The activation that just ran heals known drift (registerMcpServers
;; etc.); this verifies the heal actually took. Advisory by design — the system has
;; already switched, so a finding is surfaced loudly but never fails the rebuild.
(define (run-drift-check)
  (define checker (in-repo "scripts" "claude-config-check.sh"))
  (when (file-exists? checker)
    (printf "┌─ claude-config drift (--local)\n") (flush-output)
    (cond
      [(sh (path->string checker) "--local")
       (printf "└─ ✓ claude-config drift — machine matches the dotfile source of truth\n")]
      [else
       (printf "└─ ⚠ claude-config drift (see above) — system already switched; fix dotfiles + re-run `firn rebuild`\n")])
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
  (when on-linux?
    (printf "── sudo: caching credentials upfront (no prompt during build)\n")
    (flush-output)
    (unless (sh "sudo" "-v")
      (eprintf "firn rebuild: sudo authentication failed\n") (exit 1)))

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
       (printf "└─ ✗ ~a (~a)\n" name (fmt-elapsed elapsed))
       (eprintf "firn rebuild: ~a failed; aborting.\n" name)
       (exit 1)])
    (flush-output))

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
      (exit 1))

    ;; Step 2: validate paths and value types against the schema.
    (phase "firn-validate"
      (λ () (sh (path->string (in-repo "scripts" "firn-validate")))))

    ;; Step 2b: flake input purity.
    (cond
      [auto-impure?
       (printf "── flake-input-purity skipped (--impure)\n")]
      [else
       (phase "flake-input-purity"
         (λ ()
           (define purity-issues (flake-input-purity-violations))
           (cond
             [(null? purity-issues) #t]
             [else
              (eprintf "  flake has absolute-path inputs that break pure eval:\n")
              (for ([line (in-list purity-issues)]) (eprintf "  ~a\n" line))
              (eprintf "  fix: publish to a git remote (github:owner/repo), or override locally with --override-input.\n")
              #f])))]))

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
     ;; Attempt Claude diagnosis if claude CLI is available
     (define claude-bin (find-executable-path "claude"))
     (when claude-bin
       (printf ">> diagnosing with claude...\n")
       ;; Re-run nix build (eval-only) to capture the error message
       (define host-name (or host (current-hostname)))
       (define flake-ref (string-append ROOT "#nixosConfigurations." host-name
                                        ".config.system.build.toplevel"))
       (define nix-bin (find-executable-path "nix"))
       (when nix-bin
         (define err-port (open-output-string))
         (parameterize ([current-output-port (open-output-nowhere)]
                        [current-error-port err-port])
           (system* nix-bin "build" "--no-link" flake-ref))
         (define err-text (get-output-string err-port))
         (when (non-empty-string? err-text)
           ;; Take last 100 lines to keep the prompt manageable
           (define err-lines (string-split err-text "\n"))
           (define tail-lines (take-right err-lines (min 100 (length err-lines))))
           (define tail-text (string-join tail-lines "\n"))
           (define diag-port (open-output-string))
           (parameterize ([current-output-port diag-port])
             (system* claude-bin "-p"
                      (string-append
                       "A NixOS rebuild failed. Diagnose the root cause from this output. "
                       "Be concise — state the fix in 1-3 sentences.\n\n"
                       tail-text)))
           (define diagnosis (get-output-string diag-port))
           (when (non-empty-string? diagnosis)
             (printf "\n~a\n" diagnosis)))))
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
              "firn-build → validate → nixos-rebuild → tag generation")
   (walk-edge "host" "impact" "[<host>]" 'current-host
              handle-host-impact
              "dry-run impact prediction (what will rebuild, estimated time)")))
