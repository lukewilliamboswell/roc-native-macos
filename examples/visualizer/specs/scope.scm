; The scope: the wave and the marker scaled into the surface, moved on by
; their sources' steps and kept in place as the window widens, and the plot
; hidden, which takes the surface off the frame clock.
(test "scope"
  (steps
    (window-size 600 300)
    (frame 100)
    (expect-surfaces :shown 1 :ticking 1 :time "100.0")
    (expect-dump (window :width 600 :height 300
                   (vstack :views 1
                     (vstack :views 2
                       (segmented :items ("Scope" "Echo") :selected "Scope")
                       (hstack :views 2
                         (vstack :views 3
                           (button "Hide plot")
                           (button "Clear trail")
                           (checkbox "Caption" :checked #f))
                         (overlay
                           (surface "Visualizer" :width 428 :height 160 :pacing display :ticking #t
                             (space :fit 640.0 160.0 :scale 0.669 :offset 0.0 26.5)
                             (stroke green 3.0 0.0,80.0 80.0,37.6 160.0,20.0 240.0,37.6 320.0,80.0 400.0,122.4 480.0,140.0 560.0,122.4 640.0,80.0)
                             (save)
                             (transform 1.000 0.000 0.000 1.000 0.000 0.000)
                             (fill adaptive:ffaa00:ffaa00 0.0,68.0 12.0,80.0 0.0,92.0 -12.0,80.0 0.0,68.0 close)
                             (restore))))))))
    (step-source "synthetic.wave")
    (step-source "synthetic.wave")
    (step-source "synthetic.level")
    (step-source "synthetic.level")
    (frame 100)
    (expect-dump (window :width 600 :height 300
                   (vstack :views 1
                     (vstack :views 2
                       (segmented :items ("Scope" "Echo") :selected "Scope")
                       (hstack :views 2
                         (vstack :views 3
                           (button "Hide plot")
                           (button "Clear trail")
                           (checkbox "Caption" :checked #f))
                         (overlay
                           (surface "Visualizer" :width 428 :height 160 :pacing display :ticking #t
                             (space :fit 640.0 160.0 :scale 0.669 :offset 0.0 26.5)
                             (stroke green 3.0 0.0,20.0 80.0,37.6 160.0,80.0 240.0,122.4 320.0,140.0 400.0,122.4 480.0,80.0 560.0,37.6 640.0,20.0)
                             (save)
                             (transform 1.000 0.000 0.000 1.000 160.000 0.000)
                             (fill adaptive:ffaa00:ffaa00 0.0,68.0 12.0,80.0 0.0,92.0 -12.0,80.0 0.0,68.0 close)
                             (restore))))))))
    (expect-probe (surface "Visualizer") 107 80 :r 100 :g 67 :b 0 :a 100)
    (window-size 800 300)
    (frame 100)
    (expect-dump (window :width 800 :height 300
                   (vstack :views 1
                     (vstack :views 2
                       (segmented :items ("Scope" "Echo") :selected "Scope")
                       (hstack :views 2
                         (vstack :views 3
                           (button "Hide plot")
                           (button "Clear trail")
                           (checkbox "Caption" :checked #f))
                         (overlay
                           (surface "Visualizer" :width 628 :height 160 :pacing display :ticking #t
                             (space :fit 640.0 160.0 :scale 0.981 :offset 0.0 1.5)
                             (stroke green 3.0 0.0,20.0 80.0,37.6 160.0,80.0 240.0,122.4 320.0,140.0 400.0,122.4 480.0,80.0 560.0,37.6 640.0,20.0)
                             (save)
                             (transform 1.000 0.000 0.000 1.000 160.000 0.000)
                             (fill adaptive:ffaa00:ffaa00 0.0,68.0 12.0,80.0 0.0,92.0 -12.0,80.0 0.0,68.0 close)
                             (restore))))))))
    (expect-probe (surface "Visualizer") 157 80 :r 100 :g 67 :b 0 :a 100)
    (expect-probe (surface "Visualizer") 107 80 :r 0 :g 0 :b 0 :a 0)
    (click (button "Hide plot"))
    (expect-surfaces :shown 0 :ticking 0)
    (frame 100)
    (expect-surfaces :shown 0 :ticking 0 :time "400.0")
    (expect-dump (window :width 800 :height 146
                   (vstack :views 1
                     (vstack :views 2
                       (segmented :items ("Scope" "Echo") :selected "Scope")
                       (hstack :views 1
                         (vstack :views 3
                           (button "Show plot")
                           (button "Clear trail")
                           (checkbox "Caption" :checked #f)))))))))
