#lang racket/base

(require racket/string
         racket/list
         racket/path
         "util.rkt"
         "tag-resolve.rkt")

(provide host-of-path node-edges
         host-modules
         live-modules)

;; ---------- AST-based reference extraction ----------
;;
;; A module is "referenced by" a file if any path mentioned in that
;; file starts with `myConfig.modules.<name>`. This catches every
;; shape the regex-based predecessor missed:
;;   (set myConfig.modules.X.enable #t)             — direct enable
;;   (set myConfig.modules.X (att (enable #t) …))   — attrset form
;;   (set myConfig.modules.X.someOption val)        — config-only
;;   (enable myConfig.modules.X)                    — bare enable
;;
;; All of those go through util.rkt's `paths-referenced-in`.

(define (host-of-path p)
  (define m (regexp-match #rx"/hosts/([^/]+)/" p))
  (and m (cadr m)))

(define (host-modules host)
  ;; Direct module references in this host's configuration.bnix.
  (define f (host-config-source host))
  (cond
    [(file-exists? f)
     (define paths (paths-referenced-in f))
     (sort
      (remove-duplicates
       (filter values
               (for/list ([p (in-list paths)])
                 (define m (regexp-match #rx"^myConfig\\.modules\\.([^.]+)" p))
                 (and m (cadr m)))))
      string<?)]
    [else '()]))

(define (host-tag-modules host)
  ;; Modules that resolve to "enabled" via the tag system for this host.
  (with-handlers ([exn:fail? (λ (_) '())])
    (define res (resolve-host host))
    (resolution-active res)))

;; ---------- live closure ----------

(define (live-modules)
  ;; Modules referenced directly by any host's configuration.bnix OR
  ;; activated via tag resolution against that host's enabled-tags.bnix.
  (define hs (hosts))
  (define from-hosts (apply append (map host-modules hs)))
  (define from-tags  (apply append (map host-tag-modules hs)))
  (sort (remove-duplicates (append from-hosts from-tags)) string<?))

;; ---------- set helpers (avoid pulling in racket/set fully) ----------

(define (list->set xs) (let ([h (make-hash)]) (for ([x (in-list xs)]) (hash-set! h x #t)) h))

;; ---------- handlers ----------

(define (print-used-modules)
  (define live-mods (live-modules))
  (printf "Used modules (~a):\n" (length live-mods))
  (for ([m (in-list live-mods)])
    (define direct-h (filter (λ (host) (member m (host-modules host))) (hosts)))
    (define via-tag-h (filter (λ (host) (member m (host-tag-modules host))) (hosts)))
    (define sources
      (append direct-h
              (map (λ (h) (string-append "via tag@" h)) via-tag-h)))
    (printf "  ~a  (~a)\n" m
            (cond [(pair? sources) (string-join (remove-duplicates sources) ", ")]
                  [else "—"]))))

(define (print-unused-modules)
  (define live (list->set (live-modules)))
  (define dead (sort (filter (λ (m) (not (hash-has-key? live m))) (modules)) string<?))
  (printf "Unreferenced modules (~a):\n" (length dead))
  (for ([m (in-list dead)]) (printf "  ~a\n" m)))

(define (handle-module-list leaf)
  (case (string->symbol leaf)
    [(all)
     (define ms (modules))
     (printf "Modules (~a):\n" (length ms))
     (for ([m (in-list ms)]) (printf "  myConfig.modules.~a\n" m))]
    [(used)   (print-used-modules)]
    [(unused) (print-unused-modules)]
    [else
     (eprintf "firn module list: expected one of all|used|unused, got '~a'\n" leaf)
     (exit 1)]))

(define (handle-host-list _leaf)
  (define hs (hosts))
  (printf "Hosts (~a):\n" (length hs))
  (for ([h (in-list hs)]) (printf "  ~a\n" h)))

(define (print-refs name)
  ;; Direct = referenced in the host's hand-authored configuration.bnix.
  ;; Via tags = activated by tag resolution (reads enabled-tags.bnix,
  ;; does not depend on the .nix output). _generated-enables.bnix is
  ;; intentionally excluded — it's just the materialised tag result.
  (printf "Hosts (direct, from configuration.bnix):\n")
  (define direct-hs
    (sort (filter (λ (h) (member name (host-modules h))) (hosts))
          string<?))
  (cond
    [(null? direct-hs) (printf "  (none)\n")]
    [else (for ([h (in-list direct-hs)]) (printf "  ~a\n" h))])
  (newline)
  (printf "Hosts (via tag resolution):\n")
  (define tag-hs
    (sort (filter (λ (h) (member name (host-tag-modules h))) (hosts))
          string<?))
  (cond
    [(null? tag-hs) (printf "  (none)\n")]
    [else (for ([h (in-list tag-hs)]) (printf "  ~a\n" h))]))

(define node-edges
  (list
   (walk-edge "module" "list" "all|used|unused" 'all
              handle-module-list
              "list modules (all, used = enabled somewhere, unused = orphan)")
   (walk-edge "module" "refs" "<name>" #f
              print-refs
              "show which hosts reference a module (direct + via tags)")
   (walk-edge "host"   "list" "all" 'all
              handle-host-list
              "list every host directory under hosts/")))
