#lang racket/base

;; firn-cmds/tag-edit — mutating commands against
;; hosts/<host>/enabled-tags.bnix.
;;
;; The tag-driven world has one source-of-truth for "what runs on a
;; host": that host's enabled-tags.bnix. Every per-module enable comes
;; from tag resolution. These commands edit that file directly:
;;
;;   firn tag enable <tag>           add <tag> to :enabled
;;   firn tag disable <tag>          remove <tag> from :enabled
;;   firn tag opt-in <tag>+<mod>     append +<mod> under <tag>
;;   firn tag opt-out <tag>+<mod>    append -<mod> under <tag>
;;   firn tag status [<host>]        show :enabled, :disabled, resolved set
;;   firn module disable <name>      append <name> to :disabled
;;   firn module enable <name>       remove <name> from :disabled, OR error
;;                                   with guidance if <name> is not there
;;
;; The on-disk file is parsed with tag-resolve's `extract-host-tags`,
;; mutated as an AST, and re-emitted with a fixed pretty-printer that
;; matches the current hand-authored shape (one entry per line under
;; :enabled, inline :disabled).

(require racket/file
         racket/list
         racket/string
         "util.rkt"
         "tag-resolve.rkt")

(provide node-edges)

;; ---------- pretty-printer ----------

(define (entry->string entry)
  ;; entry = (cons tag-string (list of (op . mod-name) ...))
  (define tag (car entry))
  (define flags (cdr entry))
  (cond
    [(null? flags) tag]
    [else
     (string-append
      "[" tag " "
      (string-join
       (for/list ([f (in-list flags)])
         (define sign (case (car f) [(plus) "+"] [(minus) "-"] [else ""]))
         (string-append sign (cdr f)))
       " ")
      "]")]))

(define (format-enabled-tags-bnix ht)
  ;; Pretty-print the host-tags struct back to beagle/nix source.
  ;; Matches the shape of existing hand-authored files: one entry per
  ;; line under :enabled, inline :disabled if non-empty.
  (define enabled (host-tags-enabled ht))
  (define disabled (host-tags-disabled ht))
  (define platform (host-tags-platform ht))
  (define out (open-output-string))
  (fprintf out "#lang beagle/nix\n\n")
  (fprintf out "(ns enabled-tags)\n\n")
  (fprintf out "{:platform ~a\n :enabled\n" platform)
  (cond
    [(null? enabled)
     (fprintf out "  []")]
    [else
     (define lines (map entry->string enabled))
     (fprintf out "  [~a"
              (string-join lines "\n   "))
     (fprintf out "]")])
  (cond
    [(null? disabled)
     (fprintf out "\n}\n")]
    [else
     (fprintf out "\n :disabled [~a]\n}\n"
              (string-join disabled " "))])
  (get-output-string out))

;; ---------- mutation core ----------

(define (mutate-host-tags host transform)
  ;; transform : host-tags -> host-tags
  ;; Reads the host's enabled-tags.bnix, applies transform, writes back
  ;; if the result differs. Quiet no-op when unchanged.
  (define path (in-repo "hosts" host "enabled-tags.bnix"))
  (unless (file-exists? path)
    (eprintf "firn: no such file ~a\n" (relative-to-repo path))
    (eprintf "  (create the host directory and an empty enabled-tags.bnix first)\n")
    (exit 1))
  (define ht-old (extract-host-tags host))
  (define ht-new (transform ht-old))
  (cond
    [(equal? ht-old ht-new)
     (printf "no change to ~a\n" (relative-to-repo path))]
    [else
     (display-to-file (format-enabled-tags-bnix ht-new) path #:exists 'replace)
     (printf "updated ~a\n" (relative-to-repo path))]))

(define (split-leaf-on-plus leaf)
  ;; "<tag>+<mod>" → (values tag mod). Exits with usage on bad shape.
  (define m (regexp-match #px"^([^+]+)\\+(.+)$" leaf))
  (cond
    [m (values (cadr m) (caddr m))]
    [else
     (eprintf "firn: expected '<tag>+<module>', got '~a'\n" leaf)
     (exit 1)]))

(define (tag-entry-find enabled tag)
  ;; Return the (cons tag flags) entry for tag, or #f.
  (findf (λ (e) (equal? (car e) tag)) enabled))

(define (tag-entry-without enabled tag)
  ;; Drop the entry whose car is tag.
  (filter (λ (e) (not (equal? (car e) tag))) enabled))

(define (flag-in? flags op mod)
  (findf (λ (f) (and (eq? (car f) op) (equal? (cdr f) mod))) flags))

;; ---------- tag enable / disable ----------

(define (handle-tag-enable tag)
  (mutate-host-tags
   (current-hostname)
   (λ (ht)
     (define enabled (host-tags-enabled ht))
     (cond
       [(tag-entry-find enabled tag) ht]
       [else
        (host-tags (host-tags-host ht)
                   (append enabled (list (cons tag '())))
                   (host-tags-disabled ht)
                   (host-tags-platform ht))]))))

(define (handle-tag-disable tag)
  (mutate-host-tags
   (current-hostname)
   (λ (ht)
     (host-tags (host-tags-host ht)
                (tag-entry-without (host-tags-enabled ht) tag)
                (host-tags-disabled ht)
                (host-tags-platform ht)))))

;; ---------- tag opt-in / opt-out ----------

(define (add-flag-to-tag host tag op mod)
  ;; If the tag isn't currently in :enabled, auto-create it with the flag.
  ;; Otherwise, append the flag to its existing edit vector (idempotent —
  ;; if the same (op . mod) is already there, no-op).
  (mutate-host-tags
   host
   (λ (ht)
     (define enabled (host-tags-enabled ht))
     (define existing (tag-entry-find enabled tag))
     (define new-flag (cons op mod))
     (define new-enabled
       (cond
         [(not existing)
          ;; Auto-create the tag entry with this flag.
          (append enabled (list (cons tag (list new-flag))))]
         [(flag-in? (cdr existing) op mod)
          ;; Already present — no-op.
          enabled]
         [else
          ;; Append flag to existing entry's flag vector. Replace the entry.
          (for/list ([e (in-list enabled)])
            (cond
              [(equal? (car e) tag)
               (cons tag (append (cdr e) (list new-flag)))]
              [else e]))]))
     (host-tags (host-tags-host ht) new-enabled (host-tags-disabled ht)
                (host-tags-platform ht)))))

(define (handle-tag-opt-in leaf)
  (define-values (tag mod) (split-leaf-on-plus leaf))
  (add-flag-to-tag (current-hostname) tag 'plus mod))

(define (handle-tag-opt-out leaf)
  (define-values (tag mod) (split-leaf-on-plus leaf))
  (add-flag-to-tag (current-hostname) tag 'minus mod))

;; ---------- tag status ----------

(define (handle-tag-status leaf)
  (define host
    (cond
      [(or (equal? leaf "current") (equal? leaf "all"))
       (current-hostname)]
      [else leaf]))
  (define path (in-repo "hosts" host "enabled-tags.bnix"))
  (unless (file-exists? path)
    (eprintf "firn tag status: no such file ~a\n" (relative-to-repo path))
    (exit 1))
  (define ht (extract-host-tags host))
  (printf "Host: ~a\n" host)
  (printf "Platform: ~a\n" (host-tags-platform ht))
  (printf "Source: ~a\n\n" (relative-to-repo path))
  (printf ":enabled (~a):\n" (length (host-tags-enabled ht)))
  (cond
    [(null? (host-tags-enabled ht))
     (printf "  (none)\n")]
    [else
     (for ([e (in-list (host-tags-enabled ht))])
       (printf "  ~a\n" (entry->string e)))])
  (newline)
  (printf ":disabled (~a):\n" (length (host-tags-disabled ht)))
  (cond
    [(null? (host-tags-disabled ht))
     (printf "  (none)\n")]
    [else
     (for ([m (in-list (host-tags-disabled ht))])
       (printf "  ~a\n" m))])
  (newline)
  ;; Resolved active set
  (define res (resolve-host host))
  (cond
    [(pair? (resolution-errors res))
     (printf "Resolution errors (~a):\n" (length (resolution-errors res)))
     (for ([e (in-list (resolution-errors res))])
       (printf "  ~a\n" (tag-validation-error-hint e)))
     (newline)]
    [else (void)])
  (define active (resolution-active res))
  (printf "Resolved active modules (~a):\n" (length active))
  (cond
    [(null? active) (printf "  (none)\n")]
    [else (for ([m (in-list active)]) (printf "  ~a\n" m))]))

;; ---------- module enable / disable (manage :disabled) ----------

(define (handle-module-tag-disable name)
  ;; Append name to :disabled if not already present.
  (mutate-host-tags
   (current-hostname)
   (λ (ht)
     (cond
       [(member name (host-tags-disabled ht)) ht]
       [else
        (host-tags (host-tags-host ht)
                   (host-tags-enabled ht)
                   (sort (cons name (host-tags-disabled ht)) string<?)
                   (host-tags-platform ht))]))))

(define (handle-module-tag-enable name)
  ;; Two outcomes:
  ;;   1. If <name> is in :disabled → remove it (un-blacklist).
  ;;   2. Otherwise → error with guidance: there is no module-level
  ;;      force-on in the tag-driven model. The user should either add
  ;;      the module to a tag's :tags / :tags-opt-in, or opt-in via
  ;;      `firn tag opt-in <tag>+<mod>`.
  (define ht (extract-host-tags (current-hostname)))
  (cond
    [(member name (host-tags-disabled ht))
     (mutate-host-tags
      (current-hostname)
      (λ (ht2)
        (host-tags (host-tags-host ht2)
                   (host-tags-enabled ht2)
                   (filter (λ (m) (not (equal? m name)))
                           (host-tags-disabled ht2))
                   (host-tags-platform ht2))))]
    [else
     (eprintf "firn module enable: no module-level force-on in tag-driven hosts.\n")
     (eprintf "\n")
     (eprintf "  ~a is not currently blacklisted in :disabled, so there is\n" name)
     (eprintf "  nothing to un-blacklist. To activate it on this host:\n")
     (eprintf "\n")
     (eprintf "    - opt in via a tag:    firn tag opt-in <tag>+~a\n" name)
     (eprintf "      (where <tag> is one the module lists in :tags-opt-in)\n")
     (eprintf "    - or enable a tag the module already lists in :tags:\n")
     (eprintf "                            firn tag enable <tag>\n")
     (eprintf "    - or, only as a last resort, add :tags ~a-only to the module\n" (current-hostname))
     (eprintf "      and enable that tag here.\n")
     (exit 1)]))

;; ---------- registration ----------

(define node-edges
  (list
   (walk-edge "tag" "enable"  "<tag>" #f
              handle-tag-enable
              "enable a tag in the current host's enabled-tags.bnix")
   (walk-edge "tag" "disable" "<tag>" #f
              handle-tag-disable
              "remove a tag from the current host's enabled-tags.bnix")
   (walk-edge "tag" "opt-in"  "<tag>+<module>" #f
              handle-tag-opt-in
              "append +<module> under <tag> in enabled-tags.bnix")
   (walk-edge "tag" "opt-out" "<tag>+<module>" #f
              handle-tag-opt-out
              "append -<module> under <tag> in enabled-tags.bnix")
   (walk-edge "tag" "status"  "<host>" 'current-host
              handle-tag-status
              "show enabled-tags.bnix + resolved active modules")
   (walk-edge "module" "enable"  "<name>" #f
              handle-module-tag-enable
              "remove <name> from :disabled (no module-level force-on)")
   (walk-edge "module" "disable" "<name>" #f
              handle-module-tag-disable
              "append <name> to :disabled in enabled-tags.bnix")))
