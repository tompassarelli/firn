#lang racket/base

;; firn-cmds/flake-inputs-resolve — collect :flake-inputs from modules,
;; generate into flake.bnix between markers.
;;
;; Pattern: same as tag-resolve.rkt. Read each module's default.bnix,
;; extract :flake-inputs clause, merge across all active modules (from
;; tag resolution), detect conflicts (same input name, different URL),
;; and splice into flake.bnix between markers.

(require racket/file
         racket/list
         racket/path
         racket/port
         racket/string
         racket/format
         "util.rkt"
         "tag-resolve.rkt")

(provide node-edges
         extract-module-flake-inputs
         collect-all-flake-inputs
         splice-flake-inputs!)

;; ---------- extraction ----------

(define FLAKE-INPUTS-RE #px":flake-inputs[\\s{]")

(define (file-has-flake-inputs? path)
  (with-handlers ([exn:fail? (λ (_) #f)])
    (regexp-match? FLAKE-INPUTS-RE (file->string path))))

(define (extract-module-flake-inputs name)
  ;; Returns a hash: input-name-string → hash of spec keys.
  ;; Empty hash if no :flake-inputs clause.
  (define path (in-repo "modules" name "default.bnix"))
  (cond
    [(not (file-exists? path)) (hash)]
    [(not (file-has-flake-inputs? path)) (hash)]
    [else
     (define forms (read-bnix-forms path))
     (define body (find-module-body forms))
     (define h (map-datum->pairs (or body '())))
     (define raw (hash-ref h "flake-inputs" #f))
     (cond
       [(not raw) (hash)]
       [(not (list? raw)) (hash)]
       [else
        (let loop ([xs raw] [result (hash)])
          (cond
            [(null? xs) result]
            [(null? (cdr xs)) result]
            [(keyword-symbol? (car xs))
             (define input-name (keyword-name (car xs)))
             (define spec-datum (cadr xs))
             (define spec (map-datum->pairs (if (list? spec-datum) spec-datum '())))
             (loop (cddr xs) (hash-set result input-name spec))]
            [else (loop (cdr xs) result)]))])]))

;; ---------- collection + conflict detection ----------

(define (collect-all-flake-inputs active-modules)
  ;; Returns (values collected-hash errors).
  ;; collected-hash: input-name → (hash "url" ... "source-module" ...)
  (define collected (make-hash))
  (define errors '())
  (for ([mod (in-list active-modules)])
    (define inputs (extract-module-flake-inputs mod))
    (for ([(input-name spec) (in-hash inputs)])
      (define url (hash-ref spec "url" #f))
      (cond
        [(hash-has-key? collected input-name)
         (define existing (hash-ref collected input-name))
         (define existing-url (hash-ref existing "url" ""))
         (define existing-mod (hash-ref existing "source-module" "?"))
         (unless (equal? url existing-url)
           (set! errors
                 (cons (format "flake-inputs: conflict on '~a' — module '~a' declares url ~a but module '~a' declares url ~a"
                               input-name mod url existing-mod existing-url)
                       errors)))]
        [else
         (hash-set! collected input-name
                    (hash-set spec "source-module" mod))])))
  (values (hash-copy collected) (reverse errors)))

;; ---------- emission: splice into flake.bnix ----------

(define INPUT-BEGIN-MARKER   ";; --- GENERATED MODULE INPUTS (do not edit) ---")
(define INPUT-END-MARKER     ";; --- END GENERATED MODULE INPUTS ---")
(define ARGS-BEGIN-MARKER    ";; --- GENERATED MODULE ARGS (do not edit) ---")
(define ARGS-END-MARKER      ";; --- END GENERATED MODULE ARGS ---")
(define SPECIAL-BEGIN-MARKER ";; --- GENERATED MODULE SPECIALARGS (do not edit) ---")
(define SPECIAL-END-MARKER   ";; --- END GENERATED MODULE SPECIALARGS ---")
(define HM-SPECIAL-BEGIN-MARKER  ";; --- GENERATED HM SPECIALARGS (do not edit) ---")
(define HM-SPECIAL-END-MARKER    ";; --- END GENERATED HM SPECIALARGS ---")
(define DARWIN-SPECIAL-BEGIN-MARKER  ";; --- GENERATED DARWIN SPECIALARGS (do not edit) ---")
(define DARWIN-SPECIAL-END-MARKER    ";; --- END GENERATED DARWIN SPECIALARGS ---")
(define DARWIN-HM-BEGIN-MARKER  ";; --- GENERATED DARWIN HM SPECIALARGS (do not edit) ---")
(define DARWIN-HM-END-MARKER    ";; --- END GENERATED DARWIN HM SPECIALARGS ---")

(define (find-marker-pos text marker)
  ;; Returns the byte offset of `marker` in `text`, or #f.
  (define m (regexp-match-positions (regexp-quote marker) text))
  (and m (car (car m))))

(define (replace-between-markers text begin-marker end-marker new-content)
  (define begin-pos (find-marker-pos text begin-marker))
  (define end-pos (and begin-pos (find-marker-pos text end-marker)))
  (unless (and begin-pos end-pos)
    (error 'replace-between-markers
           "markers not found in flake.bnix: ~a ... ~a" begin-marker end-marker))
  (define before (substring text 0 (+ begin-pos (string-length begin-marker))))
  ;; Preserve the end marker's original indentation by finding the
  ;; whitespace between the preceding newline and the marker itself.
  (define pre-end (substring text 0 end-pos))
  (define last-nl (for/last ([i (in-range (string-length pre-end))]
                             #:when (char=? (string-ref pre-end i) #\newline))
                    i))
  (define indent (if last-nl (substring pre-end (+ last-nl 1)) ""))
  (define after (substring text end-pos))
  (string-append before "\n" new-content indent after))

(define (format-input-decl name spec)
  (define pairs
    (for/list ([(k v) (in-hash spec)]
               #:when (not (equal? k "source-module")))
      (cond
        [(boolean? v) (format ":~a ~a" k (if v "true" "false"))]
        [(and (string? v) (or (equal? v "false") (equal? v "true")))
         (format ":~a ~a" k v)]
        [else (format ":~a ~v" k v)])))
  (format "   :~a {~a}" name (string-join pairs " ")))

(define (format-specialargs-entry name)
  (format ":~a ~a" name name))

(define (splice-flake-inputs! collected)
  (define path (in-repo "flake.bnix"))
  (define text (file->string path))
  (define sorted-names (sort (hash-keys collected) string<?))

  ;; 1. Input declarations
  (define input-lines
    (for/list ([name (in-list sorted-names)])
      (format-input-decl name (hash-ref collected name))))
  (define input-block (string-append (string-join input-lines "\n") "\n"))

  ;; 2. Outputs arg names
  (define args-block
    (string-append
     (string-join (for/list ([n (in-list sorted-names)]) (format "     ~a" n)) "\n")
     "\n"))

  ;; 3. specialArgs entries (same content for all 4 sites)
  (define special-lines
    (for/list ([n (in-list sorted-names)])
      (format "                    ~a" (format-specialargs-entry n))))
  (define special-block (string-append (string-join special-lines "\n") "\n"))

  (define text2 (replace-between-markers text INPUT-BEGIN-MARKER INPUT-END-MARKER input-block))
  (define text3 (replace-between-markers text2 ARGS-BEGIN-MARKER ARGS-END-MARKER args-block))
  (define text4 (replace-between-markers text3 SPECIAL-BEGIN-MARKER SPECIAL-END-MARKER special-block))
  (define text5 (replace-between-markers text4 HM-SPECIAL-BEGIN-MARKER HM-SPECIAL-END-MARKER special-block))
  (define text6 (replace-between-markers text5 DARWIN-SPECIAL-BEGIN-MARKER DARWIN-SPECIAL-END-MARKER special-block))
  (define text7 (replace-between-markers text6 DARWIN-HM-BEGIN-MARKER DARWIN-HM-END-MARKER special-block))

  (cond
    [(equal? text text7) #f]
    [else
     (with-output-to-file path #:exists 'replace (λ () (display text7)))
     #t]))

;; ---------- top-level driver ----------

(define (run-flake-inputs-resolve #:emit? [emit? #f] #:quiet? [quiet? #f])
  ;; Collect from ALL modules, not just tag-active ones. Modules can be
  ;; enabled directly in configuration.bnix without tags (e.g. walker),
  ;; or via opt-in tags. Flake inputs must be declared for any module
  ;; that exists — nix is lazy, unused inputs are harmless.
  (define all-modules (modules))

  (define-values (collected errors) (collect-all-flake-inputs all-modules))

  (when (pair? errors)
    (for ([e (in-list errors)])
      (eprintf "~a\n" e))
    (exit 1))

  (unless quiet?
    (define count (hash-count collected))
    (cond
      [(zero? count) (printf "flake-inputs: no module inputs found\n")]
      [else
       (printf "flake-inputs: ~a module input~a from ~a module~a\n"
               count (if (= count 1) "" "s")
               (length all-modules) (if (= (length all-modules) 1) "" "s"))
       (for ([name (in-list (sort (hash-keys collected) string<?))])
         (define spec (hash-ref collected name))
         (printf "  ~a (from ~a)\n" name (hash-ref spec "source-module" "?")))]))

  (when emit?
    (define changed? (splice-flake-inputs! collected))
    (unless quiet?
      (cond
        [changed? (printf "flake-inputs: updated flake.bnix\n")]
        [else     (printf "flake-inputs: flake.bnix is up to date\n")])))

  collected)

;; ---------- handler ----------

(define (handle-flake-inputs-resolve leaf)
  (define emit? (or (equal? leaf "emit")
                    (regexp-match? #rx"\\+emit$" leaf)
                    (getenv "FIRN_FLAKE_INPUTS_EMIT")))
  (run-flake-inputs-resolve #:emit? emit?))

(define node-edges
  (list
   (walk-edge "flake-input" "resolve" "show|emit" "show"
              handle-flake-inputs-resolve
              "collect :flake-inputs from active modules; emit splices into flake.bnix")))
