#lang racket/base

(require json
         rackunit
         racket/file
         racket/list
         racket/port
         racket/string
         racket/system
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
       "flake#host;$(not-shell)"))

    (define active-target (build-path scratch "active-system"))
    (define changed-target (build-path scratch "changed-system"))
    (make-directory active-target)
    (make-directory changed-target)
    (define active-link (build-path scratch "active-link"))
    (define built-link (build-path scratch "built-link"))
    (make-file-or-directory-link active-target active-link)
    (make-file-or-directory-link active-link built-link)

    (define activation-commands (box '()))
    (define (record-command . command)
      (set-box! activation-commands
                (append (unbox activation-commands) (list command)))
      #t)
    (parameterize ([current-environment-variables trace-env]
                   [current-monotonic-clock
                    (clock-from '(40.0 40.25 50.0 51.0))]
                   [current-output-port (open-output-nowhere)])
      (check-true
       (activate-linux-system (path->string built-link)
                              (path->string active-link)
                              record-command))
      (check-equal? (unbox activation-commands) '())
      (check-true
       (activate-linux-system (path->string changed-target)
                              (path->string active-link)
                              record-command)))
    (check-equal?
     (unbox activation-commands)
     (list
      (list "sudo" "nix-env"
            "--profile" "/nix/var/nix/profiles/system"
            "--set" (path->string changed-target))
      (list "sudo"
            (string-append (path->string changed-target)
                           "/bin/switch-to-configuration")
            "switch")))

    (define activation-events (drop (read-events trace-path) 4))
    (check-equal? (map (λ (event) (hash-ref event 'name)) activation-events)
                  (make-list 4 "activation"))
    (check-equal? (map (λ (event) (hash-ref event 'activation))
                       activation-events)
                  '("skipped" "skipped" "run" "run"))
    (check-equal? (map (λ (event) (hash-ref event 'reason))
                       (take activation-events 2))
                  '("already-active" "already-active"))
    (check-false (hash-has-key? (third activation-events) 'reason))
    (check-equal? (hash-ref (second activation-events) 'status) "ok")
    (check-equal? (hash-ref (fourth activation-events) 'status) "ok")

    (set-box! activation-commands '())
    (parameterize ([current-environment-variables absent-env]
                   [current-monotonic-clock (clock-from '(60.0 61.0))]
                   [current-output-port (open-output-nowhere)])
      (check-true
       (activate-linux-system (path->string changed-target)
                              (path->string (build-path scratch "missing-system"))
                              record-command)))
    (check-equal? (length (unbox activation-commands)) 2)

    (define blocking-checker (build-path scratch "blocking-checker"))
    (call-with-output-file blocking-checker
      #:exists 'truncate
      (λ (out)
        (display "#!/usr/bin/env bash\nsleep 30\n" out)))
    (file-or-directory-permissions blocking-checker #o755)
    (define job-gate (make-semaphore 0))
    (define blocking-job #f)
    (define schedule-command #f)
    (define (mock-supervisor . command)
      (set! schedule-command command)
      (set! blocking-job
            (thread (λ () (semaphore-wait job-gate))))
      #t)
    (define schedule-start (current-inexact-monotonic-milliseconds))
    (parameterize ([current-environment-variables trace-env]
                   [current-monotonic-clock (clock-from '(70.0))]
                   [current-output-port (open-output-nowhere)])
      (check-true
       (schedule-drift-check blocking-checker
                             mock-supervisor
                             "firn-agent-config-check-test.service")))
    (define schedule-elapsed
      (- (current-inexact-monotonic-milliseconds) schedule-start))
    (check-true (< schedule-elapsed 1000.0))
    (check-false (thread-dead? blocking-job))
    (check-not-false (member "--no-block" schedule-command))
    (check-not-false (member "--collect" schedule-command))
    (check-equal? (take-right schedule-command 2)
                  (list "firn-agent-config-check"
                        (path->string blocking-checker)))
    (semaphore-post job-gate)
    (thread-wait blocking-job)

    (parameterize ([current-environment-variables trace-env]
                   [current-monotonic-clock (clock-from '(71.0))]
                   [current-output-port (open-output-nowhere)])
      (check-true
       (schedule-drift-check blocking-checker
                             (λ _ #f)
                             "firn-agent-config-check-error.service")))
    (define advisory-events (drop (read-events trace-path) 8))
    (check-equal? (map (λ (event) (hash-ref event 'event)) advisory-events)
                  '("advisory_job" "advisory_job"))
    (check-equal? (map (λ (event) (hash-ref event 'status)) advisory-events)
                  '("scheduled" "schedule_error"))
    (check-equal? (map (λ (event) (hash-ref event 'unit)) advisory-events)
                  '("firn-agent-config-check-test.service"
                    "firn-agent-config-check-error.service"))

    (define failing-checker (build-path scratch "failing-checker"))
    (call-with-output-file failing-checker
      #:exists 'truncate
      (λ (out)
        (display "#!/usr/bin/env bash\nexit 19\n" out)))
    (file-or-directory-permissions failing-checker #o755)
    (define advisory-error (open-output-string))
    (check-true
     (parameterize ([current-error-port advisory-error])
       (system* (find-executable-path "bash")
                "-c" advisory-check-shell
                "firn-agent-config-check"
                (path->string failing-checker))))
    (check-true (string-contains? (get-output-string advisory-error)
                                  "agent harness drift (advisory)")))
  (λ ()
    (delete-directory/files scratch #:must-exist? #f)))
