; A reload starts a fresh engine: the running watch and its lap are gone,
; and the fresh one runs as the first did.
(test "reload"
  (setup
    (initial-time 1700000000000))
  (steps
    (click (button "Start"))
    (tick-interval 47)
    (advance-time 300)
    (tick-interval 47)
    (click (button "Lap"))
    (reload)
    (expect-interval 47 0)
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
                           (text "Press Lap while the watch runs." :color tertiary-label)))))))
    (click (button "Start"))
    (tick-interval 47)
    (advance-time 200)
    (tick-interval 47)
    (expect-visible (text "0:00.20"))
    (click (button "Stop"))
    (click (button "Reset"))
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
