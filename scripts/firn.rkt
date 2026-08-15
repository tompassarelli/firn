#!/usr/bin/env racket
#lang racket/base

;; firn — config management CLI.
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
;; `firn rebuild [host]` is the canonical operator shortcut. Every other
;; command uses the entity-first graph directly.

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

(define (dispatch-command argv)
  (cond
    [(equal? (car argv) "rebuild")
     (cond
       [(or (> (length argv) 2)
            (and (pair? (cdr argv))
                 (string-prefix? (cadr argv) "-")))
        (eprintf "Usage: firn rebuild [host]\n")
        (exit 1)]
       [else
        (dispatch (list "host" "rebuild"
                        (if (pair? (cdr argv)) (cadr argv) "current")))])]
    [else (dispatch argv)]))

;; ---------- help ----------

(define (cmd-help _args)
  (printf "firn — config management\n\n")
  (printf "Usage:\n  firn <node> <edge> [<leaf>]  [<node> <edge> [<leaf>] ...]\n\n")
  (printf "Operator shortcut:\n")
  (printf "  firn rebuild          build + validate + switch (current host)\n")
  (printf "\nCommon graph commands:\n")
  (printf "  firn repo build       regenerate .nix from .bnix\n")
  (printf "  firn repo validate    lint + type/package/path check\n")
  (printf "  firn host impact      what will rebuild, estimated time\n")
  (printf "  firn repo doctor      repo health check\n")
  (printf "  firn tag status       enabled-tags.bnix + resolved active modules\n")
  (printf "  firn tag enable <t>   add a tag to the current host\n")
  (printf "  firn tag opt-in <t>+<m>   add +<module> under tag <t>\n")
  (printf "  firn module disable <m>   add <m> to :disabled (hard off)\n")
  (printf "  firn repo diff        re-emit and diff vs committed .nix\n")
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
     (dispatch-command argv)]))

(r:finish-runtime-startup-span!)
(main (vector->list (current-command-line-arguments)))
