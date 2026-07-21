#lang racket/base

;; tag-resolve-test — unit tests for the tag-driven composition resolver.
;;
;; Run:  raco test tests/tag-resolve-test.rkt
;;
;; Tests cover the four worked examples from docs/TAGS.md plus the
;; validation paths (unknown tag, opt-in mismatch, unknown disabled,
;; minus-typo warning, tag-override scoping).

(require rackunit
         "../scripts/firn-cmds/tag-resolve.rkt")

;; ---------- helpers ----------

(define (mod name #:tags [tags '()] #:opt-in [opt-in '()] #:overrides [overrides (hash)])
  (cons name (module-tags name tags opt-in overrides)))

(define (mk-index . pairs)
  (define h (make-hash))
  (for ([p (in-list pairs)])
    (hash-set! h (car p) (cdr p)))
  h)

(define (mk-host name #:enabled [enabled '()] #:disabled [disabled '()]
                 #:platform [platform "linux"])
  ;; enabled is a list of either:
  ;;   "tagname"                                — bare-tag entry
  ;;   (cons "tagname" (list (cons 'minus "x") (cons 'plus "y") …))
  ;;                                            — edited-tag entry
  ;; This mirrors what extract-host-tags returns from the .bnix.
  (host-tags name
             (for/list ([e (in-list enabled)])
               (cond [(string? e) (cons e '())]
                     [else e]))
             disabled
             platform))

(define (active-set res) (resolution-active res))
(define (per-tag res tag) (sort (hash-ref (resolution-per-tag res) tag '()) string<?))
(define (overrides-for res mod) (hash-ref (resolution-overrides res) mod '()))

;; ---------- worked example 1: kitchen-sink ----------

(test-case "kitchen-sink: enabling a tag activates every module that joins it"
  (define idx
    (mk-index
     (mod "git"     #:tags '("dev" "terminal"))
     (mod "ripgrep" #:tags '("dev" "terminal"))
     (mod "firefox" #:tags '("browsers" "gui-only"))))
  (define res (resolve idx (mk-host "h" #:enabled '("dev" "terminal" "browsers"))))
  (check-equal? (active-set res) '("firefox" "git" "ripgrep"))
  (check-equal? (per-tag res "dev") '("git" "ripgrep"))
  (check-equal? (per-tag res "browsers") '("firefox"))
  (check-equal? (resolution-errors res) '())
  (check-equal? (resolution-warnings res) '()))

;; ---------- worked example 2: edited tag (minus) ----------

(test-case "edited tag: -firefox removes firefox from browsers contribution"
  (define idx
    (mk-index
     (mod "git"     #:tags '("dev" "terminal"))
     (mod "ripgrep" #:tags '("dev" "terminal"))
     (mod "firefox" #:tags '("browsers" "gui-only"))))
  (define res (resolve idx
                       (mk-host "h"
                                #:enabled (list "dev"
                                                (cons "browsers"
                                                      (list (cons 'minus "firefox")))))))
  (check-equal? (active-set res) '("git" "ripgrep"))
  (check-false (member "firefox" (active-set res)))
  ;; Minus scope: firefox stays out of browsers' contribution but if
  ;; gui-only were also enabled, firefox would come back via that tag.
  (check-equal? (per-tag res "browsers") '()))

(test-case "edited tag: per-tag minus does not affect other tags"
  (define idx
    (mk-index
     (mod "firefox" #:tags '("browsers" "gui-only"))))
  (define res (resolve idx
                       (mk-host "h"
                                #:enabled (list (cons "browsers"
                                                      (list (cons 'minus "firefox")))
                                                "gui-only"))))
  ;; firefox subtracted from browsers but gui-only puts it back.
  (check-equal? (active-set res) '("firefox")))

;; ---------- worked example 3: opt-in plus ----------

(test-case "opt-in plus: +qutebrowser-experimental activates an opt-in module"
  (define idx
    (mk-index
     (mod "firefox" #:tags '("browsers"))
     (mod "qutebrowser-experimental" #:opt-in '("browsers"))))
  (define res (resolve idx
                       (mk-host "h"
                                #:enabled (list (cons "browsers"
                                                      (list (cons 'plus "qutebrowser-experimental")))))))
  (check-equal? (active-set res) '("firefox" "qutebrowser-experimental")))

(test-case "opt-in plus: enabling the tag alone does NOT pull in opt-in modules"
  (define idx
    (mk-index
     (mod "qutebrowser-experimental" #:opt-in '("browsers"))))
  (define res (resolve idx (mk-host "h" #:enabled '("browsers"))))
  (check-equal? (active-set res) '()))

(test-case "opt-in plus mismatch: +x under tag that x doesn't list in :tags-opt-in errors"
  (define idx
    (mk-index
     ;; 'terminal' is a known tag (git lists it) but qutebrowser-experimental
     ;; lists its opt-in for 'browsers', not 'terminal' — so +x under
     ;; terminal must error.
     (mod "git" #:tags '("terminal"))
     (mod "qutebrowser-experimental" #:opt-in '("browsers"))))
  (define res (resolve idx
                       (mk-host "h"
                                #:enabled (list (cons "terminal"
                                                      (list (cons 'plus "qutebrowser-experimental")))))))
  (define opt-errs
    (for/list ([e (in-list (resolution-errors res))]
               #:when (eq? (tag-validation-error-kind e) 'opt-in-mismatch))
      e))
  (check-equal? (length opt-errs) 1)
  (check-equal? (tag-validation-error-mod (car opt-errs)) "qutebrowser-experimental")
  (check-equal? (tag-validation-error-tag (car opt-errs)) "terminal"))

;; ---------- worked example 4: hard disable ----------

(test-case "hard disable: :disabled wins over every tag-based activation"
  (define idx
    (mk-index
     (mod "piper" #:tags '("dev"))))
  (define res (resolve idx (mk-host "h" #:enabled '("dev") #:disabled '("piper"))))
  (check-equal? (active-set res) '())
  (check-equal? (resolution-warnings res) '()))

(test-case "hard disable: warns if disabled name is unknown module"
  (define idx (mk-index (mod "firefox" #:tags '("browsers"))))
  (define res (resolve idx
                       (mk-host "h"
                                #:enabled '("browsers")
                                #:disabled '("nonexistent-mod"))))
  (check-not-equal? (resolution-errors res) '())
  (define e (car (resolution-errors res)))
  (check-equal? (tag-validation-error-kind e) 'unknown-disabled))

;; ---------- worked example 5: tag-override scoping ----------

(test-case "tag-override fires when module joins via :tags (default-on)"
  (define idx
    (mk-index
     (mod "firefox"
          #:tags '("browsers")
          #:overrides (hash "browsers"
                            (list (cons "myConfig.modules.firefox.default" #t))))))
  (define res (resolve idx (mk-host "h" #:enabled '("browsers"))))
  (check-equal? (active-set res) '("firefox"))
  (define ov (overrides-for res "firefox"))
  (check-equal? ov (list (cons "myConfig.modules.firefox.default" #t))))

(test-case "tag-override does NOT fire when module joins another tag without override entry"
  (define idx
    (mk-index
     (mod "firefox"
          #:tags '("browsers" "gui-only")
          #:overrides (hash "browsers"
                            (list (cons "myConfig.modules.firefox.default" #t))))))
  ;; Enable only gui-only; firefox activates via gui-only, no override.
  (define res (resolve idx (mk-host "h" #:enabled '("gui-only"))))
  (check-equal? (active-set res) '("firefox"))
  (check-equal? (overrides-for res "firefox") '()))

(test-case "tag-override does NOT fire for opt-in (+) activations"
  (define idx
    (mk-index
     (mod "firefox"
          #:opt-in '("browsers")
          #:overrides (hash "browsers"
                            (list (cons "myConfig.modules.firefox.default" #t))))))
  (define res (resolve idx
                       (mk-host "h"
                                #:enabled (list (cons "browsers"
                                                      (list (cons 'plus "firefox")))))))
  (check-equal? (active-set res) '("firefox"))
  (check-equal? (overrides-for res "firefox") '()
                "overrides only apply for :tags default-on, not :tags-opt-in plus"))

;; ---------- validation errors ----------

(test-case "unknown tag in host :enabled errors"
  (define idx (mk-index (mod "firefox" #:tags '("browsers"))))
  (define res (resolve idx (mk-host "h" #:enabled '("nonexistent-tag"))))
  (check-not-equal? (resolution-errors res) '())
  (define e (car (resolution-errors res)))
  (check-equal? (tag-validation-error-kind e) 'unknown-tag)
  (check-equal? (tag-validation-error-tag e) "nonexistent-tag"))

(test-case "minus-typo: -name where name isn't in tag's defaults produces warning"
  (define idx
    (mk-index
     (mod "firefox" #:tags '("browsers"))))
  (define res (resolve idx
                       (mk-host "h"
                                #:enabled (list (cons "browsers"
                                                      (list (cons 'minus "ferefox")))))))
  ;; -ferefox is a typo for -firefox; firefox is still active
  ;; (the minus didn't apply), and a warning is recorded.
  (check-equal? (active-set res) '("firefox"))
  (check-not-equal? (resolution-warnings res) '()))

;; ---------- union semantics ----------

(test-case "active is the union across multiple enabled tags"
  (define idx
    (mk-index
     (mod "git"     #:tags '("dev"))
     (mod "ripgrep" #:tags '("dev" "terminal"))
     (mod "firefox" #:tags '("browsers"))))
  (define res (resolve idx (mk-host "h" #:enabled '("dev" "browsers"))))
  (check-equal? (active-set res) '("firefox" "git" "ripgrep")))

(test-case "Darwin resolution excludes tag members outside the canonical import allowlist"
  (define idx
    (mk-index
     (mod "git" #:tags '("cli-tools"))
     (mod "libsecret" #:tags '("cli-tools"))))
  (define res
    (resolve idx
             (mk-host "ashashi" #:enabled '("cli-tools") #:platform "darwin")
             #:allowed-modules '("git")))
  (check-equal? (active-set res) '("git"))
  (check-equal? (per-tag res "cli-tools") '("git"))
  (check-false (regexp-match? #rx"libsecret" (emit-host-enables-bnix res))))

;; ---------- emitter ----------

(test-case "emit produces a parseable beagle/nix file with mkDefault enables"
  (define idx
    (mk-index
     (mod "git"     #:tags '("dev"))
     (mod "ripgrep" #:tags '("dev"))))
  (define res (resolve idx (mk-host "whiterabbit" #:enabled '("dev"))))
  (define text (emit-host-enables-bnix res))
  (check-true (regexp-match? #rx"#lang beagle/nix" text))
  (check-true (regexp-match? #rx":myConfig\\.modules\\.git\\.enable \\(lib\\.mkDefault true\\)" text))
  (check-true (regexp-match? #rx":myConfig\\.modules\\.ripgrep\\.enable \\(lib\\.mkDefault true\\)" text)))

(test-case "emit includes tag-override entries"
  (define idx
    (mk-index
     (mod "firefox"
          #:tags '("browsers")
          #:overrides (hash "browsers"
                            (list (cons "myConfig.modules.firefox.default" #t))))))
  (define res (resolve idx (mk-host "whiterabbit" #:enabled '("browsers"))))
  (define text (emit-host-enables-bnix res))
  (check-true (regexp-match? #rx":myConfig\\.modules\\.firefox\\.enable \\(lib\\.mkDefault true\\)" text))
  (check-true (regexp-match? #rx":myConfig\\.modules\\.firefox\\.default \\(lib\\.mkDefault true\\)" text)))
