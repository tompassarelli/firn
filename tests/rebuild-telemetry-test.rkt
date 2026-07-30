#lang racket/base

(require json
         rackunit
         racket/file
         racket/list
         (submod "../scripts/firn-cmds/rebuild.rkt" test-support))

(define (clock-from values)
  (define remaining (box values))
  (λ ()
    (define value (car (unbox remaining)))
    (set-box! remaining (cdr (unbox remaining)))
    value))

(define (read-events path)
  (call-with-input-file path
    (λ (in)
      (for/list ([line (in-lines in)])
        (string->jsexpr line)))))

(define scratch (make-temporary-file "firn-rebuild-telemetry-test-~a" 'directory))

(dynamic-wind
  void
  (λ ()
    (define trace-path (build-path scratch "trace.jsonl"))
    (define trace-env
      (environment-variables-copy (current-environment-variables)))
    (environment-variables-set! trace-env #"FIRN_TRACE_ID" #"trace-test")
    (environment-variables-set! trace-env #"FIRN_TRACE_PATH" (path->bytes trace-path))
    (parameterize ([current-environment-variables trace-env]
                   [current-monotonic-clock
                    (clock-from '(10.25 14.75 20.0 28.125))])
      (check-true (call-with-trace-span "success phase" (λ () #t)))
      (check-false
       (call-with-trace-span "failure phase"
         (λ () (error 'expected "phase failure")))))

    (define events (read-events trace-path))
    (check-equal? (map (λ (event) (hash-ref event 'schema)) events)
                  (make-list 4 "firn.rebuild/v1"))
    (check-equal? (map (λ (event) (hash-ref event 'trace_id)) events)
                  (make-list 4 "trace-test"))
    (check-equal? (map (λ (event) (hash-ref event 'event)) events)
                  '("span_start" "span_end" "span_start" "span_end"))
    (check-equal? (map (λ (event) (hash-ref event 'name)) events)
                  '("success phase" "success phase"
                    "failure phase" "failure phase"))
    (check-= (hash-ref (second events) 'duration_ms) 4.5 0.000001)
    (check-equal? (hash-ref (second events) 'status) "ok")
    (check-= (hash-ref (fourth events) 'duration_ms) 8.125 0.000001)
    (check-equal? (hash-ref (fourth events) 'status) "error")

    (define absent-env
      (environment-variables-copy (current-environment-variables)))
    (environment-variables-set! absent-env #"FIRN_TRACE_PATH" #f)
    (environment-variables-set! absent-env #"FIRN_NIX_LOG_PATH" #f)
    (parameterize ([current-environment-variables absent-env]
                   [current-monotonic-clock (clock-from '(29.0 29.5))])
      (check-true (call-with-trace-span "untraced phase" (λ () #t))))
    (check-equal? (length (read-events trace-path)) 4)

    (define missing-trace (build-path scratch "missing" "trace.jsonl"))
    (define fail-open-env
      (environment-variables-copy (current-environment-variables)))
    (environment-variables-set! fail-open-env #"FIRN_TRACE_ID" #"fail-open")
    (environment-variables-set! fail-open-env #"FIRN_TRACE_PATH"
                                (path->bytes missing-trace))
    (parameterize ([current-environment-variables fail-open-env]
                   [current-monotonic-clock (clock-from '(30.0 31.0))])
      (check-true (call-with-trace-span "fail-open phase" (λ () #t))))
    (check-false (file-exists? missing-trace))

    (define base-command
      '("nix" "build" "--no-link" "--print-out-paths"
        "flake#host;$(not-shell)"))
    (check-equal? (nix-build-command base-command #f) base-command)
    (parameterize ([current-environment-variables absent-env])
      (check-equal? (nix-build-command base-command) base-command))
    (define nix-log-path (path->string (build-path scratch "nix.jsonl")))
    (define logged-command
      (nix-build-command base-command nix-log-path))
    (check-equal?
     (take logged-command 7)
     (list "bash" "-o" "pipefail" "-c" nix-log-shell
           "firn-nix-log" nix-log-path))
    (check-equal?
     (drop logged-command 7)
     '("nix" "build" "--log-format" "internal-json"
       "--no-link" "--print-out-paths"
       "flake#host;$(not-shell)")))
  (λ ()
    (delete-directory/files scratch #:must-exist? #f)))
