; A fresh stopwatch reads zero, with Lap disabled and no laps.
(test "initial"
  (steps
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
