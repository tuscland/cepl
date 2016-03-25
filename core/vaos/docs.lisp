(in-package :cepl.vaos)

(docs:define-docs
  (defun bind-vao
      "
Bind the vao to the gl context. Remember to unbind when finshed.

Usually you will not need to interact with the vao directly as you can simply
use a buffer-stream and let map-g handle when it should be bound and unbound.
")

  (defun unbind-vao
      "
Un-bind the vao from the gl context.

Usually you will not need to interact with the vao directly as you can simply
use a buffer-stream and let map-g handle when it should be bound and unbound.
")

  (defmacro with-vao-bound
            "
Binds the vao to the gl context and guarentees it will be unbound after the
body scope.

Usually you will not need to interact with the vao directly as you can simply
use a buffer-stream and let map-g handle when it should be bound and unbound.
"))
