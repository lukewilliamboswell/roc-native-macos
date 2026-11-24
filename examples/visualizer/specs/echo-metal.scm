; The trail drawn with the Metal renderer: the same pixels as with Core
; Graphics (echo.scm). A Mac without a Metal device draws with Core
; Graphics, so the case passes the same there.
(test "echo-metal"
  (steps
    (renderer metal)
    (choose "Echo")
    (window-size 600 300)
    (frame 100)
    (expect-surfaces :shown 1 :ticking 1 :time "100.0")
    (expect-probe (surface "Visualizer") 30 30 :r 100 :g 0 :b 0 :a 100)
    (expect-probe (surface "Visualizer") 45 30 :r 0 :g 0 :b 0 :a 0)
    (frame 100)
    (expect-probe (surface "Visualizer") 25 30 :r 100 :g 0 :b 0 :a 100)
    (expect-probe (surface "Visualizer") 30 30 :r 100 :g 0 :b 0 :a 100)
    (expect-probe (surface "Visualizer") 45 30 :r 100 :g 0 :b 0 :a 50)
    (expect-probe (surface "Visualizer") 55 30 :r 0 :g 0 :b 0 :a 0)
    (repaint)
    (expect-probe (surface "Visualizer") 30 30 :r 100 :g 0 :b 0 :a 100)
    (expect-probe (surface "Visualizer") 45 30 :r 100 :g 0 :b 0 :a 50)
    (click (button "Clear trail"))
    (frame 0)
    (expect-probe (surface "Visualizer") 30 30 :r 100 :g 0 :b 0 :a 100)
    (expect-probe (surface "Visualizer") 45 30 :r 0 :g 0 :b 0 :a 0)
    (toggle (checkbox "Caption"))
    (frame 100)
    (expect-surfaces :shown 1 :ticking 1 :time "300.0")
    (expect-dump (window :width 600 :height 234
                   (vstack :views 1
                     (vstack :views 2
                       (segmented :items ("Scope" "Echo" "Bands" "Shaders" "Gallery") :selected "Echo")
                       (hstack :views 2
                         (vstack :views 3
                           (button "Hide plot")
                           (button "Clear trail")
                           (checkbox "Caption" :checked #t))
                         (overlay
                           (surface "Visualizer" :width 428 :height 160 :pacing display :ticking #t :trail held
                             (space :points)
                             (fill adaptive:ff0000:ff0000 20.0,20.0 40.0,20.0 40.0,40.0 20.0,40.0 close)
                             (stroke orange 2.0 240.0,36.0 271.9,42.0 291.2,71.0 283.0,104.8 255.0,121.3 226.9,116.0 208.8,98.0 202.2,73.3 211.7,46.3 close))
                           (box :fill adaptive:000000:000000
                             (text "Echo, echo, fading slow: the old light under the new." :color adaptive:ffffff:ffffff))))))))
    (expect-probe (surface "Visualizer") 120 150 :r 0 :g 0 :b 0 :a 0)
    (expect-probe (surface "Visualizer") 40 30 :r 100 :g 0 :b 0 :a 50)))
