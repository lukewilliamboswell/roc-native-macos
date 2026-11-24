; The bands drawn with the Metal renderer: the same pixels as with Core
; Graphics (bands.scm). A Mac without a Metal device draws with Core
; Graphics, so the spec passes the same there.
(test "bands-metal"
  (steps
    (renderer metal)
    (choose "Bands")
    (window-size 600 300)
    (frame 100)
    (expect-surfaces :shown 1 :ticking 1 :time "100.0")
    (expect-dump (window :width 600 :height 300
                   (vstack :views 1
                     (vstack :views 2
                       (segmented :items ("Scope" "Echo" "Bands") :selected "Bands")
                       (hstack :views 2
                         (vstack :views 3
                           (button "Hide plot")
                           (button "Clear trail")
                           (checkbox "Caption" :checked #f))
                         (overlay
                           (surface "Visualizer" :width 428 :height 160 :pacing display :ticking #t
                             (space :points)
                             (fill green 2.0,140.0 38.0,140.0 38.0,80.0 2.0,80.0 close 42.0,140.0 78.0,140.0 78.0,37.6 42.0,37.6 close 82.0,140.0 118.0,140.0 118.0,20.0 82.0,20.0 close 122.0,140.0 158.0,140.0 158.0,37.6 122.0,37.6 close 162.0,140.0 198.0,140.0 198.0,80.0 162.0,80.0 close 202.0,140.0 238.0,140.0 238.0,122.4 202.0,122.4 close 242.0,140.0 278.0,140.0 278.0,140.0 242.0,140.0 close 282.0,140.0 318.0,140.0 318.0,122.4 282.0,122.4 close 322.0,140.0 358.0,140.0 358.0,80.0 322.0,80.0 close)
                             (save)
                             (transform 1.000 0.000 0.000 1.000 100.000 20.000)
                             (fill adaptive:ffaa00:ffaa00 0.0,-8.0 8.0,0.0 0.0,8.0 -8.0,0.0 0.0,-8.0 close)
                             (restore)
                             (save)
                             (transform 1.000 0.000 0.000 1.000 380.000 80.000)
                             (fill adaptive:ff0000:ff0000 -8.0,-8.0 8.0,-8.0 8.0,8.0 -8.0,8.0 close)
                             (restore)
                             (stroke orange 1.0 0.0,150.0 360.0,150.0))))))))
    (expect-probe (surface "Visualizer") 100 20 :r 100 :g 67 :b 0 :a 100)
    (expect-probe (surface "Visualizer") 380 80 :r 100 :g 0 :b 0 :a 100)
    (step-source "synthetic.wave" 2)
    (frame 100)
    (expect-surfaces :time "200.0")
    (expect-dump (window :width 600 :height 300
                   (vstack :views 1
                     (vstack :views 2
                       (segmented :items ("Scope" "Echo" "Bands") :selected "Bands")
                       (hstack :views 2
                         (vstack :views 3
                           (button "Hide plot")
                           (button "Clear trail")
                           (checkbox "Caption" :checked #f))
                         (overlay
                           (surface "Visualizer" :width 428 :height 160 :pacing display :ticking #t
                             (space :points)
                             (fill green 2.0,140.0 38.0,140.0 38.0,20.0 2.0,20.0 close 42.0,140.0 78.0,140.0 78.0,37.6 42.0,37.6 close 82.0,140.0 118.0,140.0 118.0,80.0 82.0,80.0 close 122.0,140.0 158.0,140.0 158.0,122.4 122.0,122.4 close 162.0,140.0 198.0,140.0 198.0,140.0 162.0,140.0 close 202.0,140.0 238.0,140.0 238.0,122.4 202.0,122.4 close 242.0,140.0 278.0,140.0 278.0,80.0 242.0,80.0 close 282.0,140.0 318.0,140.0 318.0,37.6 282.0,37.6 close 322.0,140.0 358.0,140.0 358.0,20.0 322.0,20.0 close)
                             (save)
                             (transform 1.000 0.000 0.000 1.000 100.000 80.000)
                             (fill adaptive:ffaa00:ffaa00 0.0,-8.0 8.0,0.0 0.0,8.0 -8.0,0.0 0.0,-8.0 close)
                             (restore)
                             (save)
                             (transform 1.000 0.000 0.000 1.000 380.000 80.000)
                             (fill adaptive:ff0000:ff0000 -8.0,-8.0 8.0,-8.0 8.0,8.0 -8.0,8.0 close)
                             (restore)
                             (stroke orange 1.0 0.0,150.0 360.0,150.0))))))))
    (expect-probe (surface "Visualizer") 100 80 :r 100 :g 67 :b 0 :a 100)
    (expect-probe (surface "Visualizer") 100 20 :r 0 :g 0 :b 0 :a 0)
    (expect-probe (surface "Visualizer") 380 80 :r 100 :g 0 :b 0 :a 100)))
