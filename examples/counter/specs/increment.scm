; Each click is one engine turn: three up and one down leave 2.
(test "increment"
  (steps
    (expect-visible (text "0"))
    (click (button "+"))
    (click (button "+"))
    (click (button "+"))
    (click (button "−"))
    (expect-visible (text "2"))
    (expect-absent (text "0"))
    (expect-dump (window :width 360 :height 237
                   (vstack :views 1
                     (vstack :views 4
                       (text "Counter" :color secondary-label :text-style headline)
                       (text "2" :design monospaced-digits :font-size 64 :weight light)
                       (hstack :views 3
                         (button "−")
                         (button "Reset")
                         (button "+"))
                       (text "Each click is one engine turn." :color tertiary-label :text-style caption1)))))))
