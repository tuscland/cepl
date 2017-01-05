(in-package :cepl.context)

(defclass gl-context ()
  ((cache :initform (make-hash-table))
   (handle :initarg :handle :reader handle)
   (window :initarg :window :reader window)
   (fbo :initarg :window :reader context-fbo)))

(defconstant +unknown-id+ -1)

;; Caching details
;; ---------------
;; IDs: Unknown = -1
(defclass cepl-context ()
  ((uninitialized-resources :initform nil)
   (gl-context :initform nil)

   (array-buffer-binding-id :initform +unknown-id+
                            :type (signed-byte 32))
   (element-array-buffer-binding-id :initform +unknown-id+
                                    :type (signed-byte 32))
   (vao-binding-id :initform +unknown-id+
                   :type vao-id)
   (read-fbo-binding-id :initform +unknown-id+
                        :type (signed-byte 32))
   (draw-fbo-binding-id :initform +unknown-id+
                        :type (signed-byte 32))

   (gpu-buffers :initform (make-array 0 :element-type 'gpu-buffer
                                      :initial-element +null-gpu-buffer+
                                      :adjustable t
                                      :fill-pointer 0))
   (fbos :initform (make-array 0 :element-type 'fbo
                               :initial-element +null-fbo+
                               :adjustable t
                               :fill-pointer 0))))

(defvar *cepl-context*
  (make-instance 'cepl-context))

;;----------------------------------------------------------------------

(defun register-gpu-buffer (cepl-context gpu-buffer)
  (with-slots (gpu-buffers) cepl-context
    (let ((id (gpu-buffer-id gpu-buffer)))
      (ensure-vec-index gpu-buffers id +null-gpu-buffer+)
      (setf (aref gpu-buffers id) gpu-buffer))))

(defun register-fbo (cepl-context fbo)
  (with-slots (fbos) cepl-context
    (let ((id (%fbo-id fbo)))
      (ensure-vec-index fbos id +null-fbo+)
      (setf (aref fbos id) fbo))))

;;----------------------------------------------------------------------

(defun read-fbo-bound (cepl-context)
  (with-slots (gl-context fbos read-fbo-binding-id) cepl-context
    (let* ((id (if (= read-fbo-binding-id +unknown-id+)
                   (setf read-fbo-binding-id
                         (read-framebuffer-binding gl-context))
                   read-fbo-binding-id))
           (fbo (when (>= id 0) (aref fbos id))))
      (assert (not (eq fbo +null-fbo+)))
      fbo)))

(defun (setf read-fbo-bound) (fbo cepl-context)
  (with-slots (gl-context fbos read-fbo-binding-id) cepl-context
    (let ((id (if fbo
                  (%fbo-id fbo)
                  0)))
      (when (/= id read-fbo-binding-id)
        (setf (read-framebuffer-binding gl-context) id
              read-fbo-binding-id id))
      fbo)))

(defun draw-fbo-bound (cepl-context)
  (with-slots (gl-context fbos draw-fbo-binding-id) cepl-context
    (let* ((id (if (= draw-fbo-binding-id +unknown-id+)
                   (setf draw-fbo-binding-id
                         (draw-framebuffer-binding gl-context))
                   draw-fbo-binding-id))
           (fbo (when (>= id 0) (aref fbos id))))
      (assert (not (eq fbo +null-fbo+)))
      fbo)))

(defun (setf draw-fbo-bound) (fbo cepl-context)
  (with-slots (gl-context fbos draw-fbo-binding-id) cepl-context
    (let ((id (if fbo
                  (%fbo-id fbo)
                  0)))
      (when (/= id draw-fbo-binding-id)
        (setf (draw-framebuffer-binding gl-context) id
              draw-fbo-binding-id id))
      fbo)))

(defun fbo-bound (cepl-context)
  (cons (read-fbo-bound cepl-context)
        (draw-fbo-bound cepl-context)))

(defun (setf fbo-bound) (fbo cepl-context)
  (assert (typep fbo 'fbo))
  (with-slots (gl-context fbos read-fbo-binding-id draw-fbo-binding-id)
      cepl-context
    (let* ((id (if fbo
                   (%fbo-id fbo)
                   0))
           (r-dif (/= id read-fbo-binding-id))
           (d-dif (/= id draw-fbo-binding-id)))
      (cond
        ((and r-dif d-dif) (setf (framebuffer-binding gl-context) id))
        (r-dif (setf (read-framebuffer-binding gl-context) id))
        (d-dif (setf (draw-framebuffer-binding gl-context) id)))
      (setf draw-fbo-binding-id id
            read-fbo-binding-id id)
      fbo)))

;;----------------------------------------------------------------------

(defun buffer-bound (cepl-context target)
  (ecase target
    (:array-buffer (array-buffer-bound cepl-context))
    (:uniform-buffer (element-array-buffer-bound cepl-context))
    (:element-array-buffer (element-array-buffer-bound cepl-context))))

(defun (setf buffer-bound) (value cepl-context target)
  (ecase target
    (:array-buffer (setf (array-buffer-bound cepl-context) value))
    (:uniform-buffer (setf (element-array-buffer-bound cepl-context) value))
    (:element-array-buffer (setf (element-array-buffer-bound cepl-context) value))))

(define-compiler-macro buffer-bound (&whole whole cepl-context target)
  (case target
    (:array-buffer `(array-buffer-bound ,cepl-context))
    (:uniform-buffer `(element-array-buffer-bound ,cepl-context))
    (:element-array-buffer `(element-array-buffer-bound ,cepl-context))
    (otherwise whole)))

(define-compiler-macro (setf buffer-bound)
    (&whole whole value cepl-context target)
  (case target
    (:array-buffer
     `(setf (array-buffer-bound ,cepl-context) ,value))
    (:uniform-buffer
     `(setf (element-array-buffer-bound ,cepl-context) ,value))
    (:element-array-buffer
     `(setf (element-array-buffer-bound ,cepl-context) ,value))
    (otherwise whole)))

;;----------------------------------------------------------------------

(defun array-buffer-bound (cepl-context)
  (with-slots (gl-context gpu-buffers array-buffer-binding-id) cepl-context
    (let* ((id (if (= array-buffer-binding-id +unknown-id+)
                   (setf array-buffer-binding-id
                         (array-buffer-binding gl-context))
                   array-buffer-binding-id))
           (buffer (when (> id 0) (aref gpu-buffers id))))
      (assert (not (eq buffer +null-gpu-buffer+)))
      buffer)))

(defun (setf array-buffer-bound) (gpu-buffer cepl-context)
  (with-slots (gl-context gpu-buffers array-buffer-binding-id) cepl-context
    (let ((id (if gpu-buffer
                  (gpu-buffer-id gpu-buffer)
                  0)))
      (when (/= id array-buffer-binding-id)
        (setf (array-buffer-binding gl-context) id
              array-buffer-binding-id id))
      gpu-buffer)))

;;----------------------------------------------------------------------

(defun element-array-buffer-bound (cepl-context)
  (with-slots (gl-context gpu-buffers element-array-buffer-binding-id)
      cepl-context
    (let* ((id (if (= element-array-buffer-binding-id +unknown-id+)
                   (setf element-array-buffer-binding-id
                         (element-array-buffer-binding gl-context))
                   element-array-buffer-binding-id))
           (buffer (when (> id 0) (aref gpu-buffers id))))
      (assert (not (eq buffer +null-gpu-buffer+)))
      buffer)))

(defun (setf element-array-buffer-bound) (gpu-buffer cepl-context)
  (with-slots (gl-context gpu-buffers element-array-buffer-binding-id)
      cepl-context
    (let ((id (if gpu-buffer
                  (gpu-buffer-id gpu-buffer)
                  0)))
      (when (/= id element-array-buffer-binding-id)
        (setf (element-array-buffer-binding gl-context) id
              element-array-buffer-binding-id id))
      gpu-buffer)))

;;----------------------------------------------------------------------

(defun vao-bound (cepl-context)
  (with-slots (gl-context vao-binding-id) cepl-context
    (if (= vao-binding-id +unknown-id+)
        (setf vao-binding-id (vertex-array-binding gl-context))
        vao-binding-id)))

(defun (setf vao-bound) (vao cepl-context)
  (with-slots (gl-context vao-binding-id) cepl-context
    (when (/= vao-binding-id vao)
      (setf (vertex-array-binding gl-context) vao)
      (setf vao-binding-id vao)))
  vao)

;;----------------------------------------------------------------------
;; we don't cache this as we would also need to cache the ranges, in that
;; case we end up doing so many checks we are kind of defeating the point.
;; Instead we just make sure the transform to cepl objects works

(defun uniform-buffer-bound (cepl-context index &optional offset size)
  (assert (and (null offset) (null size)))
  (with-slots (gl-context gpu-buffers)
      cepl-context
    (let* ((id (uniform-buffer-binding gl-context index))
           (buffer (when (> id 0) (aref gpu-buffers id))))
      (assert (not (eq buffer +null-gpu-buffer+)))
      buffer)))

(defun (setf uniform-buffer-bound)
    (gpu-buffer cepl-context index &optional offset size)
  (with-slots (gl-context gpu-buffers)
      cepl-context
    (if gpu-buffer
        (let ((id (gpu-buffer-id gpu-buffer)))
          (cond
            ((and offset size)
             (setf (uniform-buffer-binding gl-context index offset size) id))
            ((or offset size)
             (error "If you specify one offset or size, you must specify the other"))
            (t (setf (uniform-buffer-binding gl-context index) id))))
        (progn
          (assert (and (null offset) (null size)))
          (setf (uniform-buffer-binding gl-context index) 0)))
    gpu-buffer))

;;----------------------------------------------------------------------

(defun on-gl-context (cepl-context new-gl-context)
  (with-slots (gl-context uninitialized-resources) cepl-context
    (setf gl-context new-gl-context)
    (initialize-all-delayed uninitialized-resources)
    (setf uninitialized-resources nil)))

;;----------------------------------------------------------------------
;; Delayed resource initialization

(defvar *post-context-init* nil)

(defstruct delayed
  (waiting-on nil :type list)
  (thunk (error "delayed must have a constructor thunk")
	 :type function))

(defun delay-initialization (cepl-context init-thunk waiting-on-these-resources)
  (with-slots (uninitialized-resources) cepl-context
    (push (make-delayed :waiting-on waiting-on-these-resources
                        :thunk init-thunk)
          uninitialized-resources))
  t)

(defun initialize-all-delayed (thunks)
  (let ((delayed-further (reduce #'initialize-delayed thunks
				 :initial-value nil)))
    (when delayed-further
      (initialize-all-delayed delayed-further))))


(defun initialize-delayed (delay-again item)
  (let ((still-waiting-on
	 (remove-if #'initialized-p (delayed-waiting-on item))))
    (if still-waiting-on
	(progn
	  (setf (delayed-waiting-on item)
		still-waiting-on)
	  (cons item delay-again))
	(progn
	  (funcall (delayed-thunk item))
	  delay-again))))

(defmacro if-gl-context (init-func-call pre-context-form &optional depends-on)
  (let ((pre (cepl-utils:symb :%pre%)))
    `(let ((,pre ,pre-context-form))
       (if (slot-value *cepl-context* 'gl-context)
	   (let ((,pre ,pre))
	     ,init-func-call)
	   (delay-initialization
            *cepl-context*
            (lambda () ,init-func-call)
            ,depends-on))
       ,pre)))
