#!/usr/bin/env racket
#lang racket/base
(require racket/file racket/string racket/port racket/runtime-path)

(define (find-bnix-files dir)
  (for/fold ([acc '()])
            ([p (in-directory dir)])
    (if (regexp-match? #rx"\\.bnix$" (path->string p))
      (cons p acc)
      acc)))

(define (corresponding-nix bnix-path)
  (define s (path->string bnix-path))
  (define nix-s (regexp-replace #rx"\\.bnix$" s ".nix"))
  (and (file-exists? nix-s) nix-s))

(define pass 0)
(define fail 0)
(define err 0)
(define fail-list '())

(define-runtime-path test-dir ".")
(define repo-root (simplify-path (build-path test-dir 'up)))
(define all-bnix (sort (find-bnix-files (build-path repo-root "modules"))
                       string<? #:key path->string))

(for ([bnix (in-list all-bnix)])
  (define nix-path (corresponding-nix bnix))
  (cond
    [(not nix-path)
     (set! err (add1 err))
     (printf "ERR  ~a (no .nix)\n" (path->string bnix))]
    [else
     (define expected (string-trim (file->string nix-path)))
     (define actual-result
       (with-handlers ([exn:fail? (lambda (e) (cons 'error (exn-message e)))])
         (define out
           (parameterize ([current-error-port (open-output-nowhere)])
             (with-output-to-string
               (lambda ()
                 (dynamic-require (string->path (path->string bnix)) #f)))))
         (cons 'ok (string-trim out))))
     (cond
       [(eq? (car actual-result) 'error)
        (set! err (add1 err))
        (printf "ERR  ~a: ~a\n" (path->string bnix) (cdr actual-result))]
       [(string=? (cdr actual-result) expected)
        (set! pass (add1 pass))]
       [else
        (set! fail (add1 fail))
        (set! fail-list (cons (path->string bnix) fail-list))
        (printf "FAIL ~a\n" (path->string bnix))])]))

(printf "\n~a PASS, ~a FAIL, ~a ERR out of ~a total\n"
        pass fail err (+ pass fail err))

(when (> fail 0)
  (printf "\nFailed files:\n")
  (for ([f (in-list (reverse fail-list))])
    (printf "  ~a\n" f)))
