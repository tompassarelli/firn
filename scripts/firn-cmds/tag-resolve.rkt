#lang racket/base

;; firn-cmds/tag-resolve — tag-driven host composition resolver.
;;
;; Reads each module's :tags / :tags-opt-in / :tag-overrides clauses
;; from modules/<name>/default.bnix and each host's :enabled / :disabled
;; vector from hosts/<host>/enabled-tags.bnix, then computes the active
;; module set per the resolution algorithm:
;;
;;   active := union over each enabled-tag T of (
;;     defaults := { m | T ∈ m.:tags }
;;     minuses  := { x | -x ∈ T's edit-flags }
;;     pluses   := { x | +x ∈ T's edit-flags AND T ∈ x.:tags-opt-in }
;;     (defaults \ minuses) ∪ pluses
;;   )
;;   enabled-modules := active \ host.:disabled
;;
;; Plus :tag-overrides — for each active M, for each tag T where
;; M ∈ T's defaults (not pluses), apply M.:tag-overrides[T] as
;; mkDefault entries on M's options.
;;
;; Outputs:
;;   firn tag resolve <host>            — pretty-print the resolution
;;   firn tag resolve <host> --emit     — write hosts/<host>/_generated-enables.bnix
;;   firn tag resolve all               — pretty-print every host
;;   firn tag resolve all --emit        — emit for every host
;;
;; Also exports `resolve-host` for use by tests and by firn-build's
;; pre-build hook (see firn-cmds/pipeline.rkt).

(require racket/file
         racket/list
         racket/path
         racket/port
         racket/string
         racket/format
         json
         beagle/private/parse        ; #29: the real beagle reader (read-beagle-syntax)
         "util.rkt")

(provide node-edges
         resolve
         resolve-host
         resolve-and-emit!
         read-bnix-forms
         find-module-body
         map-datum->pairs
         keyword-symbol?
         keyword-name
         extract-module-tags
         extract-host-tags
         clear-module-index-cache!
         emit-host-enables-bnix
         (struct-out resolution)
         (struct-out tag-validation-error)
         (struct-out module-tags)
         (struct-out host-tags))

;; ---------- bnix reader ----------
;;
;; #29: use the REAL beagle reader (read-beagle-syntax) — not Racket's reader.
;; The old Racket-reader hack couldn't parse beagle-only surface (`~''…''`,
;; `${…}`, `#…`, `|…|`) and FELL BACK to a regex `:tags` scan that FALSE-MATCHED
;; coincidental `:tags` nested in nix builder calls (niri's writePython3Bin, lem's
;; overrideLispAttrs were enabled by that accident — see #25). The beagle reader
;; reads ALL beagle/nix surface, so there is one parse path, no regex fallback,
;; no false-match class. `debeagle` normalizes the reader's tagged containers
;; (`(#%map …)`/`(#%brackets …)`/`(#%set …)`) to the SAME flat-list shape the
;; downstream extraction already expects (`{:k v}`→`(:k v)`, `[a b]`→`(a b)`).

(define (debeagle d)
  (cond
    [(and (pair? d) (memq (car d) '(#%map #%brackets #%set))) (map debeagle (cdr d))]
    [(pair? d) (cons (debeagle (car d)) (debeagle (cdr d)))]
    [else d]))

(define (read-bnix-forms path)
  ;; Top-level datums via the beagle reader, container-tags normalized away.
  ;; Raises loudly on a malformed source (no silent empty/regex fallback).
  ;; (A leading `#lang beagle/X` reads as a `(define-target X)` form, which the
  ;; module-body / host-map searches skip — harmless.)
  (map (lambda (s) (debeagle (syntax->datum s))) (read-beagle-syntax path)))

;; ---------- keyword utilities ----------

(define (keyword-symbol? s)
  ;; In bnix, keyword keys read as symbols starting with ':'.
  (and (symbol? s)
       (let ([str (symbol->string s)])
         (and (positive? (string-length str))
              (char=? (string-ref str 0) #\:)))))

(define (keyword-name s)
  ;; Strip the leading ':' from a keyword-symbol, e.g. :tags → "tags".
  (substring (symbol->string s) 1))

(define (map-datum->pairs datum)
  ;; Convert a Racket-reader output of a bnix map like
  ;;   (:k1 v1 :k2 v2 …)
  ;; into a hash table keyed by the keyword-name string.
  ;; Non-keyword interleavings (a buggy map) are skipped silently — the
  ;; structural checker beagle-syntax catches those; the resolver isn't
  ;; the right tool to re-diagnose them.
  (cond
    [(not (list? datum)) (hash)]
    [else
     (let loop ([xs datum] [h (hash)])
       (cond
         [(null? xs) h]
         [(null? (cdr xs)) h]
         [(keyword-symbol? (car xs))
          (loop (cddr xs) (hash-set h (keyword-name (car xs)) (cadr xs)))]
         [else (loop (cdr xs) h)]))]))

;; ---------- module-side extraction ----------
;;
;; Walks every top-level datum in modules/<name>/default.bnix looking
;; for the `nix/module` form's body map, then extracts :tags,
;; :tags-opt-in, and :tag-overrides. Tolerant — a module with no tags
;; returns an empty record.

(struct module-tags (name tags opt-in overrides) #:transparent)

(define (find-module-body forms)
  ;; In a default.bnix, the relevant form is (nix/module [args] {body}).
  ;; The body is the last argument to nix/module. There may be a
  ;; surrounding `let` — handle one level of unwrapping.
  (for/or ([form (in-list forms)])
    (and (pair? form)
         (eq? (car form) 'nix/module)
         (find-body-map form))))

(define (find-body-map nix-module-form)
  ;; (nix/module [args] body) — body is the third element. Body may be
  ;; a (let [...] map) wrapping the actual map; unwrap up to a few levels.
  (cond
    [(or (not (pair? nix-module-form))
         (not (eq? (car nix-module-form) 'nix/module))
         (< (length nix-module-form) 3))
     #f]
    [else
     (let unwrap ([body (caddr nix-module-form)] [depth 0])
       (cond
         [(> depth 4) #f]
         [(and (list? body) (pair? body) (keyword-symbol? (car body))) body]
         [(and (pair? body) (eq? (car body) 'let) (>= (length body) 3))
          (unwrap (caddr body) (+ depth 1))]
         [(and (pair? body) (eq? (car body) 'lib.mkIf) (>= (length body) 3))
          (unwrap (caddr body) (+ depth 1))]
         [else #f]))]))

(define (parse-symbol-list datum)
  ;; A :tags value reads as (sym1 sym2 ...) — convert to list of strings.
  (cond
    [(not (list? datum)) '()]
    [else
     (for/list ([x (in-list datum)] #:when (symbol? x))
       (symbol->string x))]))

(define (parse-tag-overrides datum)
  ;; :tag-overrides reads as (tagname (:opt-path val …) tagname2 …).
  ;; Returns a hash: tagname-string → (list of (path . value) pairs).
  (cond
    [(not (list? datum)) (hash)]
    [else
     (let loop ([xs datum] [h (hash)])
       (cond
         [(null? xs) h]
         [(null? (cdr xs)) h]
         [(symbol? (car xs))
          (define tag (symbol->string (car xs)))
          (define inner (cadr xs))
          (define pairs
            (let inner-loop ([ys (if (list? inner) inner '())] [acc '()])
              (cond
                [(null? ys) (reverse acc)]
                [(null? (cdr ys)) (reverse acc)]
                [(keyword-symbol? (car ys))
                 (inner-loop (cddr ys)
                             (cons (cons (keyword-name (car ys)) (cadr ys)) acc))]
                [else (inner-loop (cdr ys) acc)])))
          (loop (cddr xs) (hash-set h tag pairs))]
         [else (loop (cdr xs) h)]))]))

;; Heuristic short-circuit: most modules have no tag clauses. Reading
;; the whole .bnix with Racket's reader stumbles on bnix-only syntax
;; (~''/${…}/#$/| in symbols), so we first grep the file for any of
;; :tags / :tags-opt-in / :tag-overrides. Files with none short-circuit
;; to an empty record, no reader involved. Files that DO have a tag
;; clause must be parseable — bnix and Racket s-expr syntax overlap
;; enough for the clauses themselves to read cleanly, and a parse
;; failure on a tag-bearing module is a real bug we want to surface.
(define TAG-CLAUSE-RE #px":tags(-opt-in|-overrides)?[\\s\\[]")

(define (file-has-tag-clause? path)
  (with-handlers ([exn:fail? (λ (_) #f)])
    (regexp-match? TAG-CLAUSE-RE (file->string path))))

;; (#29 removed extract-tags-regex + its helpers — the regex fallback that
;;  false-matched coincidental builder `:tags`. The beagle reader now parses
;;  every module, so `:tags` is always extracted structurally.)

(define (extract-module-tags name)
  ;; Reads modules/<name>/default.bnix and returns a module-tags struct.
  ;; Missing file or no nix/module form → empty record (no tags).
  (define path (in-repo "modules" name "default.bnix"))
  (cond
    [(not (file-exists? path)) (module-tags name '() '() (hash))]
    [(not (file-has-tag-clause? path)) (module-tags name '() '() (hash))]
    [else
     ;; #29: single parse path — the beagle reader reads ALL beagle/nix surface,
     ;; so :tags is extracted STRUCTURALLY from the nix/module body map. No
     ;; regex fallback (that's what false-matched coincidental builder `:tags`).
     ;; A genuine read/parse error surfaces loudly (read-bnix-forms raises).
     (define forms (read-bnix-forms path))
     (define body (find-module-body forms))
     (define h (map-datum->pairs (or body '())))
     (module-tags name
                  (parse-symbol-list (hash-ref h "tags" '()))
                  (parse-symbol-list (hash-ref h "tags-opt-in" '()))
                  (parse-tag-overrides (hash-ref h "tag-overrides" '())))]))

;; ---------- host-side extraction ----------

(struct host-tags (host enabled disabled platform) #:transparent)
;; enabled: list of (cons tag-string (list of edit-flag entries))
;;   each edit-flag is (cons 'plus modname-string) or (cons 'minus modname-string)
;; disabled: list of module-name strings

(define (parse-host-enabled-entry e)
  ;; Either a bare symbol → (cons "<tag>" '()), or a list
  ;; (tag-sym flag-sym …) → (cons "<tag>" (list of (op . name))).
  ;; Returns #f for unrecognised shapes.
  (cond
    [(symbol? e) (cons (symbol->string e) '())]
    [(and (list? e) (pair? e) (symbol? (car e)))
     (define tag (symbol->string (car e)))
     (define flags
       (for/list ([f (in-list (cdr e))] #:when (symbol? f))
         (define s (symbol->string f))
         (cond
           [(and (positive? (string-length s)) (char=? (string-ref s 0) #\-))
            (cons 'minus (substring s 1))]
           [(and (positive? (string-length s)) (char=? (string-ref s 0) #\+))
            (cons 'plus (substring s 1))]
           [else #f])))
     (cons tag (filter values flags))]
    [else #f]))

(define (extract-host-tags host)
  ;; Reads hosts/<host>/enabled-tags.bnix and returns a host-tags
  ;; struct. Missing file → empty record (no tags enabled).
  (define path (in-repo "hosts" host "enabled-tags.bnix"))
  (cond
    [(not (file-exists? path)) (host-tags host '() '() "linux")]
    [else
     (with-handlers ([exn:fail?
                      (λ (e)
                        (eprintf "tag-resolve: failed to read ~a: ~a\n"
                                 (relative-to-repo path) (exn-message e))
                        (host-tags host '() '() "linux"))])
       (define forms (read-bnix-forms path))
       ;; Find the first map-shaped form: either bare (:enabled … :disabled …)
       ;; or (def NAME {map}) — accept both.
       (define raw-map
         (or (for/or ([f (in-list forms)])
               (cond
                 [(and (list? f) (pair? f) (keyword-symbol? (car f))) f]
                 [(and (pair? f) (eq? (car f) 'def) (>= (length f) 3)
                       (list? (caddr f)) (pair? (caddr f))
                       (keyword-symbol? (car (caddr f))))
                  (caddr f)]
                 [else #f]))
             '()))
       (define h (map-datum->pairs raw-map))
       (define enabled-raw (hash-ref h "enabled" '()))
       (define disabled-raw (hash-ref h "disabled" '()))
       (define platform-raw (hash-ref h "platform" 'linux))
       (host-tags host
                  (filter values (map parse-host-enabled-entry
                                      (if (list? enabled-raw) enabled-raw '())))
                  (parse-symbol-list (if (list? disabled-raw) disabled-raw '()))
                  (if (symbol? platform-raw)
                      (symbol->string platform-raw)
                      "invalid")))]))

;; ---------- resolution ----------

(struct resolution (host
                    active        ; sorted list of activated module names
                    per-tag       ; hash: tag → (list of modname strings)
                    overrides     ; hash: modname → (list of (path . value))
                    errors        ; list of tag-validation-error
                    warnings)     ; list of strings
  #:transparent)

(struct tag-validation-error (kind tag mod hint) #:transparent)
;; kind ∈ '(unknown-tag opt-in-mismatch unknown-disabled)

(define (build-module-index)
  ;; Returns hash: modname → module-tags
  (define h (make-hash))
  (for ([m (in-list (modules))])
    (hash-set! h m (extract-module-tags m)))
  h)

(define (tag-universe module-index)
  ;; Returns hash: tag → (list of modname strings via :tags)
  ;;        plus    tag → (list of modname strings via :tags-opt-in)
  ;; under separate hashes.
  (define defaults (make-hash))
  (define opt-in (make-hash))
  (for ([(name mt) (in-hash module-index)])
    (for ([t (in-list (module-tags-tags mt))])
      (hash-set! defaults t (cons name (hash-ref defaults t '()))))
    (for ([t (in-list (module-tags-opt-in mt))])
      (hash-set! opt-in t (cons name (hash-ref opt-in t '())))))
  (values defaults opt-in))

;; Module index is cached: the universe of (modname → tag clauses) is
;; identical across hosts, so we build it once per process. The cache
;; is invalidated automatically because `firn` is a fresh process per
;; invocation; long-running callers (tests, daemon) can call
;; (clear-module-index-cache!) explicitly.
(define cached-module-index #f)
(define (clear-module-index-cache!) (set! cached-module-index #f))
(define (get-module-index)
  (unless cached-module-index
    (set! cached-module-index (build-module-index)))
  cached-module-index)

(define (resolve-host host)
  ;; Compute the resolution struct for `host` by reading the live repo.
  ;; Pure-ish — does not write files. Caller decides what to do with
  ;; the result. For tests, use (resolve module-index host-tags-record).
  (define ht (extract-host-tags host))
  (define allowed
    (case (string->symbol (host-tags-platform ht))
      [(linux) #f]
      [(darwin)
       (define path (in-repo "config" "darwin-modules.json"))
       (unless (file-exists? path)
         (error 'resolve-host "Darwin module allowlist is missing: ~a" path))
       (define value (call-with-input-file path read-json))
       (unless (and (list? value) (andmap string? value))
         (error 'resolve-host "Darwin module allowlist must be a JSON array of strings: ~a" path))
       value]
      [else #f]))
  (resolve (get-module-index) ht #:allowed-modules allowed))

(define (resolve module-index ht #:allowed-modules [allowed-modules #f])
  ;; Pure resolution kernel: takes a module-index (hash: name → module-tags)
  ;; and a host-tags struct, returns a resolution struct. No I/O.
  (define-values (defaults opt-in) (tag-universe module-index))
  (define host (host-tags-host ht))
  (define platform (host-tags-platform ht))
  (define enabled-entries (host-tags-enabled ht))
  (define disabled (host-tags-disabled ht))

  (define errors '())
  (define warnings '())
  (define per-tag (make-hash))
  (define active-set (make-hash))     ; modname → #t
  (define override-applies (make-hash)) ; modname → list of (tag . override-pairs)
  (define allowed-set (and allowed-modules (list->hash-set allowed-modules)))

  (unless (member platform '("linux" "darwin"))
    (set! errors
          (cons (tag-validation-error
                 'unknown-platform #f #f
                 (format "host '~a' declares unsupported platform '~a'"
                         host platform))
                errors)))

  (for ([entry (in-list enabled-entries)])
    (define tag (car entry))
    (define flags (cdr entry))

    ;; Unknown tag check: a tag is "known" iff at least one module
    ;; lists it in :tags or :tags-opt-in.
    (define known? (or (hash-has-key? defaults tag)
                       (hash-has-key? opt-in tag)))
    (unless known?
      (set! errors
            (cons (tag-validation-error
                   'unknown-tag tag #f
                   (format "host '~a' enables tag '~a' but no module declares it"
                           host tag))
                  errors)))

    (define def-set (list->hash-set (hash-ref defaults tag '())))
    (define minuses
      (for/list ([f (in-list flags)] #:when (eq? (car f) 'minus))
        (cdr f)))
    (define pluses
      (for/list ([f (in-list flags)] #:when (eq? (car f) 'plus))
        (cdr f)))

    ;; Warn on -name when name isn't in the tag's defaults (likely typo).
    (for ([m (in-list minuses)])
      (unless (hash-has-key? def-set m)
        (set! warnings
              (cons (format "host '~a' tag '~a': -~a but ~a is not in this tag's default set"
                            host tag m m)
                    warnings))))

    ;; Validate +name: module must list this tag in :tags-opt-in.
    (define opt-in-set (list->hash-set (hash-ref opt-in tag '())))
    (for ([m (in-list pluses)])
      (unless (hash-has-key? opt-in-set m)
        (set! errors
              (cons (tag-validation-error
                     'opt-in-mismatch tag m
                     (format "host '~a' tag '~a': +~a but module '~a' does not list tag '~a' in :tags-opt-in"
                             host tag m m tag))
                    errors))))

    ;; Compute this tag's contribution: (defaults \ minuses) ∪ pluses
    (define minus-set (list->hash-set minuses))
    (define defaults-here (hash-ref defaults tag '()))
    (define from-defaults
      (filter (λ (m) (and (not (hash-has-key? minus-set m))
                          (or (not allowed-set) (hash-has-key? allowed-set m))))
              defaults-here))
    (define from-pluses
      (filter (λ (m) (and (hash-has-key? opt-in-set m)
                          (or (not allowed-set) (hash-has-key? allowed-set m))))
              pluses))
    (define contribution (sort (remove-duplicates (append from-defaults from-pluses))
                               string<?))
    (hash-set! per-tag tag contribution)
    (for ([m (in-list contribution)])
      (hash-set! active-set m #t))

    ;; Record :tag-overrides for default-on memberships only
    (for ([m (in-list from-defaults)])
      (define mt (hash-ref module-index m #f))
      (when mt
        (define ovs (hash-ref (module-tags-overrides mt) tag #f))
        (when (pair? ovs)
          (hash-set! override-applies m
                     (cons (cons tag ovs) (hash-ref override-applies m '())))))))

  ;; Validate :disabled entries reference real modules.
  (for ([m (in-list disabled)])
    (unless (hash-has-key? module-index m)
      (set! errors
            (cons (tag-validation-error
                   'unknown-disabled #f m
                   (format "host '~a' :disabled lists '~a' but no such module exists"
                           host m))
                  errors))))

  ;; Subtract :disabled
  (for ([m (in-list disabled)])
    (hash-remove! active-set m)
    (hash-remove! override-applies m))

  (define active (sort (hash-keys active-set) string<?))

  ;; Flatten override-applies into modname → list of (path . value)
  (define overrides-out (make-hash))
  (for ([m (in-list active)])
    (define triples (hash-ref override-applies m '()))
    (define pairs
      (apply append (for/list ([t (in-list triples)]) (cdr t))))
    (when (pair? pairs)
      (hash-set! overrides-out m pairs)))

  (resolution host active per-tag overrides-out (reverse errors) (reverse warnings)))

(define (list->hash-set xs)
  (define h (make-hash))
  (for ([x (in-list xs)]) (hash-set! h x #t))
  h)

;; ---------- emission ----------
;;
;; Writes hosts/<host>/_generated-enables.bnix from a resolution. The
;; host's configuration.bnix is expected to (import "_generated-enables.nix")
;; in its `:imports` clause. We emit beagle/nix source and let
;; firn-build regenerate the .nix on the next pass.

(define (datum->bnix-literal d)
  ;; Render a Racket datum back to a beagle/nix literal string. We only
  ;; need a small slice — bool, number, string, symbol/path-like — since
  ;; :tag-overrides values are limited by the audit (one bool, one string).
  (cond
    [(boolean? d) (if d "true" "false")]
    [(number? d) (number->string d)]
    [(string? d) (format "~v" d)]
    [(symbol? d) (symbol->string d)]
    [(null? d) "[]"]
    [(list? d)
     ;; Heuristic: a list whose first elem is a keyword-symbol → map.
     ;; Otherwise → vector.
     (cond
       [(and (pair? d) (keyword-symbol? (car d)))
        (define inner
          (let loop ([xs d] [acc '()])
            (cond
              [(null? xs) (reverse acc)]
              [(null? (cdr xs)) (reverse acc)]
              [(keyword-symbol? (car xs))
               (loop (cddr xs)
                     (cons (format "~a ~a"
                                   (symbol->string (car xs))
                                   (datum->bnix-literal (cadr xs)))
                           acc))]
              [else (loop (cdr xs) acc)])))
        (string-append "{" (string-join inner " ") "}")]
       [else
        (string-append "[" (string-join (map datum->bnix-literal d) " ") "]")])]
    [else (format "~a" d)]))

(define (emit-host-enables-bnix res)
  ;; Returns a string suitable for writing to
  ;; hosts/<host>/_generated-enables.bnix.
  (define host (resolution-host res))
  (define active (resolution-active res))
  (define overrides (resolution-overrides res))
  (define out (open-output-string))
  (fprintf out "#lang beagle/nix\n\n")
  (fprintf out ";; Auto-generated by `firn tag resolve ~a --emit`.\n" host)
  (fprintf out ";; Do not edit by hand. Source of truth:\n")
  (fprintf out ";;   modules/*/default.bnix  (:tags, :tags-opt-in, :tag-overrides)\n")
  (fprintf out ";;   hosts/~a/enabled-tags.bnix\n\n" host)
  (fprintf out "(ns _generated-enables)\n\n")
  (fprintf out "(nix/module [config lib pkgs ...]\n")
  (fprintf out "  {")
  (define lines '())
  (for ([m (in-list active)])
    (set! lines
          (cons (format ":myConfig.modules.~a.enable (lib.mkDefault true)" m)
                lines))
    (define ovs (hash-ref overrides m '()))
    (for ([pair (in-list ovs)])
      (define path (car pair))
      (define val (cdr pair))
      (set! lines
            (cons (format ":~a (lib.mkDefault ~a)" path (datum->bnix-literal val))
                  lines))))
  (define joined
    (string-join (reverse lines) "\n   "))
  (fprintf out "~a})\n" joined)
  (get-output-string out))

(define (resolve-and-emit! host #:emit? [emit? #f] #:quiet? [quiet? #f])
  ;; Runs resolution, optionally writes the generated file, returns the
  ;; resolution struct. Exits non-zero on validation errors.
  (define res (resolve-host host))
  (when (pair? (resolution-errors res))
    (for ([e (in-list (resolution-errors res))])
      (eprintf "tag-resolve: ~a\n" (tag-validation-error-hint e)))
    (exit 1))
  (when (pair? (resolution-warnings res))
    (for ([w (in-list (resolution-warnings res))])
      (eprintf "tag-resolve: warning: ~a\n" w)))
  (when emit?
    (define path (in-repo "hosts" host "_generated-enables.bnix"))
    (define text (emit-host-enables-bnix res))
    (define existing (and (file-exists? path) (file->string path)))
    (cond
      [(equal? existing text)
       (unless quiet?
         (printf "tag-resolve: ~a is up to date (~a modules)\n"
                 (relative-to-repo path) (length (resolution-active res))))]
      [else
       (with-output-to-file path #:exists 'replace
         (λ () (display text)))
       (unless quiet?
         (printf "tag-resolve: wrote ~a (~a modules)\n"
                 (relative-to-repo path) (length (resolution-active res))))]))
  res)

;; ---------- pretty-printer ----------

(define (pretty-print-resolution res)
  (define host (resolution-host res))
  (define per-tag (resolution-per-tag res))
  (define active (resolution-active res))
  (define overrides (resolution-overrides res))
  (printf "Host: ~a\n\n" host)
  (define tags (sort (hash-keys per-tag) string<?))
  (cond
    [(null? tags) (printf "  (no tags enabled)\n")]
    [else
     (printf "Per-tag contributions:\n")
     (for ([t (in-list tags)])
       (define mods (hash-ref per-tag t '()))
       (printf "  ~a (~a):\n" t (length mods))
       (cond
         [(null? mods) (printf "    (none)\n")]
         [else (for ([m (in-list mods)]) (printf "    ~a\n" m))]))])
  (printf "\nActive modules (~a):\n" (length active))
  (for ([m (in-list active)])
    (define ovs (hash-ref overrides m #f))
    (cond
      [(pair? ovs)
       (printf "  ~a\n" m)
       (for ([p (in-list ovs)])
         (printf "      ~a = ~a\n" (car p) (datum->bnix-literal (cdr p))))]
      [else (printf "  ~a\n" m)])))

;; ---------- handler ----------

(define (handle-tag-resolve leaf)
  ;; leaf is "<host>" or "<host>+emit" or "all" or "all+emit". We use
  ;; '+emit' as the suffix marker so firn's existing leaf-as-string
  ;; convention still works without extra CLI surgery.
  (define emit?
    (or (regexp-match? #rx"\\+emit$" leaf)
        (getenv "FIRN_TAG_EMIT")))
  (define target
    (cond
      [(regexp-match? #rx"\\+emit$" leaf)
       (substring leaf 0 (- (string-length leaf) 5))]
      [else leaf]))
  (cond
    [(equal? target "all")
     (define tag-hosts
       (filter (λ (h) (file-exists? (in-repo "hosts" h "enabled-tags.bnix")))
               (hosts)))
     (cond
       [(and emit? (null? tag-hosts))
        ;; --emit + no tag-driven hosts: silent no-op so firn-build can
        ;; safely call us unconditionally.
        (void)]
       [else
        (for ([h (in-list (if emit? tag-hosts (hosts)))])
          (define res (resolve-and-emit! h #:emit? emit?))
          (cond
            [emit? (void)]
            [else (pretty-print-resolution res)
                  (newline)]))])]
    [(member target (hosts))
     (define res (resolve-and-emit! target #:emit? emit?))
     (unless emit? (pretty-print-resolution res))]
    [else
     (eprintf "firn tag resolve: no such host '~a' (have: ~a)\n"
              target (string-join (hosts) ", "))
     (exit 1)]))

(define node-edges
  (list
   (walk-edge "tag" "resolve" "<host>|all [+emit]" 'current-host
              handle-tag-resolve
              "resolve enabled-tags → active module set; +emit writes _generated-enables.bnix")))
