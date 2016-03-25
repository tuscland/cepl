(in-package :cepl.textures)

;;{TODO} While I see why I started abstracting this using classes
;;       We cannot extend core functionality of gl, thus uses
;;       extensible constructs is optimizing for a case that can
;;       never happen. We should go for structs, ubyte and macros
;;       to hide the ugly, optimize for helping the compiler

;;------------------------------------------------------------

(defvar *immutable-available* t)
(defvar *cube-face-order* '(:texture-cube-map-positive-x
                            :texture-cube-map-negative-x
                            :texture-cube-map-positive-y
                            :texture-cube-map-negative-y
                            :texture-cube-map-positive-z
                            :texture-cube-map-negative-z))

(defun check-immutable-feature ()
  (unless (has-feature "GL_ARB_texture_storage")
    (setf *immutable-available* nil)))

(push #'check-immutable-feature *on-context*)

;;------------------------------------------------------------

(defun texref (texture &key (mipmap-level 0) (layer 0) (cube-face 0))
  (when (and (> cube-face 0) (not (slot-value texture 'cubes)))
    (error "Cannot get the cube-face from a texture that wasnt made with :cubes t:~%~a" texture))
  (if (eq (slot-value texture 'texture-type) :texture-buffer)
      (if (> (+ mipmap-level layer cube-face) 0)
          (error "Texture index out of range")
          (slot-value texture 'backing-array))
      (if (valid-index-p texture mipmap-level layer cube-face)
          (%make-gpu-array-t
	   :texture texture
	   :texture-type (texture-type texture)
	   :level-num mipmap-level
	   :layer-num layer
	   :face-num cube-face
	   :dimensions (dimensions-at-mipmap-level
			texture mipmap-level)
	   :internal-format (internal-format texture))
          (error "Texture index out of range"))))

(defun valid-index-p (texture mipmap-level layer cube-face)
  (with-slots (mipmap-levels layer-count cubes)
      texture
    (and (< mipmap-level mipmap-levels)
         (< layer layer-count)
         (if cubes
             (<= cube-face 6)
             (eql 0 cube-face)))))

;;------------------------------------------------------------

(defun generate-mipmaps (texture)
  (let ((type (slot-value texture 'texture-type)))
    (with-texture-bound (texture)
      (gl:generate-mipmap type))))

(defun error-on-invalid-upload-formats (target internal-format pixel-format pixel-type)
  (unless (and internal-format pixel-type pixel-format)
    (error "Could not establish all the required formats for the pixel transfer"))
  (when (eq target :texture-buffer)
    (error "You should not have reached this function as buffer backed textures have buffer-gpu-arrays as their backing stores"))
  (when (and (find internal-format '(:depth-component :depth-component16
                                     :depth-component24 :depth-component32f))
             (not (find target '(:texture_2d :proxy_texture_2d
                                 :texture_rectangle
                                 :proxy_texture_rectangle))))
    (error "Texture type is ~a. Cannot populate with ~a"
           target internal-format))
  (when (and (eq pixel-format :depth-component)
             (not (find internal-format
                        '(:depth-component :depth-component16
                          :depth-component24 :depth-component32f))))
    (error "Pixel data is a depth format however the texture is not"))
  (when (and (not (eq pixel-format :depth-component))
             (find internal-format
                   '(:depth-component :depth-component16
                     :depth-component24 :depth-component32f)))
    (error "Pixel data is a depth format however the texture is not"))
  t)

(defun upload-c-array-to-gpu-array-t (gpu-array c-array &optional format type)
  ;; if no format or type
  (when (or (and format (not type)) (and type (not format)))
    (error "cannot only specify either format or type, must be both or neither"))
  (let* ((element-pf (lisp-type->pixel-format c-array))
         (compiled-pf (compile-pixel-format element-pf))
         (pix-format (or format (first compiled-pf)))
         (pix-type (or type (second compiled-pf))))
    (with-gpu-array-t gpu-array
      (error-on-invalid-upload-formats texture-type internal-format pix-format
				       pix-type)
      (unless (equal (dimensions c-array) dimensions)
	(error "dimensions of c-array and gpu-array must match~%c-array:~a gpu-array:~a" (dimensions c-array) dimensions))
      (with-texture-bound ((gpu-array-t-texture gpu-array))
	(%upload-tex texture texture-type level-num (dimensions c-array)
		     layer-num face-num pix-format pix-type (pointer c-array)))))
  gpu-array)

;; [TODO] add offsets
(defgeneric %upload-tex (tex tex-type level-num dimensions layer-num face-num
                         pix-format pix-type pointer))

(defmethod %upload-tex ((tex mutable-texture) tex-type level-num dimensions
                        layer-num face-num pix-format pix-type pointer)
  (case tex-type
    (:texture-1d (gl:tex-image-1d
		  tex-type level-num (gpu-array-t-internal-format tex)
		  (first dimensions) 0 pix-format pix-type
		  pointer))
    (:texture-2d (gl:tex-image-2d
		  tex-type level-num (gpu-array-t-internal-format tex)
		  (first dimensions) (second dimensions) 0
		  pix-format pix-type pointer))
    (:texture-3d (gl:tex-image-3d
		  tex-type level-num (gpu-array-t-internal-format tex)
		  (first dimensions) (second dimensions)
		  (third dimensions) 0 pix-format pix-type
		  pointer))
    (:texture-1d-array (gl:tex-image-2d
			tex-type level-num
			(gpu-array-t-internal-format tex)
			(first dimensions) layer-num 0
			pix-format pix-type pointer))
    (:texture-2d-array (gl:tex-image-3d
			tex-type level-num
			(gpu-array-t-internal-format tex)
			(first dimensions) (second dimensions)
			layer-num 0 pix-format pix-type pointer))
    (:texture-cube-map (gl:tex-image-2d
			(nth face-num *cube-face-order*)
			level-num (gpu-array-t-internal-format tex)
			(first dimensions) (second dimensions) 0
			pix-format pix-type pointer))
    (t (error "not currently supported for upload: ~a" tex-type))))


(defmethod %upload-tex ((tex immutable-texture) tex-type level-num dimensions
                        layer-num face-num pix-format pix-type pointer)
  (case tex-type
    (:texture-1d (gl:tex-sub-image-1d tex-type level-num 0 (first dimensions)
                                      pix-format pix-type pointer))
    (:texture-2d (gl:tex-sub-image-2d tex-type level-num 0 0
                                      (first dimensions) (second dimensions)
                                      pix-format pix-type pointer))
    (:texture-1d-array (gl:tex-sub-image-2d tex-type level-num 0 0
                                            (first dimensions) layer-num
                                            pix-format pix-type pointer))
    (:texture-3d (gl:tex-sub-image-3d tex-type level-num 0 0 0
                                      (first dimensions) (second dimensions)
                                      (third dimensions) pix-format pix-type
                                      pointer))
    (:texture-2d-array (gl:tex-sub-image-3d tex-type level-num 0 0 0
                                            (first dimensions)
                                            (second dimensions) layer-num
                                            pix-format pix-type pointer))
    (:texture-cube-map (gl:tex-sub-image-2d (nth face-num *cube-face-order*)
                                            level-num 0 0 (first dimensions)
                                            (second dimensions) pix-format
                                            pix-type pointer))
    (t (error "not currently supported for upload: ~a" tex-type))))

(defun upload-from-buffer-to-gpu-array-t (&rest args)
  (declare (ignore args))
  (error "upload-from-buffer-to-gpu-array-t is not implemented yet"))

;;------------------------------------------------------------

(defvar *mipmap-max-levels* 20)
(defvar *valid-texture-storage-options*
  ;; mipmap layers cubes dimensions multisample buffer rectangle
  '(((t nil nil 1 nil nil nil) :texture-1d)
    ((t nil nil 2 nil nil nil) :texture-2d)
    ((t nil nil 3 nil nil nil) :texture-3d)
    ((t t nil 1 nil nil nil) :texture-1d-array)
    ((t t nil 2 nil nil nil) :texture-2d-array)
    ((t nil t 2 nil nil nil) :texture-cube-map)
    ((t t t 2 nil nil nil) :texture-cube-map-array)
    ((nil nil nil 2 nil nil t) :texture-rectangle)
    ((nil nil nil 1 nil t nil) :texture-buffer)
    ((nil nil nil 2 nil t nil) :texture-buffer)
    ((nil nil nil 3 nil t nil) :texture-buffer)
    ((nil nil nil 2 t nil nil) :texture-2d-multisample)
    ((nil t nil 2 t nil nil) :texture-2d-multisample-array)))

;;------------------------------------------------------------

(defun gen-texture ()
  (first (gl:gen-textures 1)))

(defun po2p (x) (eql 0 (logand x (- x 1))))

(defun dimensions-at-mipmap-level (texture level)
  (if (= level 0)
      (base-dimensions texture)
      (let ((div (* 2 (1+ level))))
        (loop for i in (base-dimensions texture) collecting
             (floor (/ i div))))))

;;------------------------------------------------------------

(defun establish-texture-type (dimensions mipmap layers cubes po2 multisample
                               buffer rectangle)
  (declare (ignore po2))
  (cadr (assoc (list mipmap layers cubes dimensions multisample buffer rectangle)
               *valid-texture-storage-options*
               :test #'(lambda (a b)
                         (destructuring-bind
                               (a1 a2 a3 a4 a5 a6 a7 b1 b2 b3 b4 b5 b6 b7)
                             (append a b)
                           (and (if b1 t (not a1)) (if b2 t (not a2))
                                (if b3 t (not a3)) (eql b4 a4)
                                (eql b5 a5) (eql b6 a6) (eql b7 a7)))))))

;;------------------------------------------------------------
;; {TODO} Texture sizes have a limit based on the GL
;;        implementation. For 1D and 2D textures (and any texture types that
;;        use similar dimensionality, like cubemaps) the max size of either
;;        dimension is GL_MAX_TEXTURE_SIZE​. For array textures, the maximum
;;        array length is GL_MAX_ARRAY_TEXTURE_LAYERS​. For 3D textures, no
;;        dimension can be greater than GL_MAX_3D_TEXTURE_SIZE​ in size.


;; [TODO] how does mipmap-max affect this
;; [TODO] what is the max layercount?
;; [TODO] should fail on layer-count=0?
(defun %texture-dimensions (initial-contents dimensions)
  (if initial-contents
      (if dimensions
          (error "Cannot specify dimensions and initial-contents")
          (dimensions initial-contents))
      (if dimensions dimensions (error "must specify dimensions if no initial-contents provided"))))

(defun make-texture-from-id (gl-object &key base-dimensions texture-type
                                         internal-format sampler-type
                                         mipmap-levels layer-count cubes
                                         allocated)
  (make-instance 'gl-texture
                 :texture-id gl-object
                 :base-dimensions base-dimensions
                 :texture-type texture-type
                 :internal-format internal-format
                 :sampler-type sampler-type
                 :mipmap-levels mipmap-levels
                 :layer-count layer-count
                 :cubes cubes
                 :allocated allocated))


(defun make-texture (initial-contents
                     &key dimensions element-type (mipmap nil)
                       (layer-count 1) (cubes nil) (rectangle nil)
                       (multisample nil) (immutable t) (buffer-storage nil)
                       lod-bias min-lod max-lod minify-filter magnify-filter
                       wrap compare (generate-mipmaps t))
  (let ((element-type (expand-gl-type-name element-type))
	(internal-format (calc-internal-format element-type initial-contents)))
    (cond
      ;; ms
      (multisample (error "cepl: Multisample textures are not supported"))
      ;; cube textures
      ((and initial-contents cubes)
       (%make-cube-texture dimensions mipmap layer-count cubes buffer-storage
                           rectangle multisample immutable initial-contents
                           internal-format lod-bias min-lod max-lod
                           minify-filter magnify-filter wrap compare
                           generate-mipmaps))
      ;; initialize content needs to be turned into c-array
      ((and initial-contents (typep initial-contents 'uploadable-lisp-seq))
       (%make-texture-with-lisp-data dimensions mipmap layer-count cubes
                                     buffer-storage rectangle multisample
                                     immutable initial-contents lod-bias min-lod
                                     max-lod minify-filter magnify-filter wrap
                                     compare generate-mipmaps element-type
				     internal-format))
      ;; buffer backed - note that by now if there were intitial contents, they
      ;;                 are now a c-array
      (buffer-storage
       (%make-buffer-texture (%texture-dimensions initial-contents dimensions)
                             internal-format mipmap layer-count cubes
                             rectangle multisample immutable initial-contents
                             lod-bias min-lod max-lod minify-filter
                             magnify-filter wrap compare))
      ;; all other cases
      (t (%make-texture dimensions mipmap layer-count cubes buffer-storage
                        rectangle multisample immutable initial-contents
                        internal-format lod-bias min-lod max-lod
                        minify-filter magnify-filter wrap compare
                        generate-mipmaps)))))

;;-   -   -   -   -   -   -   -   -   -   -   -   -   -   -   -

(defun calc-dimensions (internal-format dimensions cube-tex)
  (declare (ignore internal-format dimensions cube-tex)))

;; other
;; (listify dimensions)
;;cube
;; (let* ((target-dim (or dimensions (dimensions (first initial-contents))))
;;        (dim (if (every (lambda (_) (equal target-dim (dimensions _)))
;;                        initial-contents)
;;                 target-dim
;;                 (error "Conflicting dimensions of c-arrays passed to make-texture with :cube t:~%~a"
;;                        initial-contents)))))

;;-   -   -   -   -   -   -   -   -   -   -   -   -   -   -   -

(defun calc-internal-format (element-type initial-contents)
  (cond
    ;; need to infer the type
    ((null element-type)
     (%calc-internal-format-without-declared-format initial-contents))
    ;; need to ensure nothing conflicts with declaration
    ((internal-formatp element-type)
     (%calc-internal-format-with-declared-format element-type
                                                 element-type
                                                 initial-contents))
    ;; need to ensure nothing conflicts with declaration
    ((pixel-format-p element-type)
     (%calc-internal-format-with-pixel-format element-type
                                              initial-contents))
    ;;
    (t (%calc-internal-format-with-lisp-type element-type
                                             initial-contents))))

;;-   -   -   -   -   -   -   -   -   -   -   -   -   -   -   -

(defun %calc-internal-format-without-declared-format (initial-contents)
  ;; The user didnt declare an element-type so try and infer one
  (typecase initial-contents
    (null (error 'make-tex-no-content-no-type))
    (c-array (lisp-type->internal-format
              (element-type initial-contents)))
    (uploadable-lisp-seq (lisp-type->internal-format
			  (cepl.c-arrays::lisp->gl-type
			   (cepl.c-arrays::scan-for-type initial-contents))))))

;;-   -   -   -   -   -   -   -   -   -   -   -   -   -   -   -

(defun %calc-internal-format-with-declared-format
    (element-type internal-format initial-contents)
  ;; Here the users declared the internal format in :element-type so
  ;; we need to make sure that no other arguments conflict with this
  (typecase initial-contents
    (null internal-format)
    (c-array (if (equal (lisp-type->internal-format
                         (element-type initial-contents))
                        internal-format)
                 internal-format
                 (error 'make-tex-array-not-match-type
                        :element-type element-type
                        :internal-format internal-format
                        :array-type (element-type initial-contents))))
    (uploadable-lisp-seq internal-format) ;; we cant infer all types so we
    ;; have to trust and then the
    ;; c-array code handle it
    (t (error 'make-tex-array-not-match-type2
              :element-type element-type
              :initial-contents initial-contents))))

;;-   -   -   -   -   -   -   -   -   -   -   -   -   -   -   -

(defun %calc-internal-format-with-pixel-format (pixel-format initial-contents)
  "Convert the pixel-format to an internal format and delegate to
   %calc-internal-format"
  (%calc-internal-format-with-declared-format
   pixel-format
   (pixel-format->internal-format pixel-format)
   initial-contents))

(defun %calc-internal-format-with-lisp-type (element-type initial-contents)
  "Convert the lisp type to an internal format and delegate to
   %calc-internal-format"
  (%calc-internal-format-with-declared-format
   element-type
   (lisp-type->internal-format element-type)
   initial-contents))

;;-   -   -   -   -   -   -   -   -   -   -   -   -   -   -   -

(defun %make-texture-with-lisp-data
    (dimensions mipmap layer-count cubes buffer-storage
     rectangle multisample immutable initial-contents
     lod-bias min-lod max-lod minify-filter
     magnify-filter wrap compare generate-mipmaps
     element-type internal-format)
  (declare (ignore element-type))
  (let ((element-type (internal-format->lisp-type internal-format)))
    (with-c-array (tmp (make-c-array initial-contents :dimensions dimensions
				     :element-type element-type))
      (make-texture tmp :mipmap mipmap
		    :layer-count layer-count :cubes cubes :rectangle rectangle
		    :multisample multisample :immutable immutable
		    :buffer-storage buffer-storage
		    :generate-mipmaps generate-mipmaps :lod-bias lod-bias
		    :min-lod min-lod :max-lod max-lod
		    :minify-filter minify-filter :magnify-filter magnify-filter
		    :wrap wrap :compare compare))))

(defun %make-cube-texture (dimensions mipmap layer-count cubes buffer-storage
                           rectangle multisample immutable initial-contents
                           internal-format lod-bias min-lod max-lod minify-filter
                           magnify-filter wrap compare generate-mipmaps)
  (assert (= 6 (length initial-contents)))
  (let* ((target-dim (or dimensions (dimensions (first initial-contents))))
         (dim (if (every (lambda (_) (equal target-dim (dimensions _)))
                         initial-contents)
                  target-dim
                  (error "Conflicting dimensions of c-arrays passed to make-texture with :cube t:~%~a"
                         initial-contents)))
         (result (%make-texture dim mipmap layer-count cubes buffer-storage
                                rectangle multisample immutable nil
                                internal-format lod-bias min-lod max-lod
                                minify-filter magnify-filter wrap compare
                                generate-mipmaps)))
    (loop :for data :in initial-contents :for i :from 0 :do
       (push-g data (texref result :cube-face i)))
    result))

(defun %make-texture (dimensions mipmap layer-count cubes buffer-storage
                      rectangle multisample immutable initial-contents
                      internal-format lod-bias min-lod max-lod minify-filter
                      magnify-filter wrap compare generate-mipmaps)
  (let* ((dimensions (listify dimensions))
	 (dimensions (%texture-dimensions initial-contents dimensions)))
    ;; check for power of two - handle or warn
    (let* ((pixel-format (when initial-contents
                           (lisp-type->pixel-format initial-contents)))
           (texture-type (establish-texture-type
                          (if (listp dimensions) (length dimensions) 1)
                          (not (null mipmap)) (> layer-count 1) cubes
                          (every #'po2p dimensions) multisample
                          buffer-storage rectangle))
           (mipmap-levels (let ((max-levels (floor (log (apply #'max dimensions) 2))))
                            (if (typep mipmap 'integer)
                                (if (<= mipmap max-levels)
                                    mipmap
                                    (error "Invalid number of mipmap levels specified (~a) for dimensions ~a"
                                           mipmap dimensions))
                                (if mipmap
                                    max-levels
                                    1)))))
      (if texture-type
          (if (and cubes (not (apply #'= dimensions)))
              (error "Cube textures must be square")
              (let ((texture (make-instance
                              (if (and immutable *immutable-available*)
                                  'immutable-texture
                                  'mutable-texture)
                              :texture-id (gen-texture)
                              :base-dimensions dimensions
                              :texture-type texture-type
                              :mipmap-levels mipmap-levels
                              :layer-count layer-count
                              :cubes cubes
                              :internal-format internal-format
                              :sampler-type (cepl.samplers::calc-sampler-type
					     texture-type
					     internal-format))))
                (with-texture-bound (texture)
                  (allocate-texture texture)
                  (when initial-contents
                    (destructuring-bind (pformat ptype)
                        (compile-pixel-format pixel-format)
                      (upload-c-array-to-gpu-array-t
                       (texref texture) initial-contents
                       pformat ptype)))
                  (when (and generate-mipmaps (> mipmap-levels 1))
                    (generate-mipmaps texture)))
                (when lod-bias
                  (setf (cepl.samplers:lod-bias texture) lod-bias))
                (when min-lod
                  (setf (cepl.samplers:min-lod texture) min-lod))
                (when max-lod
                  (setf (cepl.samplers:max-lod texture) max-lod))
                (when minify-filter
                  (setf (cepl.samplers:minify-filter texture) minify-filter))
                (when magnify-filter
                  (setf (cepl.samplers:magnify-filter texture) magnify-filter))
                (when wrap
                  (setf (cepl.samplers:wrap texture) wrap))
                (when compare
                  (setf (cepl.samplers:compare texture) compare))
                texture))
          (error "This combination of texture features is invalid")))))

;; (when (gpu-array-p initial-contents)
;;     (error "Cannot currently make a buffer-backed texture with an existing buffer-backed gpu-array"))
;;   (when (typep initial-contents 'gpu-array-t)
;;     (error "Cannot make a buffer-backed texture with a texture-backed gpu-array"))

(defun %make-buffer-texture (dimensions internal-format mipmap layer-count cubes
                             rectangle multisample immutable initial-contents
                             lod-bias min-lod max-lod minify-filter
                             magnify-filter wrap compare)
  (declare (ignore immutable))
  (let* ((dimensions (listify dimensions))
         (element-type (if initial-contents
                           (element-type initial-contents)
                           (internal-format->lisp-type internal-format)))
         (texture-type (establish-texture-type
                        (length dimensions)
                        nil nil nil (every #'po2p dimensions) nil t nil)))
    ;; validation
    (assert-valid-args-for-buffer-backend-texture
     internal-format cubes rectangle multisample mipmap layer-count
     lod-bias min-lod max-lod minify-filter magnify-filter wrap compare
     texture-type)
    ;; creation
    (let* ((array (if initial-contents
                      (make-gpu-array initial-contents)
                      (make-gpu-array nil :dimensions dimensions
                                      :element-type element-type)))
           (new-tex (make-instance
                     'buffer-texture
                     :texture-id (gen-texture)
                     :base-dimensions dimensions
                     :texture-type texture-type
                     :mipmap-levels 1
                     :layer-count 1
                     :cubes nil
                     :internal-format internal-format
                     :sampler-type (cepl.samplers::calc-sampler-type
                                    texture-type internal-format)
                     :backing-array array
                     :owns-array t)))
      ;; upload
      (with-texture-bound (new-tex)
        (%gl::tex-buffer :texture-buffer internal-format
                         (gpu-buffer-id
			  (cepl.gpu-arrays::gpu-array-buffer array)))
        (setf (slot-value new-tex 'allocated) t)
        new-tex))))

(defun assert-valid-args-for-buffer-backend-texture
    (internal-format cubes rectangle multisample mipmap layer-count
     lod-bias min-lod max-lod minify-filter magnify-filter wrap compare
     texture-type)
  (when (or mipmap (not (= layer-count 1)) cubes rectangle multisample)
    (error 'buffer-backed-texture-invalid-args))
  (when (or lod-bias min-lod max-lod minify-filter magnify-filter wrap compare)
    (error 'buffer-backed-texture-invalid-samplers))
  (unless (valid-internal-format-for-buffer-backed-texturep internal-format)
    (error 'buffer-backed-texture-invalid-internal-format
           :type-name internal-format))
  (unless (eq texture-type :texture-buffer)
    (error 'buffer-backed-texture-establish-internal-format
           :type-name texture-type)))

(defun %find-tex-internal-format (element-format)
  (if (pixel-format-p element-format)
      (pixel-format->internal-format element-format)
      (let ((pfo (lisp-type->pixel-format element-format)))
        (if pfo
            (pixel-format->internal-format pfo)
            element-format))))

(defgeneric allocate-texture (texture))

(defmethod allocate-texture ((texture buffer-texture))
  (error "This function should not have been called with a buffer backed texture"))

(defmethod allocate-texture ((texture mutable-texture))
  (gl:tex-parameter (gpu-array-t-texture-type texture) :texture-base-level 0)
  (gl:tex-parameter (gpu-array-t-texture-type texture) :texture-max-level
                    (1- (slot-value texture 'mipmap-levels)))
  (setf (slot-value texture 'allocated) t))

(defmethod allocate-texture ((texture immutable-texture))
  (if (allocatedp texture)
      (error "Attempting to reallocate a previously allocated texture")
      (let ((base-dimensions (base-dimensions texture))
            (texture-type (slot-value texture 'texture-type)))
        (case texture-type
          ((:texture-1d :proxy-texture-1d)
           (tex-storage-1d texture-type
                           (slot-value texture 'mipmap-levels)
                           (slot-value texture 'internal-format)
                           (first base-dimensions)))
          ((:texture-2d :proxy-texture-2d :texture-1d-array :texture-rectangle
                        :proxy-texture-rectangle :texture-cube-map
                        :proxy-texture-cube-map :proxy-texture-1d-array)
           (tex-storage-2d texture-type
                           (slot-value texture 'mipmap-levels)
                           (slot-value texture 'internal-format)
                           (first base-dimensions)
                           (or (second base-dimensions) 0)))
          ((:texture-3d :proxy-texture-3d :texture-2d-array :texture-cube-array
                        :proxy-texture-cube-array :proxy-texture-2d-array)
           (tex-storage-3d texture-type
                           (slot-value texture 'mipmap-levels)
                           (slot-value texture 'internal-format)
                           (first base-dimensions)
                           (or (second base-dimensions) 0)
                           (or (third base-dimensions) 0))))
        (setf (slot-value texture 'allocated) t))))

(defun tex-storage-1d (target levels internal-format width)
  (%gl:tex-storage-1d target levels (gl::internal-format->int internal-format)
                      width))

(defun tex-storage-2d (target levels internal-format width height)
  (%gl:tex-storage-2d target levels (gl::internal-format->int internal-format)
                      width height))

(defun tex-storage-3d (target levels internal-format width height depth)
  (%gl:tex-storage-3d target levels (gl::internal-format->int internal-format)
                      width height depth))

;;------------------------------------------------------------

(defmethod push-g ((object c-array) (destination gl-texture))
  (push-g object (texref destination)))
(defmethod push-g ((object list) (destination gl-texture))
  (push-g object (texref destination)))
(defmethod push-g ((object array) (destination gl-texture))
  (push-g object (texref destination)))

(defmethod push-g ((object list) (destination gpu-array-t))
  (with-c-array (c-a (make-c-array object
                                   :dimensions (dimensions destination)
                                   :element-type (internal-format->pixel-format
                                                  (gpu-array-t-internal-format destination))))
    (push-g c-a destination)))

(defmethod push-g ((object array) (destination gpu-array-t))
  (with-c-array (c-a (make-c-array object
                                   :dimensions (dimensions destination)
                                   :element-type (internal-format->pixel-format
                                                  (gpu-array-t-internal-format destination))))
    (push-g c-a destination)))

;; [TODO] This feels like could create non-optimal solutions
;;        So prehaps this should look at texture format, and
;;        find the most similar compatible format, with worst
;;        case being just do what we do below
(defmethod push-g ((object c-array) (destination gpu-array-t))
  (destructuring-bind (pformat ptype)
      (compile-pixel-format (lisp-type->pixel-format object))
    (upload-c-array-to-gpu-array-t destination object
                                  pformat ptype)))

(defmethod pull-g ((object gl-texture))
  (pull-g (texref object)))

;; [TODO] implement gl-fill and fill arguments
;; [TODO] Does not respect GL_PIXEL_PACK/UNPACK_BUFFER
(defmethod pull1-g ((object gpu-array-t))
  (with-gpu-array-t object
    (let* ((p-format (internal-format->pixel-format
                      (gpu-array-t-internal-format object)))
           (c-array (make-c-array nil :dimensions (dimensions object)
                                  :element-type p-format)))
      (destructuring-bind (format type) (compile-pixel-format p-format)
        (with-texture-bound (texture)
          (%gl:get-tex-image (foreign-enum-value '%gl:enum texture-type)
			     (coerce level-num 'real)
			     format
			     type
                             (pointer c-array))))
      c-array)))

(defmethod pull1-g ((object gl-texture))
  (pull1-g (texref object)))

;; [TODO] With-c-array is wrong
(defmethod pull-g ((object gpu-array-t))
  (with-c-array (c-array (pull1-g object))
    (pull1-g c-array)))



(defun active-texture-num (num)
  (gl:active-texture (+ #x84C0 num)))

;; {TODO}
;; copy data (from frame-buffer to texture image) - leave for now
;; copy from buffer to texture glCopyTexSubImage2D
;; set texture params
;; get texture params
;; texture views
;; generate-mipmaps
;; texsubimage*d - pushing data
;; glPixelStore — set pixel storage modes
