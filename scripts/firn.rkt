#!/usr/bin/env racket
#lang racket/base

;; firn — FirnOS config management CLI.
;;
;; Compile to a standalone binary with `./scripts/firn-build-bin`.
;;
;; CLI shape: a walkable entity-first graph. Every invocation is one
;; or more (node, edge, leaf) triples:
;;
;;   firn <node> <edge> <leaf> [<node> <edge> <leaf>]*
;;
;; e.g. `firn tag enable terminal`, `firn module status all`,
;;      `firn host rebuild whiterabbit`, `firn schema explain X`.
;;
;; If the final leaf is omitted, the edge's `default-leaf` fills in:
;;   'all          → literal "all"
;;   'current-host → (current-hostname), so `firn host rebuild` works
;;   #f            → leaf required; print usage and exit
;;
;; Each command lives in scripts/firn-cmds/*.rkt and exports a
;; `node-edges` list of walk-edge structs. firn.rkt concatenates them;
;; help text auto-groups by node so it never drifts from registered
;; handlers.
;;
;; Legacy shapes (firn status, firn rebuild, firn enable, ...) are
;; rewritten into the new walk by LEGACY-ALIASES below.

(require racket/list
         racket/format
         racket/string
         "firn-cmds/util.rkt"
         (prefix-in r:  "firn-cmds/rebuild.rkt")
         (prefix-in w:  "firn-cmds/watch.rkt")
         (prefix-in l:  "firn-cmds/list.rkt")
         (prefix-in t:  "firn-cmds/toggle.rkt")
         (prefix-in sc: "firn-cmds/scaffold.rkt")
         (prefix-in d:  "firn-cmds/diff.rkt")
         (prefix-in s:  "firn-cmds/secret.rkt")
         (prefix-in e:  "firn-cmds/explain.rkt")
         (prefix-in dr: "firn-cmds/doctor.rkt")
         (prefix-in u:  "firn-cmds/upgrade.rkt")
         (prefix-in p:  "firn-cmds/platforms.rkt")
         (prefix-in tg: "firn-cmds/tags.rkt")
         (prefix-in tr: "firn-cmds/tag-resolve.rkt")
         (prefix-in te: "firn-cmds/tag-edit.rkt")
         (prefix-in pl: "firn-cmds/pipeline.rkt")
         (prefix-in fl: "firn-cmds/flake.rkt")
         (prefix-in fi: "firn-cmds/flake-inputs-resolve.rkt")
         (prefix-in ar: "firn-cmds/architecture.rkt"))

(define ALL-EDGES
  (append r:node-edges
          w:node-edges
          l:node-edges
          t:node-edges
          sc:node-edges
          d:node-edges
          s:node-edges
          e:node-edges
          dr:node-edges
          u:node-edges
          p:node-edges
          tg:node-edges
          tr:node-edges
          te:node-edges
          pl:node-edges
          fl:node-edges
          fi:node-edges
          ar:node-edges))

(define (lookup-edge node edge)
  (findf (λ (e) (and (equal? (walk-edge-node e) node)
                     (equal? (walk-edge-edge e) edge)))
         ALL-EDGES))

(define (nodes)
  (sort (remove-duplicates (map walk-edge-node ALL-EDGES)) string<?))

(define (edges-of node)
  (filter (λ (e) (equal? (walk-edge-node e) node)) ALL-EDGES))

;; ---------- dispatch ----------

(define (print-edge-usage e)
  (eprintf "Usage: firn ~a ~a ~a\n"
           (walk-edge-node e) (walk-edge-edge e) (walk-edge-leaf-shape e))
  (eprintf "  ~a\n" (walk-edge-desc e)))

(define (suggest-node node)
  (define ns (nodes))
  (eprintf "  available nodes: ~a\n" (string-join ns ", ")))

(define (suggest-edge node)
  (define es (edges-of node))
  (cond
    [(null? es)
     (eprintf "  no such node '~a'\n" node)
     (suggest-node node)]
    [else
     (eprintf "  edges on '~a': ~a\n" node
              (string-join (map walk-edge-edge es) ", "))]))

(define (dispatch tokens)
  (cond
    [(null? tokens) (cmd-help '())]
    [(< (length tokens) 2)
     (define node (car tokens))
     (cond
       [(member node (nodes))
        (printf "Edges on '~a':\n" node)
        (for ([e (in-list (edges-of node))])
          (printf "  firn ~a ~a ~a\n      ~a\n"
                  (walk-edge-node e) (walk-edge-edge e)
                  (walk-edge-leaf-shape e) (walk-edge-desc e)))]
       [else
        (eprintf "firn: incomplete walk; expected <node> <edge> [<leaf>]\n")
        (suggest-node node)
        (exit 1)])]
    [else
     (let loop ([tokens tokens])
       (cond
         [(null? tokens) (void)]
         [(< (length tokens) 2)
          (eprintf "firn: dangling token after a complete walk: ~a\n" (car tokens))
          (exit 1)]
         [else
          (define node (car tokens))
          (define edge (cadr tokens))
          (define e (lookup-edge node edge))
          (cond
            [(not e)
             (eprintf "firn: unknown walk '~a ~a'\n" node edge)
             (suggest-edge node)
             (exit 1)]
            [else
             (define rest (cddr tokens))
             (define def (resolve-default (walk-edge-default-leaf e)))
             ;; If the next two tokens already form a known (node, edge)
             ;; pair, the user is chaining and intends to omit this leaf.
             ;; Falls back to consuming the next token as leaf when no
             ;; chain follows.
             (define chained-next?
               (and (>= (length rest) 2)
                    (lookup-edge (car rest) (cadr rest))))
             (define-values (leaf next-rest)
               (cond
                 [(and def chained-next?) (values def rest)]
                 [(null? rest)
                  (cond
                    [def (values def '())]
                    [else
                     (eprintf "firn: '~a ~a' requires a leaf node\n" node edge)
                     (print-edge-usage e)
                     (exit 1)])]
                 [else (values (car rest) (cdr rest))]))
             ((walk-edge-handler e) leaf)
             (loop next-rest)])]))]))

;; ---------- legacy aliases ----------
;;
;; Each entry: (old-first-token, rewrite-fn). The rewrite-fn takes the
;; remaining argv (after the first token is consumed) and returns the
;; new token list, or #f to fall through.

(define LEGACY-ALIASES
  (list
    ;; firn status [host]
    (cons "status"
          (λ (args)
            (define host (and (pair? args) (car args)))
            (cond
              [host (list "host" "status" host)]
              [else (list "host" "status")])))
    ;; firn enable <name>:
    ;;   - tag-shaped name (the simple case): firn tag enable <name>
    ;;   - module name that's currently in :disabled: firn module enable <name>
    ;;     (un-blacklist) — picks this when the bare name is a known module.
    ;;   - otherwise: tag enable (auto-creates the tag entry — tag-resolve
    ;;     will validate against the universe).
    (cons "enable"
          (λ (args)
            (cond
              [(null? args) #f]
              [else
               (define name (car args))
               (define kind (find-name-kind name))
               (case kind
                 [(module) (list "module" "enable" name)]
                 [else (list "tag" "enable" name)])])))
    (cons "disable"
          (λ (args)
            (cond
              [(null? args) #f]
              [else
               (define name (car args))
               (define kind (find-name-kind name))
               (case kind
                 [(module) (list "module" "disable" name)]
                 [else (list "tag" "disable" name)])])))
    ;; firn bundle ... — bundle node was removed (zero users); emit a
    ;; pointed error so anyone with muscle memory gets the right hint.
    (cons "bundle"
          (λ (_)
            (eprintf "firn: the 'bundle' node was removed (zero users).\n")
            (eprintf "  Use the tag system instead:\n")
            (eprintf "    firn tag enable  <tag>\n")
            (eprintf "    firn tag disable <tag>\n")
            (eprintf "    firn tag opt-in  <tag>+<module>\n")
            (eprintf "    firn tag status\n")
            (exit 1)))
    ;; firn rebuild [host] [--skip-checks]
    (cons "rebuild"
          (λ (args)
            ;; Pass --skip-checks through by appending after the leaf;
            ;; host-rebuild handler reads it from its argv tail. Simplest:
            ;; pack everything into the leaf via a sentinel join.
            (cond
              [(member "--skip-checks" args)
               (define host (or (findf (λ (a) (not (equal? a "--skip-checks"))) args) "current"))
               (list "host" "rebuild" (string-append host "+skip"))]
              [else
               (define host (if (pair? args) (car args) "current"))
               (list "host" "rebuild" host)])))
    (cons "doctor"  (λ (_) (list "host"   "doctor")))
    (cons "architecture" (λ (args) (append (list "repo" "architecture") args)))
    (cons "gen"     (λ (_) (list "host"   "gen")))
    (cons "diff"    (λ (args)
                      (define rest (filter (λ (a) (not (regexp-match? #rx"^--" a))) args))
                      (define target (if (pair? rest) (car rest) "all"))
                      (list "repo" "diff" target)))
    (cons "upgrade" (λ (args) (cond [(member "--dry-run" args) (list "repo" "upgrade" "dry-run")]
                                    [else                      (list "repo" "upgrade" "now")])))
    ;; firn update [host] [--no-rebuild|--dry-run] — the headline "update
    ;; my whole OS" verb: bump every flake input, then install. Chains the
    ;; existing `repo upgrade now` + `host rebuild` edges; `repo upgrade`
    ;; exits 1 on flake-update/validate failure, so a broken bump never
    ;; reaches the rebuild. --no-rebuild = fetch only; --dry-run = preview.
    (cons "update"
          (λ (args)
            (define positional (filter (λ (a) (not (regexp-match? #rx"^--" a))) args))
            (define host (if (pair? positional) (car positional) "current"))
            (cond
              [(member "--dry-run" args)    (list "repo" "upgrade" "dry-run")]
              [(member "--no-rebuild" args) (list "repo" "upgrade" "now")]
              [else (list "repo" "upgrade" "now" "host" "rebuild" host)])))
    (cons "watch"   (λ (_) (list "repo" "watch")))
    (cons "list"    (λ (args)
                      (cond
                        [(member "--used" args)   (list "module" "list" "used")]
                        [(member "--unused" args) (list "module" "list" "unused")]
                        [else                     (list "module" "list" "all")])))
    (cons "refs"    (λ (args)
                      (cond
                        [(null? args) #f]
                        [else (list "module" "refs" (car args))])))
    (cons "mod"     (λ (args)
                      (cond [(null? args) #f]
                            [else (list "module" "add" (car args))])))
    (cons "scaffold" (λ (args)
                       (cond [(< (length args) 2) #f]
                             [else (list "template" (car args) (cadr args))])))
    (cons "explain"  (λ (args)
                       (cond [(null? args) #f]
                             [else (list "schema" "explain" (string-join args " "))])))
    (cons "secret"   (λ (args)
                       (cond
                         [(null? args) #f]
                         [(equal? (car args) "list") (list "secret" "list" "all")]
                         [(equal? (car args) "show")
                          (cond [(null? (cdr args)) #f]
                                [else (list "secret" "show" (cadr args))])]
                         [else (list "secret" "edit" (car args))])))
    (cons "tags"     (λ (args)
                       (cond
                         [(null? args) (list "tag" "list" "all")]
                         [(equal? (car args) "--index")
                          (cond [(member "--stdout" args) (list "tag" "index" "stdout")]
                                [else                     (list "tag" "index" "repo")])]
                         [(equal? (car args) "--filter")
                          (cond [(null? (cdr args)) #f]
                                [else (list "tag" "filter" (cadr args))])]
                         [else (list "tag" "show" (car args))])))
    (cons "platforms" (λ (args)
                        (cond
                          [(null? args) (list "platform" "list" "all")]
                          [(equal? (car args) "darwin")     (list "platform" "list" "darwin")]
                          [(equal? (car args) "linux")      (list "platform" "list" "linux")]
                          [(equal? (car args) "--safelist") (list "platform" "safelist" "all")]
                          [else (list "platform" "show" (car args))])))
    (cons "build"    (λ (_) (list "repo" "build")))
    (cons "validate" (λ (_) (list "repo" "validate")))
    (cons "lint"     (λ (_) (list "repo" "lint")))
    (cons "impact"   (λ (args)
                       (define host (if (pair? args) (car args) "current"))
                       (list "host" "impact" host)))))

(define (maybe-legacy-rewrite tokens)
  ;; Returns the rewritten token list if the first token is a legacy
  ;; command name AND the second token is NOT a known edge of an entity
  ;; named by the first token (which would mean the user is already
  ;; using the entity-first shape).
  (cond
    [(null? tokens) tokens]
    [else
     (define first (car tokens))
     (define rest (cdr tokens))
     (cond
       ;; If first token is a registered node AND there's a 2nd token
       ;; that's a known edge of it, don't rewrite — they're using the
       ;; entity-first shape.
       [(and (member first (nodes))
             (pair? rest)
             (lookup-edge first (car rest)))
        tokens]
       [else
        (define alias (assoc first LEGACY-ALIASES))
        (cond
          [alias
           (define rewritten ((cdr alias) rest))
           (cond
             [rewritten rewritten]
             [else tokens])]
          [else tokens])])]))

;; ---------- help ----------

(define (cmd-help _args)
  (printf "firn — FirnOS config management\n\n")
  (printf "Usage:\n  firn <node> <edge> [<leaf>]  [<node> <edge> [<leaf>] ...]\n\n")
  (printf "Common shortcuts (default host is auto-detected):\n")
  (printf "  firn update           bump all flake inputs + rebuild (--no-rebuild = fetch only)\n")
  (printf "  firn rebuild          build + validate + switch (current host)\n")
  (printf "  firn build            regenerate .nix from .bnix\n")
  (printf "  firn validate         lint + type/package/path check\n")
  (printf "  firn impact           what will rebuild, estimated time\n")
  (printf "  firn doctor           repo health check\n")
  (printf "  firn architecture     regenerate the local Claude-system map (docs/claude/02-local-map.md)\n")
  (printf "  firn status           modules enabled directly in configuration.bnix\n")
  (printf "  firn tag status       enabled-tags.bnix + resolved active modules\n")
  (printf "  firn tag enable <t>   add a tag to the current host\n")
  (printf "  firn tag opt-in <t>+<m>   add +<module> under tag <t>\n")
  (printf "  firn module disable <m>   add <m> to :disabled (hard off)\n")
  (printf "  firn diff             re-emit and diff vs committed .nix\n")
  (printf "\nFull graph:\n\n")
  (for ([n (in-list (nodes))])
    (printf "~a\n" n)
    (define widest
      (apply max 0
             (map (λ (e) (string-length
                          (string-append (walk-edge-edge e) " "
                                         (walk-edge-leaf-shape e))))
                  (edges-of n))))
    (for ([e (in-list (edges-of n))])
      (define head (string-append (walk-edge-edge e) " " (walk-edge-leaf-shape e)))
      (printf "  ~a  ~a\n" (~a head #:min-width widest) (walk-edge-desc e)))
    (newline)))

;; ---------- main ----------

(define (main argv)
  (cond
    [(null? argv) (cmd-help argv)]
    [(member (car argv) '("help" "-h" "--help")) (cmd-help (cdr argv))]
    [else
     (dispatch (maybe-legacy-rewrite argv))]))

(main (vector->list (current-command-line-arguments)))
