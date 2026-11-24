; A preset's file edited with a field out of range, then with a version
; this app does not read: each time the editor says which field needs
; attention, and the picture keeps the last valid preset.
(test "problem"
  (steps
    (choose "Editor")
    (click (button "New"))
    (fill (text-area) "{\"version\": 1, \"id\": \"builtin.scope\", \"name\": \"Scope\", \"background\": \"#020A04\", \"layers\": [{\"type\": \"waveform\", \"colors\": [\"#39FF7A\"], \"size\": 1200, \"thickness\": 20, \"opacity\": 100}]}")
    (expect-visible (text "layers[0].size must be between 0 and 1000"))
    (fill (text-area) "{\"version\": 2}")
    (expect-visible (text "version is 2; this app reads version 1"))
    (frame)
    (expect-dump (window :width 760 :height 820
                   (vstack :views 1
                     (vstack :views 9
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
                             (surface "Visualizer" :width 506 :height 332 :pacing display :ticking #t
                               (space :fit 1000.0 1000.0 :scale 0.332 :offset 87.0 0.0))
                             (vstack :views 0)))
                         (vstack :views 17
                           (hstack :views 2
                             (text "Presets" :text-style headline)
                             (spacer))
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
                             (text "●" :color accent)
                             (button "Orb Garden"))
                           (hstack :views 3
                             (button "New")
                             (button "Duplicate")
                             (button "Edit"))))
                       (box :border line:1:separator
                         (hstack :views 8
                           (text "0:00 / 2:59" :design monospaced-digits)
                           (slider :value 0.0)
                           (button "Previous")
                           (button "Play")
                           (button "Stop")
                           (button "Next")
                           (image speaker.wave.2.fill)
                           (slider :value 100.0)))
                       (segmented :items ("Hide Panels" "Queue" "EQ" "Editor") :selected "Editor")
                       (vstack :views 5
                         (hstack :views 4
                           (text "Preset" :text-style headline)
                           (text-field "Untitled")
                           (button "Save As")
                           (button "Delete…" :enabled #f))
                         (text "version is 2; this app reads version 1" :color red :text-style callout)
                         (hstack :views 4
                           (dropdown "Add Layer" :items ("Add Layer" "Waveform" "Circular waveform" "Spectrum bars" "Ring" "Lissajous"))
                           (spacer)
                           (file-button "Import…")
                           (button "Export…"))
                         (vstack :views 1
                           (checkbox "Feedback" :checked #f))
                         (vstack :views 2
                           (hstack :views 3
                             (text "File" :text-style subheadline :weight semibold)
                             (spacer)
                             (button "Hide File"))
                           (text-area "{\"version\": 2}")))
                       (text "A new preset: add a layer, then Save As." :color secondary-label :text-style callout)
                       (shortcut)
                       (shortcut)
                       (shortcut)))))))
