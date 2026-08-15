#lang racket/base

;; firn-cmds/platforms — answer "which modules work on darwin?"
;;
;; The mechanism: every (set X.Y val) and (enable X.Y) form in a module
;; references an option path. We cross-check each module's paths against
;; both the NixOS schema and the darwin schema; a module whose paths all
;; exist in darwin is darwin-compatible.
;;
;; Pre-req: both schemas extracted.
;;   ./scripts/firn-extract-schema           → .beagle-cache/schema.json
;;   ./scripts/firn-extract-schema --darwin  → .beagle-cache/schema-darwin.json
;;
;; Usage:
;;   firn platform list all          full matrix
;;   firn platform list darwin       list darwin-compatible only
;;   firn platform list linux        list NixOS-only
;;   firn platform show <name>       single module, with reason
;;   firn platform safelist all      suggested safelist for flake.bnix

(require racket/file
         racket/list
         racket/path
         racket/string
         racket/format
         json
         "util.rkt")

(provide node-edges)

(define CACHE-DIR (build-path ROOT ".beagle-cache"))
(define NIXOS-SCHEMA (build-path CACHE-DIR "schema.json"))
(define DARWIN-SCHEMA (build-path CACHE-DIR "schema-darwin.json"))

;; ---------- schema loading ----------

;; Schema info for compat-check. A schema is a triple of hashes:
;;   - direct: every option path → #t
;;   - prefix: every dotted prefix of every option path → #t
;;     (handles `(set programs.bash (att …))` where the attrset
;;     covers multiple leaves under that prefix)
;;   - freeform: every option whose type is attrsOf/lazyAttrsOf/etc.
;;     → #t. Children of freeform paths are always valid (e.g.
;;     `users.users.tom.shell` matches because `users.users` is
;;     attrsOf submodule).
(struct schema (direct prefix freeform) #:transparent)

(define FREEFORM-TYPES
  '("attrsOf" "lazyAttrsOf" "anything" "unspecified" "freeform"))

(define (load-schema-paths path)
  (define direct (make-hash))
  (define prefix-h (make-hash))
  (define freeform (make-hash))
  (when (file-exists? path)
    (for ([e (in-list (call-with-input-file path read-json))])
      (define p (hash-ref e 'p))
      (define t (hash-ref e 't "?"))
      (hash-set! direct p #t)
      (when (member t FREEFORM-TYPES)
        (hash-set! freeform p #t))
      (define segs (string-split p "."))
      (let loop ([acc '()] [rest segs])
        (when (pair? rest)
          (define new-acc (append acc (list (car rest))))
          (hash-set! prefix-h (string-join new-acc ".") #t)
          (loop new-acc (cdr rest))))))
  (schema direct prefix-h freeform))

(define (path-in-schema? sch path)
  ;; Three checks, in order:
  ;;   1. Direct/prefix hit (exact or `(set X (att …))` covering multiple leaves).
  ;;   2. Wildcard parent — `users.users.tom.shell` matches schema's
  ;;      `users.users.<name>.shell` if extractor stored that form.
  ;;   3. Freeform ancestor — `users.users.kanata` matches because
  ;;      `users.users` has type attrsOf and accepts arbitrary children.
  (cond
    [(hash-has-key? (schema-prefix sch) path) #t]
    [else
     (define segs (string-split path "."))
     (define n (length segs))
     (or
      ;; wildcard substitution
      (for/or ([i (in-range n)])
        (define candidate
          (string-join
           (for/list ([(s j) (in-indexed (in-list segs))])
             (if (= j i) "<name>" s))
           "."))
        (hash-has-key? (schema-prefix sch) candidate))
      ;; freeform ancestor
      (let loop ([i (- n 1)])
        (cond
          [(<= i 0) #f]
          [else
           (define ancestor (string-join (take segs i) "."))
           (cond
             [(hash-has-key? (schema-freeform sch) ancestor) #t]
             [else (loop (- i 1))])])))]))

;; ---------- per-rkt path extraction ----------

;; (paths-referenced-in lives in util.rkt for shared use)

;; ---------- module resolution ----------

(define (module-rkt-files name)
  ;; Returns all .rkt files in modules/<name>/ (default + any siblings)
  (define dir (in-repo "modules" name))
  (cond
    [(directory-exists? dir)
     (for/list ([p (directory-list dir)]
                #:when (regexp-match? #rx"\\.rkt$" (path->string p)))
       (build-path dir p))]
    [else '()]))

;; ---------- compatibility check ----------

(define (module-compat name nixos-schema darwin-schema)
  ;; Returns (values verdict blockers)
  ;;   verdict ∈ '(both linux-only darwin-only no-data)
  ;;   blockers = list of paths that broke compat (relevant for
  ;;              linux-only or darwin-only)
  (define files (module-rkt-files name))
  (cond
    [(null? files) (values 'no-data '())]
    [else
     (define all-paths
       (remove-duplicates
        (for/fold ([acc '()]) ([f (in-list files)])
          (append (paths-referenced-in f) acc))))
     ;; Skip:
     ;;   - myConfig.* (declared by our own modules, not in upstream schema)
     ;;   - cfg./config. lookups (read-only references, not setter targets)
     ;;   - bare "config"/"options"/"imports" — these are NixOS module
     ;;     top-level attrs (e.g. (set config (att …)) in the explicit
     ;;     options/config split shape), not option paths
     (define system-paths
       (filter (λ (p)
                 (and (not (string-prefix? p "cfg."))
                      (not (string-prefix? p "config."))
                      (not (string-prefix? p "myConfig."))
                      (not (member p '("config" "options" "imports")))))
               all-paths))
     (cond
       [(null? system-paths)
        ;; Pure HM module — compatible on both (HM works on darwin
        ;; via home-manager.darwinModules)
        (values 'both '())]
       [else
        (define linux-ok?
          (andmap (λ (p) (path-in-schema? nixos-schema p)) system-paths))
        (define darwin-ok?
          (andmap (λ (p) (path-in-schema? darwin-schema p)) system-paths))
        (define linux-blockers
          (filter (λ (p) (not (path-in-schema? nixos-schema p))) system-paths))
        (define darwin-blockers
          (filter (λ (p) (not (path-in-schema? darwin-schema p))) system-paths))
        (cond
          [(and linux-ok? darwin-ok?) (values 'both '())]
          [linux-ok? (values 'linux-only darwin-blockers)]
          [darwin-ok? (values 'darwin-only linux-blockers)]
          [else (values 'no-data
                        (append linux-blockers darwin-blockers))])])]))

;; ---------- output ----------

(define (print-list label items)
  (cond
    [(null? items) (printf "~a (0):  (none)\n" label)]
    [else
     (printf "~a (~a):\n" label (length items))
     (define cols 5)
     (define widest (apply max (map string-length items)))
     (define col-w (+ widest 2))
     (let loop ([xs items] [n 0])
       (cond
         [(null? xs) (newline)]
         [else
          (printf "  ~a" (~a (car xs) #:min-width col-w))
          (when (and (> n 0) (zero? (modulo (+ n 1) cols))) (newline))
          (loop (cdr xs) (+ n 1))]))
     (when (not (zero? (modulo (length items) cols))) (newline))]))

(define (run-matrix nixos-schema darwin-schema)
  (define mods (modules))
  (define verdicts (make-hash))
  (define blockers (make-hash))
  (for ([m (in-list mods)])
    (define-values (v bs) (module-compat m nixos-schema darwin-schema))
    (hash-set! verdicts m v)
    (hash-set! blockers m bs))
  (values verdicts blockers))

(define (require-schemas!)
  (cond
    [(not (file-exists? NIXOS-SCHEMA))
     (eprintf "firn platform: NixOS schema cache missing.\n")
     (eprintf "  run: ./scripts/firn-extract-schema\n")
     (exit 1)]
    [(not (file-exists? DARWIN-SCHEMA))
     (eprintf "firn platform: darwin schema cache missing.\n")
     (eprintf "  run: ./scripts/firn-extract-schema --darwin\n")
     (exit 1)]))

(define (load-both)
  (require-schemas!)
  (define nixos-schema (load-schema-paths NIXOS-SCHEMA))
  (define darwin-schema (load-schema-paths DARWIN-SCHEMA))
  (define-values (verdicts blockers) (run-matrix nixos-schema darwin-schema))
  (values nixos-schema darwin-schema verdicts blockers))

(define (mods-with verdicts v)
  (sort (filter (λ (m) (eq? (hash-ref verdicts m) v))
                (hash-keys verdicts))
        string<?))

(define (handle-platform-list leaf)
  (define-values (nixos-schema darwin-schema verdicts blockers) (load-both))
  (define both       (mods-with verdicts 'both))
  (define linux-only (mods-with verdicts 'linux-only))
  (define no-data    (mods-with verdicts 'no-data))
  (case (string->symbol leaf)
    [(darwin) (print-list "darwin-compatible modules" both)]
    [(linux)
     (print-list "NixOS-only modules" linux-only)
     (when (pair? no-data)
       (newline)
       (print-list "modules with no detectable paths (skipped)" no-data))]
    [(all)
     (printf "Platform compatibility matrix (~a modules)\n"
             (length (modules)))
     (printf "Sources: NixOS schema (~a paths), darwin schema (~a paths)\n\n"
             (hash-count (schema-direct nixos-schema))
             (hash-count (schema-direct darwin-schema)))
     (print-list "darwin-compatible modules" both)
     (newline)
     (print-list "NixOS-only modules" linux-only)
     (when (pair? no-data)
       (newline)
       (print-list "no-data (HM-only or unparsable)" no-data))
     (newline)
     (printf "Note: this is a *schema* compatibility check — option paths the\n")
     (printf "module sets must exist on the target platform. It doesn't\n")
     (printf "verify package availability; modules that only set\n")
     (printf "environment.systemPackages will pass even if the package itself\n")
     (printf "has no darwin build. Try `darwin-rebuild build` to confirm.\n")]
    [else
     (eprintf "firn platform list: expected one of all|darwin|linux, got '~a'\n" leaf)
     (exit 1)]))

(define (handle-platform-show name)
  (define-values (nixos-schema darwin-schema verdicts blockers) (load-both))
  (cond
    [(member name (modules))
     (define v (hash-ref verdicts name 'no-data))
     (define bs (hash-ref blockers name '()))
     (printf "module:  ~a\n" name)
     (printf "verdict: ~a\n" v)
     (when (pair? bs)
       (printf "blocking paths:\n")
       (for ([p (in-list bs)]) (printf "  ~a\n" p)))]
    [else
     (eprintf "firn platform show: no module named '~a'\n" name)
     (exit 1)]))

(define (handle-platform-safelist _leaf)
  (define-values (_n _d verdicts _b) (load-both))
  (define both (mods-with verdicts 'both))
  (printf ";; darwin-compatible modules (auto-generated by `firn platform safelist all`).\n")
  (printf ";; Paste into mkDarwinSystem's imports list. ~a entries.\n" (length both))
  (printf "(lst")
  (for ([m (in-list both)])
    (printf "\n     ~s" m))
  (printf ")\n"))

(define node-edges
  (list
   (walk-edge "platform" "list"     "all|darwin|linux" 'all
              handle-platform-list
              "platform compat overview (all = full matrix; others = filtered)")
   (walk-edge "platform" "show"     "<name>" #f
              handle-platform-show
              "compat report for one module")
   (walk-edge "platform" "safelist" "all" 'all
              handle-platform-safelist
              "emit a darwin-safelist (lst …) snippet for flake.bnix")))
