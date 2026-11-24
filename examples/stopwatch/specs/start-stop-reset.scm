; While the watch runs, an interval ticks; the clock is virtual, so each
; tick adds exactly the time the spec moves it on.
(test "start-stop-reset"
  (setup
    (initial-time 1700000000000))
  (steps
    (click (button "Start"))
    (expect-interval 47 1)
    (tick-interval 47)
    (advance-time 1250)
    (tick-interval 47)
    (expect-visible (text "0:01.25"))
    (click (button "Lap"))
    (advance-time 500)
    (mark-metrics)
    (tick-interval 47)
    (expect-metric-delta set_text 1)
    (expect-allocations-at-most 9)
    (expect-allocated-bytes-at-most 3919)
    (click (button "Stop"))
    (expect-interval 47 0)
    (expect-visible (text "0:01.75"))
    (expect-dump (window :width 420 :height 236
                   (vstack :views 1
                     (vstack :views 4
                       (text "0:01.75" :design monospaced-digits :font-size 56 :weight light)
                       (hstack :views 3
                         (button "Reset")
                         (button "Lap" :enabled #f)
                         (button "Start"))
                       (hstack :views 3
                         (text "Laps" :text-style headline)
                         (spacer)
                         (text "1 recorded" :color secondary-label :text-style caption1))
                       (box :border line:1:separator
                         (vstack :views 1
                           (hstack :views 4
                             (text "Lap 1" :color secondary-label)
                             (text "0:01.25" :design monospaced-digits)
                             (spacer)
                             (text "0:01.25" :color secondary-label :design monospaced-digits))))))))
    (click (button "Reset"))
    (expect-visible (text "0:00.00"))
    (expect-dump (window :width 420 :height 236
                   (vstack :views 1
                     (vstack :views 4
                       (text "0:00.00" :design monospaced-digits :font-size 56 :weight light)
                       (hstack :views 3
                         (button "Reset")
                         (button "Lap" :enabled #f)
                         (button "Start"))
                       (hstack :views 3
                         (text "Laps" :text-style headline)
                         (spacer)
                         (text "" :color secondary-label :text-style caption1))
                       (box :border line:1:separator
                         (vstack :views 1
                           (text "Press Lap while the watch runs." :color tertiary-label)))))))))
