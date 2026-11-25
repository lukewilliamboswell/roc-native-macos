; Lyrics appear over Echo Rings as native text. After each frame the
; surface behind the letters still shows only its own background.
(test "trails"
  (setup
    (audio-clock manual))
  (steps
    (toggle (checkbox "Lyrics"))
    (click (button "Echo Rings"))
    (click (button "Play"))
    (render 5000)
    (frame 100)
    (frame 100)
    (frame 100)
    (expect-visible (text "The Roc on the kick has a crack in its beak."))
    (expect-probe (surface "Visualizer") 450 250 :r 3 :g 1 :b 6 :a 100)
    (expect-probe (surface "Visualizer") 60 250 :r 3 :g 1 :b 6 :a 100)
    (render 4000)
    (frame 100)
    (frame 100)
    (expect-visible (text "Three amps hum and the fourth one squeals."))
    (expect-probe (surface "Visualizer") 450 250 :r 3 :g 1 :b 6 :a 100)
    (expect-probe (surface "Visualizer") 60 250 :r 3 :g 1 :b 6 :a 100)))
