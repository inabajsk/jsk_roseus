;; -*- mode: EusLisp; coding: utf-8-unix; -*-

(setq *real* nil) ;; switch for using real camera
(defun init-cr-cap (&optional (real *real*))
  (cond
   (real
    (load (format nil "~A/prog/jvl/app/test-cr-save.l" (unix:getenv "HOME")))
    (test-cr-capture
     :param-prefix (format nil "~A/prog/jvl/app/sr4000/2010-02-16-15-14-42" (unix:getenv "HOME")))
    (defun proc-pcloud ()
      (proc-cr)
      (setq *3dp* (send *cr* :point-cloud))
      )
    )
   (t
    (load (format nil "~A/prog/jvl/app/test-sr-capture.l" (unix:getenv "HOME")))
    (init-cap "many-packs")
    (defun proc-pcloud ()
      (proc-3dpos)
      (setq *3dp* (send *sr* :point-cloud))
      )
    )
   )
  )
(init-cr-cap)

(pushnew (format nil "~A/euslisp/"
                 (read-line (piped-fork "rospack find roseus")))
         *load-path* :test #'equal)
(load "roseus.l")

(setq ros::*compile-message* t) ;; switch for compile
(defun roseus-add-files (pkg type)
 (let (dir dirfile)
   (setq dir (format nil "~A/~A/eus/~A/"
                     (read (piped-fork (format nil "rospack find ~A" pkg)))
                     type pkg))
   (unless (probe-file dir)
     (warning-message 1 (format nil ";; can not find ~A directory for [~A] pac\
kages~%" dir pkg))
     (exit))
   (unless (find-package (string-upcase pkg))
     (make-package (string-upcase pkg)))
   (dolist (file (directory dir))
     (when (and (string= (pathname-type file) "l")
                (not (= #\. (elt (pathname-name file) 0))))
       (setq dirfile (concatenate string dir file))
       (if ros::*compile-message*
           (let* ((fname (format nil "~A" (pathname-name file)))
                  (old-module (find fname *loaded-modules*
                                    :key #'lisp::load-module-file-name :test #'equal)))
             (if old-module (sys::unbinload old-module))
             (let ((pwd (unix::pwd)) lname)
               (unix::chdir (string-right-trim "/" dir))
               (comp:compile-file-if-src-newer file)
               (setq lname (load fname))
               (warning-message 6 ";; loading   ~A~%" lname)
               (unix::chdir pwd)))
         (progn
           (warning-message 6 ";; loading ~A~%" dirfile)
           (load dirfile)))))
   ))

(roseus-add-msgs "roslib")
(roseus-add-msgs "geometry_msgs")
(roseus-add-msgs "sensor_msgs")

(if ros::*compile-message*
    (let* ((file "make-pcloud-message.l")
           (fname (format nil "~A" (pathname-name file)))
           (old-module (find fname *loaded-modules*
                             :key #'lisp::load-module-file-name :test #'equal)))
      (if old-module (sys::unbinload old-module))
      (comp:compile-file-if-src-newer file)
      (load fname)
      )
  (load "./make-pcloud-message.l"))

(defvar P_WIDTH 176)
(defvar P_HEIGHT 144)
(setq *points-num* (* P_WIDTH P_HEIGHT))

(roseus "test_pcloud")
(ros::advertise "pcloud" sensor_msgs::PointCloud 5)
(ros::rate 15)

(setq *tm* (instance mtimer :init))
(let ((count 0)
      points msg)

  (dotimes (i *points-num*)
    (push (instance geometry_msgs::Point32 :init) points))

  (while (ros::ok)
    (send *tm* :start)
    (proc-pcloud)
    (format t ";;;; proc pointcloud ~4,1F [ms]~%" (* (send *tm* :stop) 1000))

    (setq msg (make-pointcloud-message *3dp* points))
    (format t ";;;; make-message    ~4,1F [ms]~%" (* (send *tm* :stop) 1000))

    (ros::publish "pcloud" msg)
    (format t ";;;; publish-message ~4,1F [ms]~%" (* (send *tm* :stop) 1000))

    (ros::sleep)
    (incf count)
    )
  )

(roseus "shutdown")
(exit)