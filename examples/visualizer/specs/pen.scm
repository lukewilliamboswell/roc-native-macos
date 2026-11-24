; A pen's width read from a source: the level's steps widen the stroke,
; so a point just past its edge is drawn once the level has moved on.
(test "pen"
  (steps
    (choose "Bands")
    (window-size 600 300)
    (frame 100)
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
    (expect-probe (surface "Visualizer") 50 150 :r 100 :g 55 :b 16 :a 100)
    (expect-probe (surface "Visualizer") 50 153 :r 0 :g 0 :b 0 :a 0)
    (step-source "synthetic.level" 4)
    (frame 100)
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
                             (stroke orange 9.0 0.0,150.0 360.0,150.0))))))))
    (expect-probe (surface "Visualizer") 50 153 :r 100 :g 55 :b 16 :a 100)
    (expect-probe (surface "Visualizer") 50 157 :r 0 :g 0 :b 0 :a 0)))
