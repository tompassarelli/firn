(ns spaces.rt
  "Untyped runtime edge for spaces.main: blocking IO loops and host calls
   the typed beagle/clj stdlib does not cover yet. Every function here is a
   typed-stdlib gap datum for the beagle upstream thread."
  (:require [babashka.process :as proc]
            [clojure.java.io :as io]
            [cheshire.core :as json]))

(defn sleep-ms [ms] (Thread/sleep ms) nil)

(defn getenv-or [k fallback]
  (or (System/getenv k) fallback))

(defn parse-int-or [s fallback]
  (try (Integer/parseInt (str s)) (catch Exception _ fallback)))

(defn parse-json-safe [s]
  (try (json/parse-string s) (catch Exception _ nil)))

(defn my-pid []
  (.pid (java.lang.ProcessHandle/current)))

(defn pid-alive [pid]
  (let [oh (java.lang.ProcessHandle/of pid)]
    (and (.isPresent oh) (.isAlive (.get oh)))))

(defn mkfifo [path]
  (proc/shell "mkfifo" (str path))
  nil)

(defn- safely
  "A throwing handler must never kill its reader loop — log and continue."
  [on-line line]
  (try
    (on-line line)
    (catch Exception e
      (println "spaces handler error:" (.getMessage e)))))

(defn process-lines
  "Spawn cmd, feed each stdout line to on-line; returns the exit code."
  [cmd on-line]
  (let [p (proc/process cmd {:err :inherit})]
    (with-open [r (io/reader (:out p))]
      (doseq [line (line-seq r)]
        (safely on-line line)))
    (:exit @p)))

(defn fifo-lines
  "Consume lines from a FIFO until writer-side EOF; caller reopens."
  [path on-line]
  (with-open [r (io/reader (str path))]
    (doseq [line (line-seq r)]
      (safely on-line line)))
  nil)

(defn write-line-timeout
  "Write one line to a FIFO; false when no reader appears within timeout-ms."
  [path line timeout-ms]
  (let [f (future (spit (str path) (str line "\n")) true)
        v (deref f timeout-ms ::timeout)]
    (if (= v ::timeout)
      (do (future-cancel f) false)
      true)))
