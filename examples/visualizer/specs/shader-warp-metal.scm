; A warp shader with the Metal renderer: each frame drags the previous one
; a tenth of the width (42.8 points) right with no fade, so the red mark at
; 20 to 40 smears right a step a frame, and the marks are drawn over it.
; The frames that run it allocate nothing on the Roc side: a frame never
; calls the engine. A Mac without a Metal device stops at (require-metal)
; and passes; shaders.scm checks what Core Graphics draws instead.
(test "shader-warp-metal"
  (steps
    (require-metal)
    (renderer metal)
    (window-size 600 300)
    (choose "Shaders")
    (choose "Warp")
    (frame 100)
    (expect-visible (text "Shaders: running"))
    (expect-probe (surface "Visualizer") 30 30 :r 100 :g 0 :b 0 :a 100)
    (expect-probe (surface "Visualizer") 70 30 :r 0 :g 0 :b 0 :a 0)
    (frame 100)
    (expect-probe (surface "Visualizer") 30 30 :r 100 :g 0 :b 0 :a 100)
    (expect-probe (surface "Visualizer") 70 30 :r 100 :g 0 :b 0 :a 100)
    (expect-probe (surface "Visualizer") 110 30 :r 0 :g 0 :b 0 :a 0)
    (frame 100)
    (expect-probe (surface "Visualizer") 110 30 :r 100 :g 0 :b 0 :a 100)
    (expect-probe (surface "Visualizer") 30 60 :r 0 :g 0 :b 0 :a 0)
    (mark-metrics)
    (frame 100)
    (frame 100)
    (frame 100)
    (expect-allocations-at-most 0)
    (expect-dump (window :width 600 :height 268
                   (vstack :views 1
                     (vstack :views 3
                       (segmented :items ("Scope" "Echo" "Bands" "Shaders") :selected "Shaders")
                       (hstack :views 2
                         (segmented :items ("Warp" "Invert" "Param" "Broken") :selected "Warp")
                         (text "Shaders: running" :color secondary-label :text-style caption1))
                       (hstack :views 2
                         (vstack :views 3
                           (button "Hide plot")
                           (button "Clear trail")
                           (checkbox "Caption" :checked #f))
                         (overlay
                           (surface "Visualizer" :width 428 :height 160 :pacing display :ticking #t :trail held :shader running
                             (space :points)
                             (fill adaptive:ff0000:ff0000 20.0,20.0 40.0,20.0 40.0,40.0 20.0,40.0 close)
                             (stroke orange 2.0 240.0,36.0 271.9,42.0 291.2,71.0 283.0,104.8 255.0,121.3 226.9,116.0 208.8,98.0 202.2,73.3 211.7,46.3 close))))))))))
