#lang racket/base

(require racket/list
         racket/path
         racket/file
         racket/system
         racket/string
         "util.rkt")

(provide node-edges)

;; ---------------------------------------------------------------------------
;; firn repo diff — drift sentinel.
;;
;; Re-emit each .bnix via beagle-build, strip the authoring-only tag attrs
;; (mirroring firn-build's post-process), and unified-diff the result against
;; its committed .nix. Confirms the committed .nix matches what beagle would
;; emit today.
;; ---------------------------------------------------------------------------

(define (beagle-build-exe)
  (define base
    (or (getenv "BEAGLE_PATH")
        (path->string (simplify-path (build-path ROOT 'up "beagle")))))
  (build-path base "bin" "beagle-build"))

;; Resolve a user-facing name to a .bnix source path. Accepts:
;;   - bare name        → modules/<name>/default.bnix | hosts/<name>/configuration.bnix
;;   - module[s]/<name> → modules/<name>/default.bnix
;;   - host[s]/<name>   → hosts/<name>/configuration.bnix
;;   - flake            → flake.bnix
;;   - relative path    → as-is (must end in .bnix)
(define (resolve-bnix-source name)
  (cond
    [(equal? name "flake") (in-repo "flake.bnix")]
    [(regexp-match #rx"^module[s]?/(.+)$" name)
     => (λ (m) (in-repo "modules" (cadr m) "default.bnix"))]
    [(regexp-match #rx"^host[s]?/(.+)$" name)
     => (λ (m) (in-repo "hosts" (cadr m) "configuration.bnix"))]
    [(regexp-match #rx"\\.bnix$" name)
     (cond [(file-exists? name) (string->path name)]
           [(file-exists? (in-repo name)) (in-repo name)]
           [else #f])]
    [else
     (findf file-exists?
            (list (in-repo "modules" name "default.bnix")
                  (in-repo "hosts" name "configuration.bnix")))]))

(define (bnix->nix-path bnix)
  (define s (if (path? bnix) (path->string bnix) bnix))
  (cond
    [(regexp-match? #rx"\\.bnix$" s)
     (string->path (regexp-replace #rx"\\.bnix$" s ".nix"))]
    [else (error 'bnix->nix-path "not a .bnix file: ~a" s)]))

;; Strip authoring-only resolver metadata that firn-build removes before the
;; .nix lands. Re-emitting without this would report spurious drift for tagged
;; modules and modules that contribute flake inputs.
(define (count-ch s ch)
  (for/sum ([c (in-string s)]) (if (char=? c ch) 1 0)))

(define (strip-authoring-attrs text)
  (define t1 (regexp-replace* #px"(?m:^[ \t]*tags[ \t]*=[ \t]*\\[[^]]*\\];[ \t]*\n)" text ""))
  (define t2 (regexp-replace* #px"(?m:^[ \t]*tags-opt-in[ \t]*=[ \t]*\\[[^]]*\\];[ \t]*\n)" t1 ""))
  (define lines (string-split t2 "\n" #:trim? #f))
  (let loop ([ls lines] [acc '()])
    (cond
      [(null? ls) (string-join (reverse acc) "\n")]
      ;; Multi-line `tag-overrides = {` … `};` — consume balanced braces.
      [(regexp-match? #px"^[ \t]*tag-overrides[ \t]*=[ \t]*\\{[ \t]*$" (car ls))
       (let skip ([rest (cdr ls)] [depth 1])
         (cond
           [(or (null? rest) (<= depth 0)) (loop rest acc)]
           [else
            (define line (car rest))
            (skip (cdr rest)
                  (+ depth (count-ch line #\{) (- (count-ch line #\})))) ]))]
      ;; Single-line `tag-overrides = { … };`
      [(regexp-match? #px"^[ \t]*tag-overrides[ \t]*=[ \t]*\\{.*\\};[ \t]*$" (car ls))
       (loop (cdr ls) acc)]
      ;; Multi-line `flake-inputs = {` … `};` — consume balanced braces.
      [(regexp-match? #px"^[ \t]*flake-inputs[ \t]*=[ \t]*\\{[ \t]*$" (car ls))
       (let skip ([rest (cdr ls)] [depth 1])
         (cond
           [(or (null? rest) (<= depth 0)) (loop rest acc)]
           [else
            (define line (car rest))
            (skip (cdr rest)
                  (+ depth (count-ch line #\{) (- (count-ch line #\})))) ]))]
      ;; Single-line `flake-inputs = { … };`
      [(regexp-match? #px"^[ \t]*flake-inputs[ \t]*=[ \t]*\\{.*\\};[ \t]*$" (car ls))
       (loop (cdr ls) acc)]
      [else (loop (cdr ls) (cons (car ls) acc))])))

;; Re-emit a .bnix to a Nix string (authoring attrs stripped). #f on failure.
(define (re-emit-nix bnix-path)
  (define tmp (make-temporary-file "firn-emit-~a.nix"))
  (define err (open-output-string))
  (define ok?
    (parameterize ([current-output-port (open-output-string)]
                   [current-error-port err])
      (system* (beagle-build-exe) (path->string bnix-path) (path->string tmp))))
  (cond
    [ok?
     (define out (file->string tmp))
     (delete-file tmp)
     (strip-authoring-attrs out)]
    [else
     (when (file-exists? tmp) (delete-file tmp))
     (eprintf "firn diff: failed to emit ~a\n" (path->string bnix-path))
     (eprintf "~a" (get-output-string err))
     #f]))

(define (diff-one bnix-path)
  (define nix-path (bnix->nix-path bnix-path))
  (define fresh (re-emit-nix bnix-path))
  (cond
    [(not fresh) 'error]
    [(not (file-exists? nix-path))
     (printf "=== ~a ===\n" (relative-to-repo nix-path))
     (printf "(no committed .nix — would create)\n")
     'different]
    [else
     (define committed (file->string nix-path))
     (cond
       [(equal? fresh committed) 'same]
       [else
        (define tmp (make-temporary-file "firn-diff-~a.nix"))
        (with-output-to-file tmp #:exists 'replace (λ () (display fresh)))
        (printf "=== ~a ===\n" (relative-to-repo nix-path))
        (flush-output)
        (system* (find-exe "diff") "-u" "--color=always"
                 (path->string nix-path) (path->string tmp))
        (delete-file tmp)
        'different])]))

;; A .bnix that firn-build would regenerate (excludes tooling, fixtures, and
;; enabled-tags resolver inputs — which intentionally have no valid .nix).
(define (repo-bnix-target? s)
  (and (regexp-match? #rx"\\.bnix$" s)
       (not (regexp-match? #rx"/scripts/" s))
       (not (regexp-match? #rx"/tests/" s))
       (not (regexp-match? #rx"/docs/fixtures/" s))
       (not (regexp-match? #rx"/\\.direnv/" s))
       (not (regexp-match? #rx"/\\.git/" s))
       (not (regexp-match? #rx"/result" s))
       (not (regexp-match? #rx"enabled-tags\\.bnix$" s))))

(define (handle-repo-diff leaf)
  (define leaf* (if (symbol? leaf) (symbol->string leaf) leaf))
  (define targets
    (cond
      [(equal? leaf* "all")
       (sort
        (for/list ([f (in-directory ROOT)]
                   #:when (repo-bnix-target? (path->string f)))
          f)
        path<?)]
      [else
       (define r (resolve-bnix-source leaf*))
       (cond [r (list r)]
             [else (eprintf "firn diff: cannot resolve ~a\n" leaf*) (exit 1)])]))
  (define same 0)
  (define diff 0)
  (define err 0)
  (for ([bnix (in-list targets)])
    (case (diff-one bnix)
      [(same) (set! same (+ same 1))]
      [(different) (set! diff (+ diff 1))]
      [(error) (set! err (+ err 1))]))
  (printf "\nfirn diff: ~a unchanged, ~a differ, ~a error(s)\n" same diff err)
  (exit (if (or (> diff 0) (> err 0)) 1 0)))

(define node-edges
  (list
   (walk-edge "repo" "diff" "<target>|all" 'all
              handle-repo-diff
              "re-emit Nix from .bnix and diff vs committed .nix")))

(module+ test
  (require rackunit)

  (define emitted
    (string-append
     "{\n"
     "  tags = [ development ];\n"
     "  tags-opt-in = [ optional ];\n"
     "  tag-overrides = {\n"
     "    ash = [ darwin ];\n"
     "  };\n"
     "  flake-inputs = {\n"
     "    fram = {\n"
     "      url = \"git+file:///home/tom/code/fram?ref=main\";\n"
     "    };\n"
     "  };\n"
     "  config = { enable = true; };\n"
     "}\n"))
  (check-equal?
   (strip-authoring-attrs emitted)
   (string-append
    "{\n"
    "  config = { enable = true; };\n"
    "}\n")))
