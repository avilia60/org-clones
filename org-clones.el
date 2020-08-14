;; org-clones.el --- Clone org headings -*- lexical-binding: t; -*-

;; "Node" means an entry in an org outline
;; "Body" means everything after the headline, planning line,
;;        and property drawers until the next node.
;;        It does not include whitespace between the text and
;;        next node. 

(require 'org)
(require 'org-id)
(require 'ov)

(defface org-clones-clone
  '((t (:background "black")))
  "Body of cloned nodes.")

(face-spec-set 'org-clones-clone '((t (:background "black"))))

(defvar org-clones--headline-re "^*+ " ; outline-regexp
  "Org headline regexp.")

(defvar org-clones-empty-body-string "[empty clone body]"
  "Place holder inserted into clones with empty bodies.
Can be anything other than whitespace.")

(defvar org-clones--not-whitespace-re "[^[:space:]]"
  "Regexp to match any non-whitespace charcter.")

(defvar org-clones-clone-prefix-string "◈ "
  "String prepended to the headline of a cloned node.")


(defun org-clones--goto-body-end ()
  "Goto the end of the body of the current node, 
and return the point."
  (if (outline-next-heading)
      (point)
    (point-max)
    (re-search-backward org-clones--not-whitespace-re
			nil t)
    (goto-char (match-end 0))))

;;; Macros

(defmacro org-clones--inhibit-read-only (&rest body)
  `(let ((inhibit-read-only t))
     ,@body))

(defmacro org-clones--iterate-over-clones (&rest body)
  "Execute BODY at each clone of node at point."
  `(save-excursion
     (when-let ((clone-ids (org-entry-get-multivalued-property
			    (point)
			    "CLONED-WITH")))
       (cl-loop for clone-id in clone-ids
		do (org-clones--with-point-at-id
		     clone-id
		     ,@body)))))

(defmacro org-clones--with-point-at-id (id &rest body)
  "Switch to the buffer containing the entry with id ID.
Move the cursor to that entry in that buffer, execute BODY,
move back."
  (declare (indent defun))
  `(--when-let (org-id-find ,id 'marker)
     (save-excursion 
       (with-current-buffer (marker-buffer it)
	 (goto-char it)
	 ,@body))))

;;; Headline functions

(defun org-clones--goto-headline-start ()
  "Goto the first point of the headline, after the
leading stars."
  (org-back-to-heading t)
  (re-search-forward org-clones--headline-re nil (point-at-eol))
  (point))

(defun org-clones--get-headline-start ()
  "Get the point at the start of the headling, after
the leading stars."
  (save-excursion
    (org-clones--goto-headline-start)))

(defun org-clones--goto-headline-end ()
  "Goto the last point of the headline (i.e., before the
leading stars."
  (org-back-to-heading t)
  (unless (re-search-forward org-tag-re (point-at-eol) t)
    (end-of-line))
  (point))

(defun org-clones--get-headline-end ()
  "Get the point at the end of the headline, but
before the ellipsis."
  (save-excursion 
    (org-clones--goto-headline-end)))

(defun org-clones--delete-headline ()
  "Replace the headline of the heading at point." 
  (delete-region (org-clones--get-headline-start)
		 (org-clones--get-headline-end)))

(defun org-clones--get-headline-string ()
  "Get the full text of a headline at point, including
TODO state, headline text, and tags." 
  (buffer-substring (org-clones--get-headline-start)
		    (org-clones--get-headline-end)))

(defun org-clones--replace-headline (headline)
  "Replace the headline text at point with HEADLINE."
  (save-excursion 
    (org-clones--delete-headline)
    (org-clones--goto-headline-start)
    (insert headline)))

(defun org-clones--get-body-end ()
  "Get the end point of the body of the current node."
  (save-excursion (org-clones--goto-body-end)))

;; (defun org-clones--node-body-p ()
;;   "Does this node have a body (i.e., a section in org-element
;; parlance?"
;;   (org-clone--get-body-elements))

;;; Body functions 

(defun org-clones--insert-blank-body ()
  "Insert `org-clones-empty-body-string' into the body 
of the current node."
  (org-clones--replace-body org-clones-empty-body-string))

(defun org-clones--goto-body-start ()
  "Go to the start of the body of the current node,
and return the point."
  (org-end-of-meta-data t)
  (point))

(defun org-clones--get-body-start ()
  "Get the start point of the body of the current node."
  (save-excursion (org-clones--goto-body-start)))

(defun org-clones--replace-body (body)
  "Replace the body of the current node with
BODY."
  (save-excursion
    (org-clones--delete-body)
    (org-clones--goto-body-start)
    (insert body
	    "\n")))

(defun org-clones--parse-body ()
  "Parse all elements from the start of the body to the next node.
and return the tree beginning with the section element."
  (org-element--parse-elements (save-excursion (org-back-to-heading)
					       (org-end-of-meta-data t)
					       (point))
			       (or (save-excursion (outline-next-heading))
				   (point-max))
			       'first-section nil nil nil nil))

(defun org-clones--get-body-as-string ()
  "Get the body of the current node as a string." 
  (org-element-interpret-data 
   (org-clones--get-section-elements)))

(defun org-clones--get-section-elements ()
  "Reduce the section data to the component elements,
e.g., '((paragraph (...))
        (src-block (...)) ...)."
  (cddar (org-clones--parse-body)))

(defun org-clones--get-section-plist ()
  "Get the plist associated with the section element, 
e.g. (:begin 1 :end 10 :contents-begin ...)."
  (cadar (org-clones--parse-body)))

(defun org-clones--delete-body ()
  (when-let* ((prop-list (org-clones--get-section-plist))
	      (beg (plist-get prop-list :begin))
	      (end (plist-get prop-list :end)))
    (delete-region beg end)))

;;; Navigate functions 

(defun org-clones--last-node-p ()
  "Is this the last node in the document?"
  (not (or (save-excursion (org-get-next-sibling))
	   (save-excursion (org-goto-first-child)))))

(defun org-clones--prompt-for-source-and-move ()
  "Prompt user for a node and move to it."
  (org-goto))

;;; Clone creation

;;;###autoload 
(defun org-clones-create-clone (&optional id)
  "Insert a new headline, prompt the user for the source node,
add clone properties to the source, add clone properties to the clone
and add the headline and body from the source to the clone."
  (interactive)
  (let (source-headline source-body source-id source-clone-list	clone-id)

    ;; Create the new heading, save the ID
    (org-insert-heading-respect-content)
    (setq clone-id (org-id-get-create))
    
    ;; At the source node...
    (save-excursion 
      (org-clones--prompt-for-source-and-move)
      (org-clones--remove-clone-effects)
      (setq source-headline (org-clones--get-headline-string))
      (setq source-body (org-clones--get-body))
      (when (string= "" source-body)
	(org-clones--insert-blank-body)
	(setq source-body org-clones-empty-body-string))
      (setq source-id (org-id-get-create))
      (org-entry-add-to-multivalued-property (point)
					     "CLONED-WITH"
					     clone-id)
      (setq source-clone-list (org-entry-get-multivalued-property
			       (point)
			       "CLONED-WITH"))
      (org-clones--put-clone-effects))

    ;; For each clone from the source, add new clone id
    (cl-loop for clone-id in source-clone-list
	     do (org-clones--with-point-at-id clone-id
		  (cl-loop for clone in source-clone-list
			   do
			   (unless (string= clone (org-id-get-create))
			     (org-entry-add-to-multivalued-property (point)
								    "CLONED-WITH"
								    clone)))))
    
    ;; At the new clone...
    (org-entry-add-to-multivalued-property (point)
					   "CLONED-WITH"
					   source-id)
    (org-clones--replace-headline source-headline)
    (org-clones--replace-body source-body)
    (org-clones--put-clone-effects)))

(defun org-clones--update-clones ()
  "Update all clones of the current node to match
the headline and body of the current node and
place text properties and overlays in the cloned nodes."
  (interactive)
  (org-clones--remove-clone-effects)
  (let ((headline (org-clones--get-headline-string))
	(body (or (org-clones--get-body)
		  org-clones-empty-body-string)))
    (org-clones--put-clone-effects)
    (org-clones--iterate-over-clones
     (org-clones--remove-clone-effects)
     (org-clones--replace-headline headline)
     (org-clones--replace-body body)
     (org-clones--put-clone-effects))))

;;; Text properties and overlays 

(defun org-clones--make-read-only ()
  "Make the node at point read-only, for the purposes
of locking edits of the headline and body."
  (put-text-property (org-clones--get-headline-start)
		     (org-clones--get-headline-end)
		     'org-clones t)
  (put-text-property (org-clones--get-headline-start)
		     (org-clones--get-headline-end)
		     'read-only t)
  (put-text-property (org-clones--get-body-start)
		     (org-clones--get-body-end)
		     'org-clones t)
  (put-text-property (org-clones--get-body-start)
		     (org-clones--get-body-end)
		     'read-only t))

(defun org-clones--remove-read-only ()
  "Remove read-only text properties for the current node."
  (let ((inhibit-read-only t))
    (remove-text-properties (org-clones--get-headline-start)
			    (org-clones--get-headline-end)
			    '(read-only t 'face t))
    (remove-text-properties (org-clones--get-body-start)
			    (org-clones--get-body-end)
			    '(read-only t 'face t))))

(defun org-clones--put-text-properties ()
  "Make the node at point read-only, for the purposes
of locking edits of the headline and body."
  ;; For the headline...
  (cl-loop
   with beg = (org-clones--get-headline-start)
   with end = (org-clones--get-headline-end)
   for (prop . val) in `((org-clones-headline . t)
			 (read-only . t))
   do (put-text-property beg end prop val))

  ;; For the body...
  (cl-loop
   with beg = (org-clones--get-body-start)
   with end = (org-clones--get-body-end)
   for (prop . val) in `((org-clones-body . t)
			 (read-only . t))
   do (put-text-property beg end prop val)))

(defun org-clones--remove-text-properties ()
  "Remove read-only text properties for the current node."
  (let ((inhibit-read-only t))
    (remove-text-properties (org-clones--get-headline-start)
			    (org-clones--get-headline-end)
			    '(read-only t org-clones t))

    (remove-text-properties (org-clones--get-body-start)
			    (org-clones--get-body-end)
			    '(read-only t org-clones t))))

(defun org-clones--remove-overlays ()
  "Remove the clone overlay at the headline and body
of the current node."
  (ov-clear (org-clones--get-headline-start)
	    (org-clones--get-headline-end)
	    'face 'org-clones-clone)
  (ov-clear (org-clones--get-body-start)
	    (org-clones--get-body-end)
	    'face 'org-clones-clone))

(defun org-clones--put-clone-effects ()
  "Put overlay and text properties at the current
node."
  (org-clones--put-text-properties)
  (org-clones--put-overlays))

(defun org-clones--remove-clone-effects ()
  "Remove overlay and text properties at the current
node."
  (org-clones--remove-text-properties)
  (org-clones--remove-overlays))

(defun org-clones--put-all-clone-effects-in-buffer ()
  "Clear all overlays and text properties that might have been set 
previously. Place a new set of overlays and text properties at each
node with a CLONED-WITH property."
  (org-ql-select (current-buffer)
    '(property "CLONED-WITH")
    :action (lambda ()
	      (org-clones--iterate-over-clones
	       (org-clones--put-clone-effects)))))

(defun org-clones--remove-all-text-props-in-buffer ()
  (org-clones--inhibit-read-only
   (cl-loop for points being the intervals of (current-buffer) property 'org-clones
	    if (get-text-property (car points) 'org-clones)
	    do (remove-list-of-text-properties (car points) (cdr points)
					       '(asdf face read-only)))))

(defun org-clones--remove-all-clone-effects-in-buffer ()
  "Remove clone effects from all clones."
  (let ((inhibit-read-only t))
    (org-ql-select (current-buffer)
      '(property "CLONED-WITH")
      :action (lambda ()
		(org-clones--iterate-over-clones
		 (org-clones--remove-clone-effects))))))

(defun org-clones--put-overlays ()
  "Put the clone overlay at the headline and body
of the current node."
  (ov (org-clones--get-headline-start)
      (org-clones--get-headline-end)
      'face 'org-clones-clone
      'keymap org-clones-overlay-map
      'before-string org-clones-clone-prefix-string
      'evaporate t)

  (ov (org-clones--get-body-start)
      (org-clones--get-body-end)
      'face 'org-clones-clone
      'keymap org-clones-overlay-map
      'evaporate t))

;;; Interactive functions

(defun org-clones--edit-clone ()
  "Start edit mode."
  (interactive)
  (org-clones-edit-mode 1))

;;; Minor mode

(setq org-clones-overlay-map
      (let ((map (make-sparse-keymap)))
	(define-key map (kbd "RET") #'org-clones--edit-clone)
	map))
;;  "Keymap for overlays put on clones.")

;;;###autoload
(define-minor-mode org-clones-mode
  "Org heading transclusion minor mode."
  nil
  " ORG-CLONES"
  nil
  (if org-clones-mode
      (org-clones--put-all-clone-effects-in-buffer)
    (org-clones--remove-all-clone-effects-in-buffer)))

(provide 'org-clones)



