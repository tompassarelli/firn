#lang racket/base

;; firn repo architecture — (re)generate the local Claude-system map.
;; Shells to scripts/firn-architecture, which walks the live filesystem +
;; settings + plugin manifests and rewrites docs/claude/02-local-map.md (layer 2
;; of the docs/claude/ bundle). The map is GENERATED, never hand-maintained.

(require racket/path
         "util.rkt")

(provide node-edges)

(define (handle-architecture leaf)
  (define script (path->string (in-repo "scripts" "firn-architecture")))
  (if (member leaf '("bundle" "--bundle"))
      (sh script "--bundle")    ; print canonical + local + lodestar, top to bottom
      (sh script "--write")))    ; regenerate docs/claude/02-local-map.md + print it

(define node-edges
  (list
   (walk-edge "repo" "architecture" "all|bundle" 'all handle-architecture
              "regenerate the local Claude map (docs/claude/02-local-map.md); `bundle` prints the full read")))
