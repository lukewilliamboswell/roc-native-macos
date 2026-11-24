; Reset puts the count back to 0, whatever it was.
(test "reset"
  (steps
    (click (button "+"))
    (click (button "+"))
    (expect-visible (text "2"))
    (click (button "Reset"))
    (expect-visible (text "0"))
    (expect-dump (window :width 360 :height 261
                   (vstack :views 1
                     (vstack :views 3
                       (text "Counter" :color secondary-label :text-style headline)
                       (box :border line:1:separator
                         (text "0" :design monospaced-digits :font-size 72 :weight medium))
                       (hstack :views 3
                         (button "−")
                         (button "Reset")
                         (button "+"))))))))
