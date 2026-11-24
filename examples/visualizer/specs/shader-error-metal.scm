; A warp that does not compile, with the Metal renderer: the error reaches
; the app as `Failed` with its stage, line and column, the app shows it,
; and the surface keeps drawing without the shader (its marks and trail).
; Choosing a good shader again runs it. A Mac without a Metal device stops
; at (require-metal) and passes.
(test "shader-error-metal"
  (steps
    (require-metal)
    (renderer metal)
    (window-size 600 300)
    (choose "Shaders")
    (choose "Broken")
    (frame 100)
    (expect-visible (text "warp line 3:30: use of undeclared identifier 'brightness'"))
    (expect-probe (surface "Visualizer") 30 30 :r 100 :g 0 :b 0 :a 100)
    (expect-probe (surface "Visualizer") 70 30 :r 0 :g 0 :b 0 :a 0)
    (expect-dump (window :width 600 :height 268
                   (vstack :views 1
                     (vstack :views 3
                       (segmented :items ("Scope" "Echo" "Bands" "Shaders" "Gallery") :selected "Shaders")
                       (hstack :views 2
                         (segmented :items ("Warp" "Invert" "Param" "Broken") :selected "Broken")
                         (text "warp line 3:30: use of undeclared identifier 'brightness'" :color secondary-label :text-style caption1))
                       (hstack :views 2
                         (vstack :views 3
                           (button "Hide plot")
                           (button "Clear trail")
                           (checkbox "Caption" :checked #f))
                         (overlay
                           (surface "Visualizer" :width 428 :height 160 :pacing display :ticking #t :trail held :shader failed
                             (space :points)
                             (fill adaptive:ff0000:ff0000 20.0,20.0 40.0,20.0 40.0,40.0 20.0,40.0 close)
                             (stroke orange 2.0 240.0,36.0 271.9,42.0 291.2,71.0 283.0,104.8 255.0,121.3 226.9,116.0 208.8,98.0 202.2,73.3 211.7,46.3 close))))))))
    (choose "Warp")
    (frame 100)
    (frame 100)
    (expect-visible (text "Shaders: running"))
    (expect-probe (surface "Visualizer") 70 30 :r 100 :g 0 :b 0 :a 100)))
