;;; config.el -*- lexical-binding: t; -*-

;; Use bash internally to avoid issues with non-POSIX shells
(setq shell-file-name (executable-find "bash"))
;; But keep fish for terminal emulators
(setq-default vterm-shell "/run/current-system/sw/bin/fish")
(setq-default explicit-shell-file-name "/run/current-system/sw/bin/fish")

;; Load stylix-generated base16 theme (colors from NixOS stylix module)
(add-to-list 'custom-theme-load-path "~/.config/doom-stylix")
(setq doom-theme 'stylix-theme)
;; Match mini.base16 (neovim): cursor uses foreground (base05), not red (base08)
(add-hook! 'doom-load-theme-hook
  (set-face-attribute 'cursor nil :background (face-foreground 'default)))
;; Disable line numbers
(setq display-line-numbers-type nil)
;; Hide bookmark fringe marks (e.g. from org-refile)
(setq bookmark-set-fringe-mark nil)

;; Auto-save files on idle
(auto-save-visited-mode +1)

;; Hide modeline by default
(global-hide-mode-line-mode +1)

;; Uncomment to disable syntax highlighting globally (re-enable per mode as needed):
;; (global-font-lock-mode -1)
;; (add-hook 'org-mode-hook #'font-lock-mode)

;; Font configuration
(let ((mono (or (getenv "NIXOS_MONO_FONT") "CommitMono"))
      (serif (or (getenv "NIXOS_SERIF_FONT") "iA Writer Quattro S")))
  (setq doom-font (font-spec :family mono :size 16)
        doom-big-font (font-spec :family mono :size 20)
        doom-variable-pitch-font (font-spec :family serif :size 16)))

;; Disable automatic eldoc popups
(setq eldoc-idle-delay most-positive-fixnum)

(defun insert-date ()
  "Insert today's date at point as YYYY-MM-DD."
  (interactive)
  (insert (format-time-string "%Y-%m-%d")))

;; Kill the other window without switching to it
(defun kill-other-window ()
  (interactive)
  (if (one-window-p)
      (message "No other window to kill")
    (save-selected-window
      (other-window 1)
      (delete-window))))
(map! :leader
      :desc "Kill other window"
      "w o" #'kill-other-window)

;; Org mode configuration
(setq org-directory "~/org")

;; Elfeed: point elfeed-org at our dotfiles-managed elfeed.org
(setq rmh-elfeed-org-files (list (expand-file-name "elfeed.org" doom-user-dir)))
(after! org
  (setq org-hide-emphasis-markers t)
  (setq org-log-done 'time)
  (setq org-agenda-hide-tags-regexp "agenda"))

(map! :after org
      :map org-mode-map
      "C-S-<return>" #'org-insert-todo-subheading)

;; Log time to the task at point with a start time, duration, and optional date
(defun +org/log-time (start-time minutes &optional date)
  "Add MINUTES of clocked time starting at START-TIME to the org heading at point.
START-TIME is a string like \"9:30\" or \"0900\".
DATE is optional: \"02-25\" (mm-dd, current year) or \"2026-02-25\" (yyyy-mm-dd).
If empty or omitted, today is used."
  (interactive
   (list (read-string "Start time (e.g. 0900 or 9:00): ")
         (read-number "Minutes: ")
         (org-read-date nil nil nil "Date: ")))
  (require 'org-clock)
  (org-back-to-heading t)
  (let* ((time-norm (if (string-match ":" start-time)
                        start-time
                      (replace-regexp-in-string
                       "\\`\\([0-9]\\{1,2\\}\\)\\([0-9]\\{2\\}\\)\\'"
                       "\\1:\\2" start-time)))
         (hm (split-string time-norm ":"))
         (parsed-date (parse-time-string date))
         (start (encode-time 0 (string-to-number (cadr hm)) (string-to-number (car hm))
                             (nth 3 parsed-date) (nth 4 parsed-date) (nth 5 parsed-date)))
         (end (time-add start (seconds-to-time (* minutes 60)))))
    (org-clock-find-position nil)
    (insert-before-markers
     "CLOCK: "
     (org-timestamp-translate (org-timestamp-from-time start t t) 'end)
     "--"
     (org-timestamp-translate (org-timestamp-from-time end t t) 'end)
     " => " (format "%5s" (org-duration-from-minutes minutes)) "\n"))
  (message "Logged %d minutes from %s" minutes start-time))
(map! :leader
      :desc "Log time to task"
      "n t" #'+org/log-time)

;; UUIDv7 generator
(defun +org/uuidv7 ()
  "Generate a UUIDv7 string (48-bit ms timestamp + random, per RFC 9562)."
  (let* ((ms (truncate (* 1000 (float-time))))
         (rand-a (random 4096))
         (rand-b-hi (logior #x8000 (random #x4000)))
         (rand-b-lo (logior (ash (random #x1000000) 24)
                            (random #x1000000))))
    (format "%08x-%04x-7%03x-%04x-%012x"
            (ash ms -16)
            (logand ms #xffff)
            rand-a
            rand-b-hi
            rand-b-lo)))

;; Rename org-roam node: update title, EXPORT_FILE_NAME, and filename on disk
(defun +org/rename-node (new-title)
  "Rename the current org-roam node: update #+title, #+EXPORT_FILE_NAME, and rename the file."
  (interactive "sNew title: ")
  (unless (org-roam-file-p)
    (user-error "Not an org-roam file"))
  (let* ((slug (org-roam--title-to-slug new-title))
         (old-path (buffer-file-name))
         (old-name (file-name-nondirectory old-path))
         ;; Preserve the timestamp prefix (e.g. "20260403123456-")
         (prefix (if (string-match "^\\([0-9]\\{14\\}-\\)" old-name)
                     (match-string 1 old-name)
                   ""))
         (new-name (concat prefix slug ".org"))
         (new-path (expand-file-name new-name (file-name-directory old-path))))
    (save-excursion
      (goto-char (point-min))
      (if (re-search-forward "^#\\+title:.*$" nil t)
          (replace-match (concat "#+title: " new-title))
        (user-error "No #+title found"))
      (goto-char (point-min))
      (if (re-search-forward "^#\\+EXPORT_FILE_NAME:.*$" nil t)
          (replace-match (concat "#+EXPORT_FILE_NAME: " slug))
        (when (re-search-forward "^:END:" nil t)
          (end-of-line)
          (insert (format "\n#+EXPORT_FILE_NAME: %s" slug)))))
    (save-buffer)
    (unless (string= old-path new-path)
      (rename-file old-path new-path)
      (set-visited-file-name new-path t t)
      (save-buffer))
    (org-roam-db-sync)))
(map! :leader
      :desc "Rename org-roam node"
      "n R" #'+org/rename-node)

;; Migrate UUIDv7 files back to timestamp-slug filenames
(defun +org/migrate-from-uuidv7 ()
  "Rename all UUIDv7-named org-roam files to TIMESTAMP-slug.org format.
Extracts the timestamp from the UUIDv7 and the slug from EXPORT_FILE_NAME or title."
  (interactive)
  (require 'org-roam)
  (let ((files (org-roam-list-files))
        (count 0))
    (dolist (f files)
      (let ((old-name (file-name-nondirectory f)))
        ;; Only process UUIDv7 files
        (when (string-match "^\\([0-9a-f]\\{8\\}\\)-\\([0-9a-f]\\{4\\}\\)-7" old-name)
          (let* ((hex-hi (match-string 1 old-name))
                 (hex-lo (match-string 2 old-name))
                 (ms (+ (* (string-to-number hex-hi 16) 65536)
                        (string-to-number hex-lo 16)))
                 (timestamp (format-time-string "%Y%m%d%H%M%S"
                                                (seconds-to-time (/ ms 1000)))))
            (with-current-buffer (find-file-noselect f)
              (let* ((slug (save-excursion
                             (goto-char (point-min))
                             (if (re-search-forward "^#\\+EXPORT_FILE_NAME:\\s-*\\(.+\\)" nil t)
                                 (string-trim (match-string 1))
                               (goto-char (point-min))
                               (when (re-search-forward "^#\\+title:\\s-*\\(.+\\)" nil t)
                                 (org-roam--title-to-slug (string-trim (match-string 1)))))))
                     (new-name (concat timestamp "-" slug ".org"))
                     (new-path (expand-file-name new-name (file-name-directory f))))
                (save-buffer)
                (rename-file f new-path)
                (set-visited-file-name new-path t t)
                (save-buffer)
                (cl-incf count)))))))
    (org-roam-db-sync)
    (message "Migrated %d files from UUIDv7 to timestamp-slug. Database synced." count)))

;; Markdown mode configuration
(after! markdown-mode
  (setq-default markdown-hide-markup t)
  (setq markdown-list-item-bullets '("-")))

;; Org-roam configuration
(setq org-roam-directory "~/org-roam")
(setq org-roam-db-location "~/org-roam/org-roam.db")

;; Auto-tag roam files with :agenda: when they gain agenda-relevant content
(defun +org/ensure-agenda-tag ()
  "Add :agenda: filetag to current org-roam file if not already present.
Also refreshes the agenda file cache."
  (interactive)
  (when (and (buffer-file-name) (org-roam-file-p))
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        (unless (re-search-forward "^#\\+filetags:.*:agenda:" nil t)
          (goto-char (point-min))
          (if (re-search-forward "^#\\+filetags:\\(.*\\)" nil t)
              (replace-match (concat (match-string 0) " :agenda:"))
            (while (re-search-forward "^#\\+.*:.*$" nil t))
            (end-of-line)
            (insert "\n#+filetags: :agenda:"))
          (save-buffer)
          (let ((f (buffer-file-name)))
            (unless (member f org-agenda-files)
              (push f org-agenda-files))))))))

(add-hook 'org-after-todo-state-change-hook #'+org/ensure-agenda-tag)
(add-hook 'org-schedule-hook #'+org/ensure-agenda-tag)
(add-hook 'org-deadline-hook #'+org/ensure-agenda-tag)

;; Build agenda file list from roam files tagged :agenda:
(defun +org/agenda-files ()
  "Return org-roam files that have the :agenda: filetag."
  (seq-filter
   (lambda (f)
     (with-temp-buffer
       (insert-file-contents f nil 0 512)
       (re-search-forward "^#\\+filetags:.*:agenda:" nil t)))
   (org-roam-list-files)))

(defvar +org/agenda-files-cache nil)

(defun +org/refresh-agenda-files ()
  "Rebuild the agenda file cache."
  (setq +org/agenda-files-cache (+org/agenda-files))
  (setq org-agenda-files +org/agenda-files-cache))

(after! org-roam
  (+org/refresh-agenda-files))

;; Capture templates for org-roam (UUIDv7 filenames)
(after! org-roam
  (setq org-roam-capture-templates
        '(("d" "default" plain "%?"
           :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+date: %U\n#+EXPORT_FILE_NAME: ${slug}\n")
           :unnarrowed t)
          ("p" "public" plain "%?"
           :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                              "#+title: ${title}\n#+date: %U\n#+EXPORT_FILE_NAME: ${slug}\n#+filetags: :public:\n")
           :unnarrowed t))))

;; ox-hugo configuration
(after! ox-hugo
  (setq org-hugo-base-dir "~/code/blog"
        org-hugo-default-section-directory "")

  ;; Only export #+hugo_tags: to Hugo front matter, never filetags
  (defadvice! +org/hugo-no-filetags-as-tags (orig-fn &rest args)
    :around #'org-hugo--get-tags
    (let ((org-use-tag-inheritance nil))
      (apply orig-fn args))))

;; Export all public org-roam files to Hugo
(defun +org/hugo-publish-all ()
  "Export all org-roam files tagged :public: to Hugo via ox-hugo."
  (interactive)
  (require 'ox-hugo)
  (let ((exported 0)
        (skipped 0)
        (failed nil))
    (dolist (f (org-roam-list-files))
      (with-current-buffer (find-file-noselect f)
        (if (not (member "public" (+org/file-tags)))
            (cl-incf skipped)
          (condition-case err
              (progn
                (org-hugo-export-wim-to-md)
                (cl-incf exported))
            (error
             (push (cons f (error-message-string err)) failed)
             (message "ox-hugo: FAILED %s: %s"
                      (file-name-nondirectory f)
                      (error-message-string err)))))))
    (+org/hugo-ensure-section-indexes)
    (message "ox-hugo: %d exported, %d skipped, %d failed"
             exported skipped (length failed))
    (when failed
      (message "Failed:\n%s"
               (mapconcat (lambda (p) (format "  %s: %s" (car p) (cdr p)))
                          failed "\n")))))

(defun +org/file-tags ()
  "Return file-level tags from #+filetags as a list of strings."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (when (re-search-forward "^#\\+filetags:\\s-*\\(.*\\)" nil t)
        (split-string (match-string-no-properties 1) ":" t)))))

(defun +org/hugo-ensure-section-indexes ()
  "Create _index.md for any content subdirectory missing one."
  (let ((content-dir (expand-file-name "content" org-hugo-base-dir)))
    (dolist (dir (directory-files content-dir t "\\`[^.]"))
      (when (file-directory-p dir)
        (let ((index (expand-file-name "_index.md" dir)))
          (unless (file-exists-p index)
            (write-region
             (format "---\ntitle: \"%s\"\n---\n"
                     (capitalize (file-name-nondirectory dir)))
             nil index)))))))

;; #region / #endregion folding for CSS, JS, etc.
(defun +fold/region-fold-p ()
  "Set up #region / #endregion folding via outline-mode."
  (setq-local outline-regexp ".*#region\\|.*#endregion")
  (setq-local outline-level (lambda () 1))
  (outline-minor-mode 1))

(add-hook 'css-mode-hook #'+fold/region-fold-p)
(add-hook 'js-mode-hook #'+fold/region-fold-p)
(add-hook 'typescript-mode-hook #'+fold/region-fold-p)
