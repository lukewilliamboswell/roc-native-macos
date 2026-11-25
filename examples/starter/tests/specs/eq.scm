; A 12 dB cut at 250 Hz lowers that tone in both the output and the
; visualizer measurements. The 4 kHz tone stays steady, Flat restores
; the cut, and the volume changes the output alone.
(test "eq"
  (setup
    (audio-clock manual))
  (steps
    (drop "tests/fixtures/tones-44100.wav")
    (click (button "Next"))
    (wait 400)
    (click (button "Play"))
    (render 100)
    (wait 200)
    (expect-tone 250 -20)
    (expect-tone 4000 -20)
    (expect-snapshot :present true :loudest "7 -20, 18 -20")
    (choose "EQ")
    (slide (slider 7) -120)
    (render 100)
    (wait 200)
    (expect-eq :bypass false :preamp 0 :bands "0 0 0 -12 0 0 0 0 0 0" :volume 100)
    (expect-tone 250 -32)
    (expect-tone 4000 -20)
    (expect-snapshot :present true :loudest "7 -32, 18 -20")
    (click (button "Flat"))
    (render 100)
    (wait 200)
    (expect-eq :bypass false :preamp 0 :bands "0 0 0 0 0 0 0 0 0 0" :volume 100)
    (expect-tone 250 -20)
    (slide (slider 2) 50)
    (render 100)
    (wait 200)
    (expect-eq :volume 50)
    (expect-snapshot :present true :loudest "7 -20, 18 -20")
    (expect-dump (window :width 760 :height 840
                   (vstack :views 1
                     (vstack :views 9
                       (hstack :views 6
                         (asset-image icon.png :pixels 512x512 :width 30 :height 30)
                         (text "Music" :text-style title2 :weight bold)
                         (text "tones-44100" :color secondary-label :text-style title3)
                         (spacer)
                         (hstack :views 2
                           (text "" :color red :text-style caption1)
                           (file-button "Add lyrics…"))
                         (checkbox "Lyrics" :checked #f))
                       (hstack :views 2
                         (drop-zone
                           (overlay
                             (surface "Visualizer" :width 506 :height 332 :pacing display :ticking #t :trail empty :shader fallback
                               (space :fit 1000.0 1000.0 :scale 0.332 :offset 87.0 0.0))
                             (vstack :views 0)))
                         (vstack :views 4
                           (hstack :views 3
                             (text "Presets" :text-style headline)
                             (spacer)
                             (text "Simple visuals" :color secondary-label :text-style caption1))
                           (text "Using Orb Garden" :color secondary-label :text-style caption1)
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
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Sync Test"))))
                           (hstack :views 3
                             (button "New")
                             (button "Duplicate")
                             (button "Edit"))))
                       (box :border line:1:separator
                         (hstack :views 8
                           (text "0:00 / 0:00" :design monospaced-digits :weight medium)
                           (slider :value 800.0)
                           (button "Previous")
                           (button "Pause")
                           (button "Stop")
                           (button "Next")
                           (image speaker.wave.2.fill)
                           (slider :value 50.0)))
                       (segmented :items ("Hide Panels" "Queue" "EQ" "Editor") :selected "EQ")
                       (scroll :views 1 :height 289
                         (vstack :views 1
                           (vstack :views 4
                             (hstack :views 4
                               (text "Equalizer" :text-style headline)
                               (spacer)
                               (checkbox "Bypass" :checked #f)
                               (button "Flat" :enabled #f))
                             (hstack :views 3
                               (text "Preamp" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0.0 dB" :design monospaced-digits :text-style caption1))
                             (vstack :views 2
                               (hstack :views 3
                                 (text "Bands" :text-style subheadline :weight semibold)
                                 (spacer)
                                 (button "Hide Bands"))
                               (vstack :views 10
                                 (hstack :views 3
                                   (text "32 Hz" :color secondary-label :text-style caption1)
                                   (slider :value 0.0)
                                   (text "0.0 dB" :design monospaced-digits :text-style caption1))
                                 (hstack :views 3
                                   (text "64 Hz" :color secondary-label :text-style caption1)
                                   (slider :value 0.0)
                                   (text "0.0 dB" :design monospaced-digits :text-style caption1))
                                 (hstack :views 3
                                   (text "125 Hz" :color secondary-label :text-style caption1)
                                   (slider :value 0.0)
                                   (text "0.0 dB" :design monospaced-digits :text-style caption1))
                                 (hstack :views 3
                                   (text "250 Hz" :color secondary-label :text-style caption1)
                                   (slider :value 0.0)
                                   (text "0.0 dB" :design monospaced-digits :text-style caption1))
                                 (hstack :views 3
                                   (text "500 Hz" :color secondary-label :text-style caption1)
                                   (slider :value 0.0)
                                   (text "0.0 dB" :design monospaced-digits :text-style caption1))
                                 (hstack :views 3
                                   (text "1 kHz" :color secondary-label :text-style caption1)
                                   (slider :value 0.0)
                                   (text "0.0 dB" :design monospaced-digits :text-style caption1))
                                 (hstack :views 3
                                   (text "2 kHz" :color secondary-label :text-style caption1)
                                   (slider :value 0.0)
                                   (text "0.0 dB" :design monospaced-digits :text-style caption1))
                                 (hstack :views 3
                                   (text "4 kHz" :color secondary-label :text-style caption1)
                                   (slider :value 0.0)
                                   (text "0.0 dB" :design monospaced-digits :text-style caption1))
                                 (hstack :views 3
                                   (text "8 kHz" :color secondary-label :text-style caption1)
                                   (slider :value 0.0)
                                   (text "0.0 dB" :design monospaced-digits :text-style caption1))
                                 (hstack :views 3
                                   (text "16 kHz" :color secondary-label :text-style caption1)
                                   (slider :value 0.0)
                                   (text "0.0 dB" :design monospaced-digits :text-style caption1))))
                             (vstack :views 2
                               (hstack :views 3
                                 (text "Picture sync" :text-style headline)
                                 (spacer)
                                 (button "Sync Test"))
                               (hstack :views 3
                                 (text "Offset" :color secondary-label :text-style caption1)
                                 (slider :value 0.0)
                                 (text "0 ms" :design monospaced-digits :text-style caption1))))))
                       (text "Added 1 song." :color secondary-label :text-style callout)
                       (shortcut)
                       (shortcut)
                       (shortcut)))))))
