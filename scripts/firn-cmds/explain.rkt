#lang racket/base

;; firn-cmds/explain — given an option path (or a validator-style error
;; line), show the option's schema entry, its declarations, similar
;; paths if it doesn't exist, and where in this repo it's referenced.
;;
;; Usage:
;;   firn schema explain services.openssh.enable
;;   firn schema explain "modules/foo.bnix:6:7: unknown option services.opensh.enable"
;;     ^ paste a validator error directly; firn extracts the path

(require racket/string
         racket/list
         racket/file
         racket/path
         json
         (only-in beagle/private/nixos-schema find-similar-strs)
         "util.rkt")

(provide node-edges)

(define CACHE-DIR (build-path ROOT ".beagle-cache"))
(define SCHEMA-PATH (build-path CACHE-DIR "schema.json"))
(define SUB-CACHE-PATH (build-path CACHE-DIR "schema-submodules.json"))

(define (load-schema-table)
  (define h (make-hash))
  (when (file-exists? SCHEMA-PATH)
    (for ([e (in-list (call-with-input-file SCHEMA-PATH read-json))])
      (hash-set! h (hash-ref e 'p) e)))
  (when (file-exists? SUB-CACHE-PATH)
    (with-handlers ([exn:fail? void])
      (define data (call-with-input-file SUB-CACHE-PATH read-json))
      (for* ([(_ entries) (in-hash (hash-ref data 'submodules (hash)))]
             [e (in-list entries)])
        (hash-set! h (hash-ref e 'p) e))))
  h)

(define (extract-path-from-input s)
  ;; Accept either:
  ;;   bare path   "services.openssh.enable"
  ;;   error line  "modules/x.rkt:6:7: unknown option services.X — did you mean: ..."
  ;;   error line  "modules/x.rkt:6:7: type mismatch at services.X: expected bool..."
  (cond
    [(regexp-match #px"unknown option ([a-zA-Z0-9._<>-]+)" s) => cadr]
    [(regexp-match #px"type mismatch at ([a-zA-Z0-9._<>-]+):" s) => cadr]
    [(regexp-match? #px"^[a-zA-Z][a-zA-Z0-9._<>-]+$" s) s]
    [else #f]))

(define (describe-type t inner)
  (cond
    [(member t '("listOf" "nullOr" "attrsOf" "lazyAttrsOf"))
     (define inner-t (and inner (hash-ref inner 't "?")))
     (define inner-inner (and inner (hash-ref inner 'inner #f)))
     (format "~a (~a)" t (describe-type inner-t inner-inner))]
    [(string? t) t]
    [else "?"]))

(define (find-references-in-repo path)
  ;; Find .bnix files that reference this path.
  (define escaped (regexp-quote path))
  (define re (regexp escaped))
  (sort
   (for/list ([f (in-directory ROOT)]
              #:when (let ([s (path->string f)])
                       (and (regexp-match? #rx"\\.bnix$" s)
                            (not (regexp-match? #rx"/scripts/" s))
                            (not (regexp-match? #rx"/tests/" s))
                            (not (regexp-match? #rx"/\\.beagle-cache/" s))
                            (not (regexp-match? #rx"/\\.git/" s))
                            (not (regexp-match? #rx"/\\.direnv/" s))
                            (regexp-match? re (file->string f)))))
     f)
   path<? #:key path->string))

;; firn schema extract [<host>]  — regenerate options schema cache
;; firn schema packages [<host>] — regenerate package name cache

(define (handle-schema-extract leaf)
  (define host (if (equal? leaf "current") (current-hostname) leaf))
  (printf ">> firn-extract-schema ~a\n" host)
  (unless (sh (path->string (in-repo "scripts" "firn-extract-schema")) host)
    (eprintf "firn schema extract: failed.\n") (exit 1)))

(define (handle-schema-explain leaf)
  (cond
    [(or (not leaf) (equal? leaf ""))
     (eprintf "Usage: firn schema explain <option-path | validator-error-line>\n")
     (exit 2)]
    [else
     (define raw leaf)
     (define path (extract-path-from-input raw))
     (cond
       [(not path)
        (eprintf "firn explain: couldn't extract an option path from: ~a\n" raw)
        (exit 1)]
       [else
        (define schema (load-schema-table))
        (define entry (hash-ref schema path #f))
        (cond
          [entry
           (printf "path:  ~a\n" path)
           (define t (hash-ref entry 't "?"))
           (define inner (hash-ref entry 'inner #f))
           (printf "type:  ~a\n" (describe-type t inner))
           (define enum (hash-ref entry 'enum #f))
           (when enum
             (printf "enum:  ~a\n"
                     (string-join (map (λ (v) (format "~s" v)) enum) ", ")))
           (define decls (hash-ref entry 'declarations '()))
           (when (pair? decls)
             (printf "defined in:\n")
             (for ([d (in-list decls)]) (printf "  ~a\n" d)))
           (define refs (find-references-in-repo path))
           (cond
             [(null? refs) (printf "referenced in: (nowhere in this repo)\n")]
             [else
              (printf "referenced in this repo:\n")
              (for ([f (in-list refs)])
                (printf "  ~a\n" (relative-to-repo f)))])]
          [else
           (eprintf "no exact match for ~a\n" path)
           (define sims (find-similar-strs path (hash-keys schema) 5))
           (cond
             [(null? sims)
              (eprintf "  no similar option paths found.\n")]
             [else
              (eprintf "did you mean:\n")
              (for ([s (in-list sims)]) (eprintf "  ~a\n" s))])
           (exit 1)])])]))

(define node-edges
  (list
   (walk-edge "schema" "explain" "<path>" #f
              handle-schema-explain
              "show schema entry + repo references for an option")
   (walk-edge "schema" "extract" "[<host>]" 'current-host
              handle-schema-extract
              "regenerate options schema cache from nix eval")))
