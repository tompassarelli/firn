#lang racket/base

;; firn repo architecture — (re)generate the Claude-system architecture map.
;; Shells to scripts/firn-architecture, which walks the live filesystem +
;; settings + plugin manifests and rewrites docs/claude-os-architecture.md.
;; The map is GENERATED, never hand-maintained — that's the whole point.

(require racket/path
         "util.rkt")

(provide node-edges)

(define (handle-architecture _leaf)
  (sh (path->string (in-repo "scripts" "firn-architecture")) "--write"))

(define node-edges
  (list
   (walk-edge "repo" "architecture" "all" 'all handle-architecture
              "regenerate + print the Claude-system architecture map (docs/claude-os-architecture.md)")))
