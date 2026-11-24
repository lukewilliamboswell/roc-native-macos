; Reset puts the count back to 0, whatever it was.
(test "reset"
  (steps
    (click (button "+"))
    (click (button "+"))
    (expect-visible (text "2"))
    (click (button "Reset"))
    (expect-visible (text "0"))
    (expect-dump (window :width 360 :height 237
                   (vstack :views 1
                     (vstack :views 4
                       (text "Counter" :color secondary-label :text-style headline)
                       (text "0" :design monospaced-digits :font-size 64 :weight light)
                       (hstack :views 3
                         (button "−")
                         (button "Reset")
                         (button "+"))
                       (text "Each click is one engine turn." :color tertiary-label :text-style caption1)))))))
