;; a load of handy macros to use around the place
;; the base-* packages are meant to be 'used' so that 
;; there is no need to write the package name.

(in-package :base-macros)


;; This macro makes it very simple to create functions
;; where the args passed in are cached and used to 
;; evaluate whether the body should be eval'd

;; [TODO] This won't handle complex argument lists well. 
;;        Probably not something I care about yet, but 
;;        it'll bite me another day for sure.

(defmacro defmemo (name (&rest args) &body body)
  "This creates a function called 'name' which when called
   will only evalute if the values of the arguments passed in
   are different from the values passed to the arguements the 
   previous call.
   For example:
    CEPL-EXAMPLES> (base-macros:defmemo thing (x) (print 'yay))
     THING
    CEPL-EXAMPLES> (thing 5)
     YAY 
     5
    CEPL-EXAMPLES> (thing 5)
     NIL
    CEPL-EXAMPLES> (thing 3)
     YAY 
     3
   This is used in cepl-gl so that you can call bind-vao any 
   number of times and it will only eval if the vao to be bound
   is different (otherwise there is no need). This gives a speed
   boost as the cost of rebinding the vao over and over is 
   replaced with a simple if.

    (defmemo memo-bind-buffer (target buffer-id) 
      (gl:bind-buffer target buffer-id))

    (LET ((#:CACHE874 NIL) (#:CACHE875 NIL))
      (DEFUN MEMO-BIND-BUFFER (TARGET BUFFER-ID)
        (UNLESS (AND (EQ TARGET #:CACHE874) 
                     (EQ BUFFER-ID #:CACHE875))
          (gl:BIND-BUFFER TARGET BUFFER-ID)
          (SETF #:CACHE874 TARGET)
          (SETF #:CACHE875 BUFFER-ID))))"
  (let ((sym-args (loop for arg in args
                     collect (gensym "CACHE"))))
    `(let ,(loop for sym-arg in sym-args
                collect (list sym-arg nil))
       (defun ,name ,args
         (unless (and ,@(loop for arg in args
                             for sym-arg in sym-args
                             collect (list `eq arg sym-arg)))
           ,@body
           ,@(loop for arg in args
                             for sym-arg in sym-args
                             collect (list `setf sym-arg arg)))))))


;;;--------------------------------------------------------------

(defmacro continuable (&body body)
  "Helper macro that we can use to allow us to continue from an
   error. Remember to hit C in slime or pick the restart so 
   errors don't kill the app."
  `(restart-case 
       (progn ,@body)
     (continue () :report "Continue")))

;;;--------------------------------------------------------------
