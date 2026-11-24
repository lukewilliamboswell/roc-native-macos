; The design's legibility check: lyrics over Echo Rings, whose trail keeps
; each frame under the next. The words are native text in the overlay's
; foreground, so the surface under them never holds a trace of a letter:
; where the line sits, the surface shows its background, frame after
; frame and line after line.
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
