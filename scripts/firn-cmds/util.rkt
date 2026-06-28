#lang racket/base

;; firn-cmds/util — shared helpers used by all command modules.

(require racket/string
         racket/path
         racket/file
         racket/system)

(provide ROOT
         in-repo
         sh sh-out find-exe
         list-dirs modules hosts
         current-hostname host-config-rkt
         grep-files relative-to-repo
         paths-referenced-in
         find-name-kind
         resolve-default
         flake-input-purity-violations
         (struct-out walk-edge))

;; ---------- walk-edge metadata ----------
;;
;; firn's CLI is an entity-first walkable graph: every command is a
;; sequence of (node, edge, leaf) triples. Each firn-cmds/*.rkt module
;; exports a `node-edges` list of these structs; firn.rkt aggregates
;; them for both dispatch and help-text generation.
;;
;;   node          the entity (module, host, tag, repo, ...)
;;   edge          the verb (status, enable, add, ...)
;;   leaf-shape    user-facing string shown in help: "<name>", "all", ...
;;   default-leaf  what to use if the user omits the leaf token:
;;                   #f           — required; error if missing
;;                   'all         — literal "all"
;;                   'current-host — resolved to (current-hostname)
;;                   (string val) — any literal
;;   handler       (λ (leaf ctx) ...) — leaf is the resolved string;
;;                 ctx is the walk context; may return a new ctx or #f
;;   desc          one-line help
(struct walk-edge (node edge leaf-shape default-leaf handler desc) #:transparent)

(define (resolve-default default-leaf)
  ;; Returns the string to use for an omitted leaf, or #f if required.
  (cond
    [(eq? default-leaf #f) #f]
    [(eq? default-leaf 'all) "all"]
    [(eq? default-leaf 'current-host) (current-hostname)]
    [(string? default-leaf) default-leaf]
    [else #f]))

(define (find-name-kind name)
  ;; Return 'module, or #f. Bundles are gone (zero users) — kept the
  ;; function so legacy callsites keep compiling.
  (cond
    [(directory-exists? (in-repo "modules" name)) 'module]
    [else #f]))

;; ---------- repo discovery ----------

(define (looks-like-firn-repo? p)
  ;; flake.rkt is the pre-migration artifact; the repo's flake source is now
  ;; flake.bnix (compiled to flake.nix). Checking flake.rkt made find-repo-root
  ;; ALWAYS fall back to $HOME/code/nixos-config — so firn run from a git
  ;; worktree silently operated on the main checkout. Accept either layout.
  (and (directory-exists? p)
       (file-exists? (build-path p "scripts" "firn-build"))
       (or (file-exists? (build-path p "flake.bnix"))
           (file-exists? (build-path p "flake.rkt")))))

(define (find-repo-root)
  ;; Repo discovery, in order of preference:
  ;;   1. FIRN_REPO env var — explicit override, only accepted if it looks
  ;;      like a firn repo (has scripts/firn-build + flake.rkt).
  ;;   2. `git rev-parse --show-toplevel` from cwd, but ONLY if the result
  ;;      also looks like a firn repo. This keeps firn commands working
  ;;      when invoked from inside the nixos-config tree, but avoids
  ;;      misfiring when the user is in some unrelated git repo.
  ;;   3. Fallback: $HOME/code/nixos-config.
  (define home (or (getenv "HOME") "/home/tom"))
  (define default (path->string (build-path home "code" "nixos-config")))
  (define from-env (getenv "FIRN_REPO"))
  (cond
    [(and from-env (non-empty-string? from-env) (looks-like-firn-repo? from-env))
     from-env]
    [else
     (with-handlers ([exn:fail? (λ (_) default)])
       (define o (open-output-string))
       (parameterize ([current-output-port o])
         (system "git rev-parse --show-toplevel 2>/dev/null"))
       (define s (string-trim (get-output-string o)))
       (cond
         [(and (non-empty-string? s) (looks-like-firn-repo? s)) s]
         [else default]))]))

(define ROOT (find-repo-root))

(define (in-repo . segments)
  (apply build-path ROOT segments))

;; ---------- shell helpers ----------

(define (sh . args)
  (apply system* (find-exe (car args)) (cdr args)))

(define (sh-out . args)
  (define o (open-output-string))
  (parameterize ([current-output-port o])
    (apply system* (find-exe (car args)) (cdr args)))
  (string-trim (get-output-string o)))

(define (find-exe cmd)
  (define o (open-output-string))
  (parameterize ([current-output-port o])
    (system* "/usr/bin/env" "which" cmd))
  (define s (string-trim (get-output-string o)))
  (if (non-empty-string? s) s cmd))

;; ---------- listing helpers ----------

(define (list-dirs subdir)
  (define dir (in-repo subdir))
  (cond
    [(directory-exists? dir)
     (sort
      (for/list ([p (directory-list dir)]
                 #:when (directory-exists? (build-path dir p)))
        (path->string p))
      string<?)]
    [else '()]))

(define (modules)  (list-dirs "modules"))
(define (hosts)
  (define hd (in-repo "hosts"))
  (cond
    [(directory-exists? hd)
     (sort
      (for/list ([p (directory-list hd)]
                 #:when (directory-exists? (build-path hd p)))
        (path->string p))
      string<?)]
    [else '()]))

(define (current-hostname)
  (with-handlers ([exn:fail? (λ (_) "whiterabbit")])
    (define s (sh-out "hostname"))
    (if (non-empty-string? s) s "whiterabbit")))

(define (host-config-rkt host)
  ;; Name kept for callsite compatibility; now points at the beagle/nix file.
  (in-repo "hosts" host "configuration.bnix"))

(define (grep-files dir re)
  (define abs-dir (in-repo dir))
  (cond
    [(directory-exists? abs-dir)
     (for/list ([p (in-directory abs-dir)]
                #:when (and (file-exists? p)
                            (regexp-match? #rx"\\.(rkt|nix)$" (path->string p))
                            (with-handlers ([exn:fail? (λ (_) #f)])
                              (regexp-match? re (file->string p)))))
       (path->string p))]
    [else '()]))

(define (relative-to-repo p)
  (define s (path->string (simplify-path p)))
  (define root-s (string-append (path->string (simplify-path ROOT)) "/"))
  (cond [(string-prefix? s root-s) (substring s (string-length root-s))]
        [else s]))

;; ---------- flake input purity ----------
;;
;; Returns a list of "flake.rkt:<line>: <text>" strings for every line
;; that declares a flake input with an absolute path: URL (path:/...).
;; Such inputs trip Nix's pure-eval ("access to absolute path '/...' is
;; forbidden") as soon as anything reaches into `inputs.<name>`, even
;; transitively via flake-lock resolution. Empty list ⇒ pure-eval safe.
(define (flake-input-purity-violations)
  ;; Check the live flake source. Prefer flake.bnix (current source of
  ;; truth); fall back to flake.rkt if present (legacy).
  (define src
    (cond
      [(file-exists? (in-repo "flake.bnix")) (in-repo "flake.bnix")]
      [(file-exists? (in-repo "flake.rkt")) (in-repo "flake.rkt")]
      [else #f]))
  (cond
    [(not src) '()]
    [else
     (define lines (regexp-split #rx"\n" (file->string src)))
     (define src-name
       (cond [(equal? src (in-repo "flake.bnix")) "flake.bnix"]
             [else "flake.rkt"]))
     (for/list ([line (in-list lines)]
                [n (in-naturals 1)]
                #:when (regexp-match? #px"\"path:/[^\"]+\"" line))
       (format "~a:~a: ~a" src-name n (regexp-replace #rx"^\\s+" line "")))]))

;; ---------- option-path extraction from .rkt source ----------
;;
;; Walks a .rkt file and returns every option-path string referenced
;; via (set …), (enable …), or shortcut macros ((pkg X), (svc X),
;; (sub-modules a b c)). Bodies under home-of / hm-* / hm-module are
;; skipped — those reference home-manager paths that aren't in the
;; system schema.
;;
;; Handles both bare-identifier paths `(set boot.X val)` and quoted
;; paths `(set 'boot.X val)`. Tolerant — read errors return '().

(define HM-FORMS '(home-of home-of-bare hm hm-bare hm-module))

(define (count-char c s)
  (for/sum ([ch (in-string s)] #:when (char=? ch c)) 1))

(define (form-head-symbol datum)
  (and (pair? datum) (symbol? (car datum)) (car datum)))

(define (path-from-arg arg)
  (cond
    [(symbol? arg) (symbol->string arg)]
    [(and (pair? arg) (eq? (car arg) 'quote)
          (pair? (cdr arg)) (symbol? (cadr arg)))
     (symbol->string (cadr arg))]
    [(string? arg) arg]
    [else #f]))

(define (collect-paths-from datum acc)
  (cond
    [(not (pair? datum)) acc]
    [else
     (define head (form-head-symbol datum))
     (cond
       [(memq head HM-FORMS) acc]
       [(eq? head 'set)
        (define rest (cdr datum))
        (cond
          [(null? rest) acc]
          [else
           (define p (path-from-arg (car rest)))
           (define acc2 (if p (cons p acc) acc))
           (for/fold ([a acc2]) ([d (in-list (cdr rest))])
             (collect-paths-from d a))])]
       [(eq? head 'enable)
        (for/fold ([a acc]) ([arg (in-list (cdr datum))])
          (define p (path-from-arg arg))
          (if p (cons (string-append p ".enable") a) a))]
       [(eq? head 'pkg)
        (cons "environment.systemPackages" acc)]
       [(eq? head 'svc)
        (define args (cdr datum))
        (cond
          [(null? args) acc]
          [(and (= (length args) 3) (string? (cadr args)))
           (cons (cadr args) acc)]
          [else
           (define n (path-from-arg (car args)))
           (if n (cons (string-append "services." n ".enable") acc) acc)])]
       [(eq? head 'hm-module) acc]
       [(or (eq? head 'sub-modules) (eq? head 'sub-modules*))
        (for/fold ([a acc]) ([arg (in-list (cdr datum))])
          (define name
            (cond
              [(symbol? arg) (symbol->string arg)]
              [(and (pair? arg) (symbol? (car arg))) (symbol->string (car arg))]
              [else #f]))
          (if name (cons (string-append "myConfig.modules." name ".enable") a) a))]
       [else
        (for/fold ([a acc]) ([d (in-list datum)])
          (collect-paths-from d a))])]))

(define (paths-referenced-in rkt-path)
  (with-handlers ([exn:fail? (λ (_) '())])
    (define raw (file->string rkt-path))
    (define-values (lang-prefix rest)
      (let ([m (regexp-match-positions #rx"^#lang [^\n]*\n" raw)])
        (cond [m (values (substring raw 0 (cdr (car m)))
                         (substring raw (cdr (car m))))]
              [else (values "" raw)])))
    (define padded (string-append (make-string (count-char #\newline lang-prefix) #\newline)
                                  rest))
    (define port (open-input-string padded))
    (define out '())
    (let loop ()
      (define datum (read port))
      (unless (eof-object? datum)
        (set! out (collect-paths-from datum out))
        (loop)))
    (reverse out)))
