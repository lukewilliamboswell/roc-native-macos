; Choosing presets from the list: each draws its own scene on the surface
; (Echo Rings with a trail, Spectrum Bars from the bands), and the Lyrics
; choice, which belongs to the player, survives the switches. A switch
; makes a new scene and no new views; between two presets without
; shaders (whose status reports arrive in their own time), its
; allocations are bounded.
(test "presets"
  (steps
    (click (button "Scope"))
    (frame)
    (mark-metrics)
    (click (button "Echo Rings"))
    (expect-allocations-at-most 1692)
    (expect-metric-delta create_element 0)
    (frame)
    (expect-surfaces :shown 1 :ticking 1)
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
                             (surface "Visualizer" :width 506 :height 332 :pacing display :ticking #t :trail held
                               (space :fit 1000.0 1000.0 :scale 0.332 :offset 87.0 0.0)
                               (save)
                               (transform 1.000 0.000 0.000 1.000 500.000 500.000)
                               (transform 1.000 0.000 0.000 1.000 0.000 0.000)
                               (transform 0.333 0.000 0.000 0.333 0.000 0.000)
                               (opacity 1.000)
                               (stroke adaptive:b266ff:b266ff 12.0 0.0,-450.0 450.0,0.0 0.0,450.0 -450.0,0.0 0.0,-450.0 close)
                               (opacity 1.000)
                               (stroke adaptive:ff66d9:ff66d9 12.0 0.0,-450.0 450.0,0.0 0.0,450.0 -450.0,0.0 0.0,-450.0 close)
                               (restore))
                             (vstack :views 0)))
                         (vstack :views 4
                           (hstack :views 2
                             (text "Presets" :text-style headline)
                             (spacer))
                           (text "Using Echo Rings" :color secondary-label :text-style caption1)
                           (box :border line:1:separator :fill text-background
                             (scroll :views 15 :height 190
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Scope"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Spectrum Bars"))
                               (hstack :views 2
                                 (text "●" :color accent)
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
                                 (text "" :color accent)
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
                                 (button "Orb Garden"))))
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
                       (shortcut)))))
    (click (button "Spectrum Bars"))
    (toggle (checkbox "Lyrics"))
    (click (button "Scope"))
    (frame)
    (expect-checked (checkbox "Lyrics") true)
    (expect-dump (window :width 760 :height 539
                   (vstack :views 1
                     (vstack :views 8
                       (hstack :views 7
                         (asset-image icon.png :pixels 512x512 :width 30 :height 30)
                         (text "Music" :text-style title2 :weight bold)
                         (text "Polymorphic Defunctionalization Through Lambda Set Specialization" :color secondary-label :text-style title3)
                         (spacer)
                         (hstack :views 2
                           (text "" :color red :text-style caption1)
                           (file-button "Add lyrics…"))
                         (hstack :views 2
                           (button "Smaller Lyrics")
                           (button "Larger Lyrics"))
                         (checkbox "Lyrics" :checked #t))
                       (hstack :views 2
                         (drop-zone
                           (overlay
                             (surface "Visualizer" :width 506 :height 332 :pacing display :ticking #t
                               (space :fit 1000.0 1000.0 :scale 0.332 :offset 87.0 0.0)
                               (save)
                               (transform 1.000 0.000 0.000 1.000 500.000 500.000)
                               (transform 1.000 0.000 0.000 1.000 0.000 0.000)
                               (opacity 1.000)
                               (opacity 1.000)
                               (restore))
                             (vstack :views 1
                               (hstack :views 2
                                 (spacer)
                                 (button "Read all")))))
                         (vstack :views 4
                           (hstack :views 2
                             (text "Presets" :text-style headline)
                             (spacer))
                           (text "Using Scope" :color secondary-label :text-style caption1)
                           (box :border line:1:separator :fill text-background
                             (scroll :views 15 :height 190
                               (hstack :views 2
                                 (text "●" :color accent)
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
                                 (text "" :color accent)
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
                                 (button "Orb Garden"))))
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
