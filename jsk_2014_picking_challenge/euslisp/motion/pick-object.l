;; vim: set ft=lisp:
;; -*- mode: lisp;-*-

(load "package://jsk_2014_picking_challenge/euslisp/utils.l")
(load "package://jsk_2014_picking_challenge/euslisp/motion/move-to-target-bin.l")
(load "package://jsk_2014_picking_challenge/euslisp/motion/robot-motion-common.l")
(load "package://jsk_2014_picking_challenge/euslisp/robot-recognition.l")

(defun insert-to-pick-object-avs (arm bin)
  (let (avs)
  (move-to-target-bin-av arm bin)
  (pushback
    (send *baxter* arm :inverse-kinematics
          (make-cascoords :pos (v+ (send *pod* bin) #f(-90 0 50)))
          :revert-if-fail nil
          :rotation-axis :z) avs)
  (pushback
    (send *baxter* arm :move-end-pos #f(200 0 0) :world
          :revert-if-fail nil) avs)
  avs))

;; (setq arm :larm bin :k)
;; (progn (load "motion/pick-object.l ")(dolist (av (insert-to-pick-object-avs arm bin)) (send *irtviewer* :draw-objects) (send *ri* :angle-vector av 3000)      (send *ri* :wait-interpolation))(try-to-pick-object arm bin :rotate-and-left 30)(send *ri* :stop-grasp))
(defun try-to-pick-object (arm bin pattern depth &key (call-check-if-grabbed-function t)
			         (grasp-depth-z  95) ;; move z down to grasp
				 (check-depth-z  10) ;; move z up to check grabbed
				 (grasp-side-z   80) ;; move z down to side grasp
				 (grasp-side-z-down   40) ;; move z down to side (grasp after rotate)
				 )
  ;; load robot-test.l and run following command to get this information
  ;; (check-pick-offset :rarm '(:c :f :i :l) '((:middle . 30)))
  ;; (check-pick-offset :larm '(:a :d :g :j :b :e :h :k) '((:middle . 30)))
  (setq grasp-depth-z (min grasp-depth-z
			   (or 
			    (case arm
			      (:larm
			       (case bin (:a 95) (:d 95) (:g 95) (:j 95) (:b 90) (:e 90) (:h 90) (:k 85))
			       )
			      (:rarm 
			       (case bin (:c 90) (:f 80) (:i 115) (:l 130))
			       ))
			    grasp-depth-z)))
	
  (move-end-pos-with-interpolation arm :x depth :time 1000)

  ;; move left or right
  (case pattern
    (:right-most
     (move-end-pos-with-interpolation arm :y -80 :time 1000)
     )
    (:left-most
     (move-end-pos-with-interpolation arm :y 80 :time 1000)
     )
    (:right
     (move-end-pos-with-interpolation arm :y -50 :time 1000)
     )
    (:left
     (move-end-pos-with-interpolation arm :y 50 :time 1000)
     )
    (:middle
     ;; none
     )
    (:middle-left
     (move-end-pos-with-interpolation arm :y 20 :time 1000)
     )
    (:middle-right
     (move-end-pos-with-interpolation arm :y -20 :time 1000)
     )
    (:rotate-and-right
     (move-end-pos-with-interpolation arm :z (- grasp-side-z))
     (rotate-wrist arm -90)
     (send *ri* :angle-vector (send *baxter* :angle-vector) 1000)
     (send *ri* :wait-interpolation))
    (:rotate-and-left
     (move-end-pos-with-interpolation arm :z (- grasp-side-z))
     (rotate-wrist arm 90)
     (send *ri* :angle-vector (send *baxter* :angle-vector) 1000)
     (send *ri* :wait-interpolation))
    )

  ;; make vacuume ON
  (send *ri* :start-grasp arm)

  ;; grabbing
  (ros::ros-info "try to grasp with pattern ~A, depth ~A (grasp-depth-z ~A check-depth-z ~A)~%" pattern depth grasp-depth-z check-depth-z)
  (case pattern
    ((:right-most :left-most :right :left :middle :middle-left :middle-right)
     (move-end-rot-with-interpolation arm :y 2)
     (move-end-pos-with-interpolation arm :z (- grasp-depth-z))
     )
    (:rotate-and-left
     (move-end-rot-with-interpolation arm :x -4)
     (move-end-pos-with-interpolation arm :y 80 :z (- grasp-side-z-down) :time 1000)
     )
    (:rotate-and-right
     (move-end-rot-with-interpolation arm :x 4)
     (move-end-pos-with-interpolation arm :y -80 :z (- grasp-side-z-down) :time 1000))
    )

  (unix::sleep 1)

  ;; for check grabbed, seperate gripper.
  (case pattern
    ((:right-most :left-most :right :left :middle :middle-left :middle-right)
     (move-end-pos-with-interpolation arm :z check-depth-z :time 1000)
     )
    (:rotate-and-left
     (move-end-pos-with-interpolation arm :y -40 :time 1000)
     )
    (:rotate-and-right
     (move-end-pos-with-interpolation arm :y 40 :time 1000))
    )

  ;; ;; check if arm gripper unexpectedly attached to shelf or not
  ;; (ros::ros-info "check if attached to shelf")
  ;; (setq tmp-av (send *baxter* :angle-vector))
  ;; (setq arm-av (send *baxter* arm :angle-vector))
  ;; (send *baxter* :angle-vector (send *ri* :state :potentio-vector))
  ;; (ros::ros-info "potentio diff: ~A" (norm (v- (send *baxter* arm :angle-vector) arm-av)))
  ;; (send *baxter* :angle-vector tmp-av)

  ;; (ros::ros-info "check if grabbed")
  ;; (unless call-check-if-grabbed-function ;; return without checking grabbed
  ;;   (insert-to-pick-object-avs arm bin)
  ;;   (send *irtviewer* :draw-objects)
  ;;   (send *ri* :angle-vector (send *baxter* :angle-vector) 2000)
  ;;   (send *ri* :wait-interpolation)
  ;;   (return-from try-to-pick-object nil))

  (unless (check-if-grabbed arm)
    (ros::ros-info "go back to original position")
    ;; make vacuume OFF
    (send *ri* :stop-grasp arm)

    ;; go back to original position if can't grabbed
    (case pattern
      ((:right-most :left-most :right :left :middle :middle-left :middle-right)
       (move-end-pos-with-interpolation arm :z (- grasp-depth-z check-depth-z) :time 1000) ;; for check grabbed, seperate gripper.
       )
      (:rotate-and-right)
       (move-end-pos-with-interpolation arm :y 40 :z (+ grasp-side-z grasp-side-z-down) :time 1000)
      (:rotate-and-left
       (move-end-pos-with-interpolation arm :y -40 :z (+ grasp-side-z grasp-side-z-down) :time 1000)
       ))
    (insert-to-pick-object-avs arm bin)
    (send *irtviewer* :draw-objects)
    (send *ri* :angle-vector (send *baxter* :angle-vector) 1000)
    (send *ri* :wait-interpolation)

    (if nil ;(if *simulator-p* nil (see-if-grabbed arm))
        (progn (ros::ros-info "finish because see if grabbed")
               (return-from try-to-pick-object t))
      (return-from try-to-pick-object nil)))
  ;; patterns after grabbed
  (ros::ros-info "take arm from target bin")

  (case pattern
    ((:right-most :left-most :right :left :middle :middle-left :middle-right)
     ;; 50mm above then insert-to-pic
     (move-end-pos-with-interpolation arm :z (+ 50 (- grasp-depth-z check-depth-z)) :revert-if-fail nil :rotation-axis nil :time 4000)
     )
    ((:rotate-and-right :rotate-and-left)
     (move-end-pos-with-interpolation arm :z grasp-side-z-down :revert-if-fail nil :rotation-axis nil :time 4000)
     )
    )

  (case pattern
    (:right-most
     (move-end-pos-with-interpolation arm :y 80 :time 1500)
     )
    (:left-most
     (move-end-pos-with-interpolation arm :y -80 :time 1500)
     )
    (:right
     (move-end-pos-with-interpolation arm :y 50 :time 1500)
     )
    (:left
     (move-end-pos-with-interpolation arm :y -50 :time 1500)
     )
    (:middle
     ;; none
     )
    (:middle-left
     (move-end-pos-with-interpolation arm :y -20 :time 1500)
     )
    (:middle-right
     (move-end-pos-with-interpolation arm :y 20 :time 1500)
     )
    (:rotate-and-right
     (rotate-wrist arm 45)
     (send *ri* :angle-vector (send *baxter* :angle-vector) 1000)
     (send *ri* :wait-interpolation)
     (move-end-pos-with-interpolation arm :y 80 :z grasp-side-z :time 1000)
     )
    (:rotate-and-left
     (rotate-wrist arm -45)
     (send *ri* :angle-vector (send *baxter* :angle-vector) 1000)
     (send *ri* :wait-interpolation)
     (move-end-pos-with-interpolation arm :y -80 :z grasp-side-z :time 1000)
     )
    )

  (case pattern
    ((:right-most :left-most :right :left :middle :middle-left :middle-right)
     (move-end-rot-with-interpolation arm :y -4)
     )
    )
  t))

(defun pick-object (arm bin)
  (let* (av avs
            (patterns
                 '(:middle :middle :middle
                           :rotate-and-left :rotate-and-right :rotate-and-left :rotate-and-right :rotate-and-left :rotate-and-right
			   :right-most :left-most :right-most :left-most :right-most :left-most
			   :left :right :left :right :left :right
			   :middle-left :middle-right :middle-left :middle-right :middle-left :middle-right
		   ))
            (depths '(30 80 150
                      30 30 80 80 150 150
                      30 30 80 80 150 150
                      80 80 30 30 150 150
                      80 80 30 30 150 150
                      ))
            )

    ;; insert arm to target bin
    (dolist (av (insert-to-pick-object-avs arm bin))
      (send *irtviewer* :draw-objects)
      (send *ri* :angle-vector av 3000)
      (send *ri* :wait-interpolation))
    ;; store image to compare it with one after trying to pick
    (start-image-time-diff arm)
    ;; make vacuum on
    (send *ri* :start-grasp arm)
    ;; try to pick object while not grabbed
    (ros::ros-info "try to pick object ~A ~A" arm bin)
    (while
      (and patterns
           (not (try-to-pick-object arm bin (pop patterns) (pop depths))))
      (unless *simulator-p* (speak-en  "Fail to catch the target" :google t)))
    ;; take arm out of bin
    (ros::ros-info "take arm out of bin ~A ~A" arm bin)
    (setq avs (list (send *baxter* arm :move-end-pos #f(-250 0 0) :world :revert-if-fail nil :rotation-axis :z)))
    (pushback (avoid-shelf-pose-for-bin arm bin) avs)
    (send *irtviewer* :draw-objects)
    (send *ri* :angle-vector-sequence avs :fast nil 0 :scale 8.0)
    (send *ri* :wait-interpolation)
    ))
