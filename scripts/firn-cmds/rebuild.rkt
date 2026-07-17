#lang racket/base

(require racket/string
         racket/list
         racket/math
         racket/path
         racket/set
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
  ;; Long phases (the switch) stream child output live.
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

  ;; ─── Commit snapshot ─────────────────────────────────────────────────
  ;; Generations build from the COMMITTED tree (git+file?rev=HEAD), never the
  ;; working tree. Concurrent sessions' WIP — here or in any local input —
  ;; can neither leak into a generation nor block a switch. Self-heal commits
  ;; below may advance HEAD, so the snapshot ref is computed lazily.
  (define (git-head) (string-trim (sh-out "git" "-C" ROOT "rev-parse" "HEAD")))
  (define build-branch (string-trim (sh-out "git" "-C" ROOT "branch" "--show-current")))
  (define (snapshot-ref)
    (format "git+file://~a?rev=~a~a" ROOT (git-head)
            (if (non-empty-string? build-branch)
                (format "&ref=~a" build-branch) "")))
  (define (dirty-build-files)
    (for/list ([l (in-list (string-split
                            (sh-out "git" "-C" ROOT "status" "--porcelain" "--untracked-files=no")
                            "\n"))]
               #:when (and (> (string-length l) 3)
                           (regexp-match? #rx"\\.(bnix|nix)$|flake\\.lock$" l)))
      (substring l 3)))
  (let ([dirty (dirty-build-files)])
    (unless (null? dirty)
      (printf "── snapshot: building committed ~a — ~a in-flight build file(s) stay out of this generation:\n"
              (substring (git-head) 0 8) (length dirty))
      (for ([f (in-list dirty)]) (printf "     ~a\n" f))))

  ;; Local input pins: plan-only (no lock mutation). Promotable moves become
  ;; --override-input flags on the snapshot build; the lock is re-pointed and
  ;; mechanically committed only after the closure verifies.
  (define overrides '())   ; (list input target-rev repo)
  (cond
    [skip-checks?
     (printf "── local inputs: committed lock as-is (--skip-checks never promotes pins)\n")]
    [else
     (phase "local inputs (plan)"
       (λ ()
         (define plan-file (make-temporary-file "firn-plan-~a"))
         (define ok?
           (sh "bash" "-c"
               (format "'~a' --plan > '~a'"
                       (path->string (in-repo "scripts" "firn-sync-local-inputs"))
                       plan-file)))
         (when ok?
           (for ([line (in-list (string-split (file->string plan-file) "\n"))])
             (define m (regexp-match #px"^plan (\\S+) ([0-9a-f]{40}) ([0-9a-f]{40}) (\\S+)$" line))
             (if m
                 (set! overrides (cons (list (list-ref m 1) (list-ref m 3) (list-ref m 4))
                                       overrides))
                 (when (non-empty-string? (string-trim line))
                   (printf "~a\n" line)))))
         (delete-file plan-file)
         ok?))])
  (define override-args
    (append*
     (for/list ([o (in-list overrides)])
       (list "--override-input" (car o)
             (format "git+file://~a?ref=main&rev=~a" (caddr o) (cadr o))))))

  (unless skip-checks?
    ;; Step 1: regenerate any out-of-date .nix from .bnix sources, then
    ;; self-heal: regenerated outputs whose sources are committed-clean are
    ;; deterministic derivations of the commit — mechanically commit them so
    ;; the snapshot stays self-consistent. Outputs downstream of in-flight
    ;; WIP are left alone (the snapshot keeps their committed versions).
    (define pre-dirty (list->set (dirty-build-files)))
    (phase "firn-build"
      (λ () (sh (path->string (in-repo "scripts" "firn-build")))))
    (let* ([post-dirty (list->set (dirty-build-files))]
           [newly (set->list (set-subtract post-dirty pre-dirty))]
           [generated? (λ (f) (or (member f '("flake.bnix" "flake.nix"))
                                  (regexp-match? #rx"_generated-enables\\.bnix$" f)))]
           [foreign-bnix? (for/or ([f (in-set post-dirty)])
                            (and (regexp-match? #rx"\\.bnix$" f) (not (generated? f))))]
           [heal (for/list ([f (in-list newly)]
                            #:when (or (and (regexp-match? #rx"\\.nix$" f)
                                            (not (equal? f "flake.nix"))
                                            (let ([src (regexp-replace #rx"\\.nix$" f ".bnix")])
                                              (and (file-exists? (build-path ROOT src))
                                                   (not (set-member? post-dirty src)))))
                                       (and (generated? f) (not foreign-bnix?))))
                   f)]
           [skipped (remove* heal newly)])
      (unless (null? heal)
        (phase "self-heal stale committed outputs"
          (λ () (apply sh "git" "-C" ROOT "commit" "--only" "-m"
                       "regenerate stale committed outputs (firn rebuild self-heal)"
                       "--" heal))))
      (unless (null? skipped)
        (printf "── note: regenerated outputs depend on in-flight WIP; snapshot keeps their committed versions:\n")
        (for ([f (in-list skipped)]) (printf "     ~a\n" f))))

    ;; Step 1b: untracked build files are invisible to the snapshot. A warning,
    ;; not a wall — they may be another session's half-born module.
    (define untracked
      (let ([s (sh-out "git" "-C" ROOT "ls-files" "--others" "--exclude-standard")])
        (filter (λ (p) (regexp-match? #rx"\\.(bnix|rkt|nix)$" p))
                (string-split s "\n"))))
    (unless (null? untracked)
      (printf "── warning: untracked files are NOT in this build (git add + commit to include):\n")
      (for ([p (in-list untracked)]) (printf "     ~a\n" p)))

    ;; Step 2: validate the SNAPSHOT, not the working tree — a peer's mid-edit
    ;; .bnix must not fail an unrelated rebuild. A detached temp worktree gives
    ;; the validator the committed content.
    (define wt-parent (make-temporary-file "firn-snapshot-~a" 'directory))
    (define wt (build-path wt-parent "wt"))
    (define (cleanup-worktree!)
      (parameterize ([current-output-port (open-output-nowhere)]
                     [current-error-port (open-output-nowhere)])
        (sh "git" "-C" ROOT "worktree" "remove" "--force" (path->string wt)))
      (when (directory-exists? wt-parent)
        (delete-directory/files wt-parent #:must-exist? #f)))
    (define old-exit (exit-handler))
    (exit-handler (λ (c) (cleanup-worktree!) (old-exit c)))
    (phase "firn-validate (snapshot)"
      (λ ()
        (and (sh "git" "-C" ROOT "worktree" "add" "--detach" (path->string wt) (git-head))
             ;; The schema cache is untracked by design; share the live one.
             (begin
               (when (and (directory-exists? (build-path ROOT ".beagle-cache"))
                          (not (directory-exists? (build-path wt ".beagle-cache"))))
                 (make-file-or-directory-link (build-path ROOT ".beagle-cache")
                                              (build-path wt ".beagle-cache")))
               #t)
             (let ([old-repo (getenv "FIRN_REPO")]
                   [old-beagle (getenv "BEAGLE_PATH")])
               (putenv "FIRN_REPO" (path->string wt))
               (putenv "BEAGLE_PATH"
                       (or old-beagle
                           (path->string (simplify-path (build-path ROOT 'up "beagle")))))
               (begin0
                 (parameterize ([current-directory wt])
                   (sh (path->string (build-path wt "scripts" "firn-validate"))))
                 (putenv "FIRN_REPO" (or old-repo ""))
                 (unless old-beagle (putenv "BEAGLE_PATH" "")))))))
    (cleanup-worktree!)
    (exit-handler old-exit)

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
                  #f))))))

  ;; Step 2c: build the exact host closure from the snapshot. Always runs
  ;; (with --skip-checks too): the switch below activates THIS store path, so
  ;; what was verified is byte-identical to what runs.
  (define on-darwin?
    (equal? "Darwin" (string-trim (sh-out "uname" "-s"))))
  (define extra (if auto-impure? (list "--impure") '()))
  (define built-path #f)
  (phase "build snapshot closure"
    (λ ()
      (define attr
        (format "~a#~a" (snapshot-ref)
                (if on-linux?
                    (format "nixosConfigurations.~a.config.system.build.toplevel" host)
                    (format "darwinConfigurations.~a.system" host))))
      (define out (apply sh-out (append (list "nix" "build" "--no-link" "--print-out-paths" attr)
                                        override-args extra)))
      (set! built-path (and (regexp-match? #rx"^/nix/store/" out) out))
      (and built-path #t)))
  (when (and on-linux? built-path)
    (printf "── closure diff vs running system:\n") (flush-output)
    (sh "nix" "store" "diff-closures" "/run/current-system" built-path))

  ;; Only a verified pointer earns a mechanical lock commit; deferrals inside
  ;; the script are notices, never failures.
  (unless (or skip-checks? (null? overrides))
    (phase "promote verified local inputs"
      (λ () (apply sh
                   (path->string (in-repo "scripts" "firn-sync-local-inputs"))
                   "--commit"
                   (for/list ([o (in-list overrides)])
                     (format "~a=~a" (car o) (cadr o)))))))

  ;; Step 3: switch. On Linux, activate the EXACT store path the smoke build
  ;; produced (profile set + switch-to-configuration) — no second evaluation,
  ;; no root-side git access to a user checkout, and the verified closure is
  ;; byte-identical to the activated one. Darwin keeps darwin-rebuild but on
  ;; the same commit snapshot.
  (printf "┌─ rebuild\n") (flush-output)
  (define rebuild-start (current-inexact-milliseconds))
  (define rc
    (cond
      [on-darwin?
       (apply sh (append (list "sudo" "darwin-rebuild" "switch" "--flake"
                               (format "~a#~a" (snapshot-ref) host))
                         override-args extra))]
      [else
       (and built-path
            (sh "sudo" "nix-env" "--profile" "/nix/var/nix/profiles/system"
                "--set" built-path)
            (sh "sudo" (string-append built-path "/bin/switch-to-configuration")
                "switch"))]))
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
     ;; Current generation: modern `list-generations` marks it with a trailing
     ;; True column ("Current" appears only in the header); the old format
     ;; carried a lowercase "current" marker. Accept both — the old parser
     ;; matched neither and silently stopped tagging at gen-783.
     (define gen
       (for/or ([line (in-list (string-split gens "\n"))])
         (define t (string-trim line))
         (define m (regexp-match #px"^([0-9]+)\\s" t))
         (and m
              (or (regexp-match? #px"\\bTrue\\s*$" t)
                  (regexp-match? #rx"current" t))
              (cadr m))))
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
              "plan pins → build+validate commit snapshot → switch verified closure → tag generation")
   (walk-edge "host" "impact" "[<host>]" 'current-host
              handle-host-impact
              "dry-run impact prediction (what will rebuild, estimated time)")))
