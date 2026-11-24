; The shaded built-ins with the Metal renderer: Orb Garden, the default,
; Liquid Drift and Plasma Weave compile and run, and draw their own picture
; on the frame clock, with nothing playing so that what they draw does not
; depend on the analysis tap's timing. Their frames, drawn and shaded in
; the host, allocate nothing on the Roc side. A Mac without a Metal device
; stops at (require-metal) and passes; fallback.scm checks the Core
; Graphics picture.
(test "shaders"
  (steps
    (require-metal)
    (renderer metal)
    (frame 100)
    (frame 100)
    (expect-absent (text "Simple visuals"))
    (expect-probe (surface "Visualizer") 253 166 :r 22 :g 5 :b 36 :a 100)
    (click (button "Liquid Drift"))
    (frame 100)
    (frame 100)
    (expect-probe (surface "Visualizer") 253 166 :r 2 :g 1 :b 8 :a 100)
    (click (button "Plasma Weave"))
    (frame 100)
    (expect-probe (surface "Visualizer") 253 166 :r 36 :g 40 :b 39 :a 100)
    (mark-metrics)
    (frame 100)
    (frame 100)
    (frame 100)
    (expect-allocations-at-most 0)
    (expect-dump (window :width 760 :height 539
                   (vstack :views 1
                     (vstack :views 8
                       (hstack :views 6
                         (asset-image icon.png :pixels 512x512 :width 30 :height 30)
                         (text "Music" :text-style title2 :weight bold)
                         (text "Polymorphic Defunctionalization Through Lambda Set Specialization" :color secondary-label :text-style title3)
                         (spacer)
                         (hstack :views 2
                           (text "" :color red :text-style caption1)
                           (file-button "Add lyrics…"))
                         (checkbox "Lyrics" :checked #f))
                       (hstack :views 2
                         (drop-zone
                           (overlay
                             (surface "Visualizer" :width 506 :height 332 :pacing display :ticking #t :shader running
                               (space :fit 1000.0 1000.0 :scale 0.332 :offset 87.0 0.0)
                               (save)
                               (transform 1.000 0.000 0.000 1.000 500.000 500.000)
                               (transform 1.000 0.000 0.000 1.000 0.000 0.000)
                               (opacity 1.000)
                               (opacity 1.000)
                               (restore)
                               (save)
                               (transform 1.000 0.000 0.000 1.000 500.000 500.000)
                               (transform 1.000 0.000 0.000 1.000 0.000 0.000)
                               (opacity 0.600)
                               (opacity 1.000)
                               (restore))
                             (vstack :views 0)))
                         (vstack :views 4
                           (hstack :views 2
                             (text "Presets" :text-style headline)
                             (spacer))
                           (text "Using Plasma Weave" :color secondary-label :text-style caption1)
                           (box :border line:1:separator :fill text-background
                             (scroll :views 16 :height 190
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Scope"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Spectrum Bars"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Echo Rings"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Liquid Drift"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Blur Corridor"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Superscope Bloom"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Flux Streaks"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Phase Scope"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Peak Meter"))
                               (hstack :views 2
                                 (text "●" :color accent)
                                 (button "Plasma Weave"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Hyperspace"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Mirror Shard"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Spectrum Fire"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Ripple Pool"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Orb Garden"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Sync Test"))))
                           (hstack :views 3
                             (button "New")
                             (button "Duplicate")
                             (button "Edit"))))
                       (box :border line:1:separator
                         (hstack :views 8
                           (text "0:00 / 2:59" :design monospaced-digits :weight medium)
                           (slider :value 0.0)
                           (button "Previous")
                           (button "Play")
                           (button "Stop")
                           (button "Next")
                           (image speaker.wave.2.fill)
                           (slider :value 100.0)))
                       (segmented :items ("Hide Panels" "Queue" "EQ" "Editor") :selected "Hide Panels")
                       (text "Press Play for the default song, or drop your own songs here with their .lrc or .txt lyrics." :color secondary-label :text-style callout)
                       (shortcut)
                       (shortcut)
                       (shortcut)))))))
