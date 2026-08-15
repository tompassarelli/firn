#lang racket/base

;; firn-cmds/toggle — host-level inspection.
;;
;; Module enable/disable now lives in firn-cmds/tag-edit.rkt — it
;; operates on hosts/<host>/enabled-tags.bnix, not configuration.bnix.
;; This file keeps:
;;
;;   firn module status [all]    list enabled modules on the default host
;;   firn host status [<host>]   all enabled modules for a host
;;
;; "Enabled" here is read from the host's configuration.bnix —
;; Direct module toggles. Tag-driven enables live in
;; hosts/<host>/_generated-enables.bnix and reflect there too once
;; tag resolution has emitted them.

(require racket/file
         racket/string
         "util.rkt")

(provide node-edges)

;; ---------- status ----------
;;
;; Walks the host's (host-file …) body as datums and records every
;; <path>.enable = #t/#f toggle whether the source form is
;; `(enable A B C)`, `(set X.enable #t/#f)`, or
;; `(set X (att (enable BOOL) (sub.enable BOOL) ...))`.

(define (path-from-arg arg)
  (cond
    [(symbol? arg) (symbol->string arg)]
    [(and (pair? arg) (eq? (car arg) 'quote)
          (pair? (cdr arg)) (symbol? (cadr arg)))
     (symbol->string (cadr arg))]
    [(string? arg) arg]
    [else #f]))

(define (literal-bool? v) (or (eq? v #t) (eq? v #f)))

(define (read-host-forms host)
  (define raw (file->string (host-config-source host)))
  (define stripped (regexp-replace #rx"^#lang [^\n]*\n" raw ""))
  (with-handlers ([exn:fail? (λ (_) '())])
    (define port (open-input-string stripped))
    (define top (read port))
    (cond
      [(and (pair? top) (eq? (car top) 'host-file)) (cdr top)]
      [else '()])))

(define (collect-att-clauses! tgl path clauses)
  (for ([clause (in-list clauses)])
    (when (and (pair? clause) (= (length clause) 2))
      (define sub (path-from-arg (car clause)))
      (define sv (cadr clause))
      (when (and sub (literal-bool? sv))
        (cond
          [(string=? sub "enable")
           (hash-set! tgl (string-append path ".enable") sv)]
          [(regexp-match? #rx"\\.enable$" sub)
           (hash-set! tgl (string-append path "." sub) sv)])))))

(define (collect-toggles forms)
  (define tgl (make-hash))
  (for ([form (in-list forms)])
    (when (pair? form)
      (case (car form)
        [(enable)
         (for ([a (in-list (cdr form))])
           (define p (path-from-arg a))
           (when p (hash-set! tgl (string-append p ".enable") #t)))]
        [(set)
         (define args (cdr form))
         (when (= (length args) 2)
           (define path (path-from-arg (car args)))
           (define val (cadr args))
           (cond
             [(and path (literal-bool? val)
                   (regexp-match? #rx"\\.enable$" path))
              (hash-set! tgl path val)]
             [(and path (pair? val) (eq? (car val) 'att))
              (collect-att-clauses! tgl path (cdr val))]))])))
  tgl)

(define (strip-enable-suffix s)
  (regexp-replace #rx"\\.enable$" s ""))

(define (handle-module-status leaf)
  (cond
    [(equal? leaf "all") (print-flat-status (current-hostname))]
    [else
     (eprintf "firn module status: expected 'all', got '~a'\n" leaf)
     (exit 1)]))

(define (handle-host-status leaf)
  (define host (if (or (equal? leaf "current") (equal? leaf "all"))
                   (current-hostname)
                   leaf))
  (print-flat-status host))

(define (print-flat-status host)
  (define forms (read-host-forms host))
  (define toggles (collect-toggles forms))
  (printf "Enabled in ~a:\n" host)
  (define enabled-keys
    (sort (for/list ([(k v) (in-hash toggles)] #:when (eq? v #t)) k) string<?))
  (for ([k (in-list enabled-keys)])
    (when (regexp-match? #rx"^myConfig\\.modules\\." k)
      (printf "  ~a\n" (strip-enable-suffix k))))
  (define disabled-keys
    (sort (for/list ([(k v) (in-hash toggles)] #:when (eq? v #f)) k) string<?))
  (define disabled-filtered
    (filter (λ (k) (regexp-match? #rx"^myConfig\\.modules\\." k))
            disabled-keys))
  (unless (null? disabled-filtered)
    (printf "\nExplicitly disabled in ~a:\n" host)
    (for ([k (in-list disabled-filtered)])
      (printf "  ~a\n" (strip-enable-suffix k)))))

;; ---------- registration ----------

(define node-edges
  (list
   (walk-edge "module" "status"  "all"    'all
              handle-module-status
              "list enabled modules on the default host (configuration.bnix)")
   (walk-edge "host"   "status"  "<host>" 'current-host
              handle-host-status
              "all modules enabled directly in a host's configuration.bnix")))
