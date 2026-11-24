; Shaders with the Core Graphics renderer: they never run, the app hears
; `Fallback`, and each test draws Echo's marks and trail, the same pixels
; as echo.scm, whichever stages it asks for. This is what a Mac without a
; Metal device draws for the shader-*-metal specs. (Invert's black background
; is still fading from the trail when Param is drawn.)
(test "shaders"
  (steps
    (renderer cg)
    (window-size 600 300)
    (choose "Shaders")
    (choose "Warp")
    (frame 100)
    (expect-visible (text "Shaders: not on this renderer, so the marks and the trail alone"))
    (expect-probe (surface "Visualizer") 30 30 :r 100 :g 0 :b 0 :a 100)
    (expect-probe (surface "Visualizer") 70 30 :r 0 :g 0 :b 0 :a 0)
    (frame 100)
    (expect-probe (surface "Visualizer") 45 30 :r 100 :g 0 :b 0 :a 50)
    (expect-probe (surface "Visualizer") 70 30 :r 0 :g 0 :b 0 :a 0)
    (choose "Invert")
    (frame 100)
    (expect-probe (surface "Visualizer") 30 30 :r 100 :g 0 :b 0 :a 100)
    (expect-probe (surface "Visualizer") 70 30 :r 0 :g 0 :b 0 :a 100)
    (choose "Param")
    (step-source "synthetic.level" 4)
    (frame 100)
    (expect-probe (surface "Visualizer") 30 30 :r 100 :g 0 :b 0 :a 100)
    (expect-probe (surface "Visualizer") 120 140 :r 0 :g 0 :b 0 :a 50)
    (choose "Broken")
    (frame 100)
    (expect-visible (text "Shaders: not on this renderer, so the marks and the trail alone"))
    (expect-probe (surface "Visualizer") 30 30 :r 100 :g 0 :b 0 :a 100)
    (expect-dump (window :width 600 :height 268
                   (vstack :views 1
                     (vstack :views 3
                       (segmented :items ("Scope" "Echo" "Bands" "Shaders") :selected "Shaders")
                       (hstack :views 2
                         (segmented :items ("Warp" "Invert" "Param" "Broken") :selected "Broken")
                         (text "Shaders: not on this renderer, so the marks and the trail alone" :color secondary-label :text-style caption1))
                       (hstack :views 2
                         (vstack :views 3
                           (button "Hide plot")
                           (button "Clear trail")
                           (checkbox "Caption" :checked #f))
                         (overlay
                           (surface "Visualizer" :width 428 :height 160 :pacing display :ticking #t :trail held :shader fallback
                             (space :points)
                             (fill adaptive:ff0000:ff0000 20.0,20.0 40.0,20.0 40.0,40.0 20.0,40.0 close)
                             (stroke orange 2.0 240.0,36.0 271.9,42.0 291.2,71.0 283.0,104.8 255.0,121.3 226.9,116.0 208.8,98.0 202.2,73.3 211.7,46.3 close))))))))))
