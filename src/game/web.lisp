(in-package #:tpd2.game)

(defmystruct move-state
    cc
  move-type
  player-state
  choices
  args)

(my-defun move-state game-state ()
  (player-game (my player-state)))

(defmystruct queued-choice
    move-type
  choice)

(defstruct (web-state (:constructor %make-web-state))
  session
  (id (random 10000000))
  (announcements (tpd2.io:with-sendbuf ()))
  (waiting-for-input nil)
  (queued-choices nil)
  game-state
  resigned)

(defun make-web-state (&rest args)
  (let ((state (apply '%make-web-state args)))
    (push state (session-var (web-state-session state) 'game-states))
    state))

(my-defun web-state 'player-controller-name ()
  (if (my resigned)
      "(resigned)"
      (session-username (my session))))

(my-defun web-state 'inform :before (game-state message &rest args)
	  (declare (ignore args))
	  (setf (my game-state) game-state))

(my-defun web-state add-announcement (a)
  (tpd2.io:sendbuf-add (my announcements) a))

(my-defun web-state 'inform (game-state (message (eql :select-card)) &rest args)
  (my add-announcement (<p (player-name (getf args :player)) " played " (output-object-to-ml (make-card-from-number (getf args :choice))) ".")))

(my-defun web-state 'inform (game-state (message (eql :reject-cards)) &rest args)
  (my add-announcement (<p (player-name (getf args :player)) 
			   (if (getf args :choice) " wants to change cards."
			       " is satisfied with the cards."))))

(my-defun web-state 'inform (game-state (message (eql :accept-new-stake)) &rest args)
  (my add-announcement (<p (player-name (getf args :player)) 
			   (if (getf args :choice) " saw the raise."
			       " folded."))))

(my-defun web-state 'inform (game-state (message (eql :select-new-stake)) &rest args)
  (let ((choice (getf args :choice)))
    (unless (eql choice (its stake game-state))
      (my add-announcement (<p (player-name (getf args :player)) " raised to " choice " chips.")))))

(my-defun web-state 'inform (game-state (message (eql :winner)) &rest args)
  (my add-announcement 
      (<p (player-name (getf args :player)) " won"
	  (awhen (getf args :chips)
	    (with-ml-output " " it " chips"))
	  ".")))

(my-defun web-state 'inform (game-state (message (eql :game-over)) &rest args)
  (my add-announcement (<h2 (player-name (getf args :player)) " won the game.")))

(my-defun web-state 'inform (game-state (message (eql :new-state)) &rest args)
  (declare (ignore args))
  (my add-announcement (<p "New game."))
  (setf (my queued-choices) nil))

(my-defun web-state 'inform (game-state message &rest args)
  (my add-announcement 
      (<p (format nil "~A ~{~A ~}"  message (mapcar (lambda(a)(if (player-p a) (player-name a) a)) args)))))

(defmethod move-continuation (k (controller web-state) player-state move-type choices &rest args)
  (its add-move-state controller
       (make-move-state :cc k
			:move-type move-type
			:player-state player-state
			:choices choices
			:args args)))

(my-defun web-state add-move-state (move-state)
  (appendf (my waiting-for-input)
	   (list move-state))
  (my try-to-move))

(my-defun web-state queue-choice (move-type choice)
  (appendf (my queued-choices)
	   (list (make-queued-choice :move-type move-type :choice choice)))
  (my try-to-move)
  (values))

(my-defun web-state try-to-move ()
  (loop for waiting in (my waiting-for-input) do
	(loop for qc in (my queued-choices)
	      do (when (eql (its move-type qc) (its move-type waiting))
		   (deletef qc (my queued-choices))
		   (deletef waiting (my waiting-for-input))
		   (funcall (its cc waiting) (its choice qc))
		   (return-from web-state-try-to-move)))))

(defmacro html-action-link (text &body body)
  (with-unique-names (params)
    `(<A :href (page-link "/action" 
			  :id (register-action-id (lambda(,params)(declare (ignore ,params)) ,@body))) ,text)))

(defmacro html-action-form (title lambda-list &body body)
  `(<form :method :post :action 
	  (page-link "/action" :id 
		     (register-action-id 
		      (lambda(params)
			(let ,(loop for p in lambda-list collect
				    `(,(force-first p) (or (cdr-assoc params ,(force-byte-vector (force-first p)) 
								      :test 'byte-vector=-fold-ascii-case)
							   ,(second (force-list p)))))
			  ,@body))))
	  (<p
	    ,title
	    ,@(loop for nv in lambda-list collect
		    (destructuring-bind (name &optional value)
			(force-list nv)
		      `(<input :type :text :name ,(force-byte-vector name) 
			       ,@(when value `(:value ,value)))))
	    (<input :type :submit :value "Send"))))

(defun standard-page-head (title)
  (<head
    (<title "mopoko " (string-downcase (force-string title)))
    (css-html-style 
      (<body :font-family "georgia, serif" :margin-left "5%" :margin-right "5%")
      ((<h1 <h2 <h3 <h4 <h5 <h6) :letter-spacing "0.03em" :font-weight "normal" :margin "0.1 0.1 0.1 0.1")
      (<h1 :font-size "400%" :text-align "right")
      (".change-name" :font-size "75%" :text-align "right")
      (".players" :width "100%" :margin-top "2em")
      (".messages" :margin-top "2em" :border-top "thin rgb(188,188,188) solid")
      (".close-game" :text-align "right" :float "right")
      (".close-game:before" :content "\"+ \"")
      (".players DIV" :width "25%" :display "table-cell" :vertical-align "top"))))

(defun standard-page-body-start (title)
  (declare (ignore title))
  (<div :class "header"
	(<h1 "mopoko" (<span :style (css-attrib :color "rgb(188,188,188)") ".com"))
	(<div :class "change-name" 
	      (html-action-form "Your name " ((new-name (session-username (webapp-session))))
		(setf (session-username (webapp-session)) new-name)
		(values)))))

(defmacro standard-page ((title) &rest body)
  (once-only (title)
    `(with-ml-output
       (output-raw-ml "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\"" 
		      " \"http://www.w3.org/TR/html4/loose.dtd\">")
       (<html
	 (output-raw-ml
	  (standard-page-head ,title))
	 (<body
	   (output-raw-ml
	    (standard-page-body-start ,title))
	   ,@body
	   (output-raw-ml
	    (content-game-messages)))))))

(defun handle-challenge (game player-session-id)
  (with-ml-output
    (let ((other (find-session player-session-id)))
      (when other
	(unless
	    (loop for pair in (webapp-session-var 'challengers) thereis
		  (destructuring-bind (g . p)
		      pair
		    (when (and (equalp g game) (eql p (session-id other)))
		      (deletef pair (webapp-session-var 'challengers))
		      (<h2 "Challenge accepted")
		      (launch-game game (list (make-web-state :session (webapp-session))
					      (make-web-state :session other)))
		      t)))
	  (<h2 "Challenge issued to " (session-username other))
	  (pushnew (cons game (session-id (webapp-session))) (session-var other 'challengers) :test 'equalp)))
      (values))))

(defun content-game-messages ()
  (<div :class "game-messages"
	(loop for (g . p) in (webapp-session-var 'challengers) do
	      (awhen (find-session p)
		(<p :class "challenge" (session-username it) " wants to play " (string-downcase (force-string g)) ". "
		    (let-current-values (g p)
		      (html-action-link "Accept" (handle-challenge g p))))))
	(if (webapp-session-var 'game-states)
	    (loop for state in (webapp-session-var 'game-states) do
		  (output-object-to-ml state))
	    (<div :class "start-games"
		  (loop for game being the hash-keys of *games* do
			(<h2 :class "start-game" (<A :href (page-link (game-start-page game)) "Play " (string-downcase (force-string game)))))))))


(defun register-action-id (function)
  (let ((id (random 1000000000)))
    (push (cons id function) (webapp-session-var 'actions))
    id))

  
(defpage "/action" (id all-http-params)
  (let ((ml 		   
	 (awhen (and id (assoc (byte-vector-parse-integer id) (webapp-session-var 'actions)))
	   (prog1 (with-ml-output (output-raw-ml (funcall (cdr it) all-http-params)))
	     (deletef it (webapp-session-var 'actions))))))
    (standard-page ("") 
		   (output-raw-ml ml))))

(defun page-start-game (name)
  (webapp-session)
  (standard-page ((strcat "Play " (string-capitalize (force-string name))))
		 (<h4 "Match wits with a robot")
		 (<ul
		   (loop for bot in *bots* do
			 (<li (let-current-values (bot)
				(html-action-link (player-controller-name bot) 
				  (launch-game name (list (make-web-state :session (webapp-session)) bot))
				  (values))))))
		 (<h4 "Challenge a player ")
		 (<ul
		   (loop for session in (list-all-sessions) unless (eql session (webapp-session))
			 do
			 (<li 
			   (let-current-values (session name)
			     (html-action-link (session-username session)
			       (handle-challenge name (session-id session)))))))))

(eval-always
  (defun game-start-page (game-name)
    (strcat "/play/" (string-downcase (force-string game-name)))))

(defmacro defgamepages ()
  `(progn 
     ,@(loop for game being the hash-keys of *games* 
	     collect
	     `(defpage ,(game-start-page game) ()
		(page-start-game ,game)))))

(defgamepages)





(defun keyword-to-friendly-string (keyword)
  (string-capitalize (string-downcase (force-string (match-replace-all "-" " " keyword))) :end 1))

(my-defun move-state queue-choice (choice)
  (web-state-queue-choice (player-controller (my player-state)) (my move-type) choice))

(my-defun move-state 'object-to-ml ()
  (<div :class "move-state"
	(let ((friendly-move-type (keyword-to-friendly-string (my move-type))))
	  (cond ((eq :boolean (my choices))
		 (<p 
		   (loop for (keyword value) on (my args) by #'cddr
			 do (with-ml-output "The " (string-downcase (keyword-to-friendly-string keyword)) " is " value ". "))
		   
		   friendly-move-type
		   "? "
		    
		   (output-raw-ml (html-action-link "Yes" (my queue-choice t) (values)))
		   " "
		   (output-raw-ml (html-action-link "No" (my queue-choice nil) (values)))))
		((eql :select-card (my move-type))
		 (<p friendly-move-type "."))
		(t
		 (<p friendly-move-type
		     (output-raw-ml (html-action-form 		     
					(cond ((eql (force-first (my choices)) :integer)
					       (with-ml-output " from " (apply 'min (choices-list (my choices))) " to " 
							       (apply 'max (choices-list (my choices))) ". "))
					      (t
					       (format nil " ~{~A ~}" (my args)) " from " (format nil "~A" (my choices) )))
					((choice (first (choices-list (my choices)))))
				      (my queue-choice (read-safely-from-string choice))
				      (values)))))))))

(my-defun game 'object-to-ml ()
  (<div :class "players"
	(loop for p in (my players)
	      do (output-object-to-ml p))))
	  

(my-defun game 'object-to-ml :around ()
   (if (my game-over)
     (<p "Game over.")
     (call-next-method)))

(defun current-web-controller (controller)
  (and (web-state-p controller)
       (eql *webapp-session* (web-state-session controller))))

(my-defun web-state 'object-to-ml ()
  (<div :class "game-state"
	(<p :class "close-game" 
	    (html-action-link "Close game."
	      (without-ml-output
		(setf (my resigned) t)
		(deletef me (session-var (my session) 'game-states)))))

	(output-object-to-ml (my game-state))
	
	(when (my waiting-for-input)
	  (<div :class "moves"
		(loop for m in (my waiting-for-input)
		      do 
		      (output-object-to-ml m))))
	(<div :class "messages"
	      (<h2 "Messages")
	      (output-raw-ml
	       (my announcements))
	      (without-ml-output (setf (my announcements) (tpd2.io:with-sendbuf ())))
	      (cond 
		((its game-over (my game-state))
		 (loop for controller in (mapcar 'player-controller (its players (my game-state))) do
		       (unless (current-web-controller controller)
			 (let-current-values (controller)
			   (html-action-link "Play again"
			     (without-ml-output
			       (typecase controller
				 (web-state (handle-challenge (game-name (my game-state)) (session-id (web-state-session controller))))
				 (t (launch-game (game-name (my game-state)) (list (make-web-state :session (webapp-session)) controller)))
				 )))))))
		 (t
		 (loop for controller in (mapcar 'player-controller (its players (my game-state))) do
		       (unless (current-web-controller controller)
			 (let-current-values (controller)
			   (html-action-form (with-ml-output "Talk to " (player-controller-name controller) " ") 
			       (text)
			     (player-controller-message controller *webapp-session* text)
			     (values))))))))))

(defpage "/" ()
  (standard-page ("start")))

	    
(my-defun player 'object-to-ml ()
  (<div :class "player"
	(<h3 (my name) (when (my waiting-for-input)
	  (<span :class "turn" "'s turn")))))

(defmethod player-controller-message ((controller web-state) sender message)
  (web-state-add-announcement controller
			      (<p :class "message" (<span :class "sender" (session-username sender))
				  " " message)))



#+never
(progn
  (defgamepages)

  (let ((socket (tpd2.io:make-con-listen :port 8888)))
    (tpd2.io:launch-io 'tpd2.io:accept-forever socket 'tpd2.http::http-serve))

  (sb-thread:make-thread (lambda() (tpd2.io:event-loop)) :name "EVENT-LOOP"))