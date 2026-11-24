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
    (expect-dump (window :width 360 :height 261
                   (vstack :views 1
                     (vstack :views 3
                       (text "Counter" :color secondary-label :text-style headline)
                       (box :border line:1:separator
                         (text "2" :design monospaced-digits :font-size 72 :weight medium))
                       (hstack :views 3
                         (button "−")
                         (button "Reset")
                         (button "+"))))))))
