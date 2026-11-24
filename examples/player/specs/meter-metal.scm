(test "meter-metal"
  (setup
    (audio-clock manual))
  (steps
    (require-metal)
    (renderer metal)
    (expect-absent (surface "Meter backlight"))
    (files "specs/fixtures/tones-44100.wav")
    (wait 300)
    (click (button "Play"))
    (render 100)
    (expect-absent (surface "Meter backlight"))
    (toggle (checkbox "Measure levels"))
    (render 100)
    (frame 100)
    (expect-visible (surface "Meter backlight"))
    (expect-probe (surface "Meter backlight") 282 16 :r 70 :a 100)
    (expect-dump (window :width 640 :height 595
                   (vstack :views 1
                     (vstack :views 6
                       (hstack :views 6
                         (image music.note)
                         (text "Player" :text-style title2 :weight semibold)
                         (spacer)
                         (button "Play Sample")
                         (button "Escape Assets")
                         (file-button "Choose Audio…"))
                       (drop-zone
                         (text "Drop an audio file here" :color secondary-label :text-style headline))
                       (box
                         (vstack :views 3
                           (text "tones-44100.wav · Playing · 0:00.20 / 0:00.50" :design monospaced-digits :text-style headline)
                           (slider :value 200.0)
                           (hstack :views 7
                             (button "Play")
                             (button "Pause")
                             (button "Resume")
                             (button "Stop")
                             (spacer)
                             (text "Volume" :color secondary-label :text-style caption1)
                             (slider :value 100.0))))
                       (box
                         (vstack :views 2
                           (hstack :views 4
                             (text "Equalizer" :text-style headline)
                             (spacer)
                             (checkbox "Bypass" :checked #f)
                             (button "Flat"))
                           (vstack :views 11
                             (hstack :views 3
                               (text "32" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "64" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "125" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "250" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "500" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "1k" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "2k" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "4k" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "8k" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "16k" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "Preamp" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1)))))
                       (box
                         (vstack :views 2
                           (hstack :views 3
                             (checkbox "Measure levels" :checked #t)
                             (spacer)
                             (text "level -20 dB · peak -14 dB · loudest 4k–5k" :design monospaced-digits))
                           (overlay :vertical center
                             (surface "Meter backlight" :width 564 :height 32 :pacing display :ticking #t :shader running)
                             (progress :value 40 :max 60))))
                       (text "Loaded: 0:00.50, 44100 Hz, 1 channel" :color secondary-label :text-style caption1)))))
    (toggle (checkbox "Measure levels"))
    (expect-absent (surface "Meter backlight"))
    (toggle (checkbox "Measure levels"))
    (click (button "Pause"))
    (render 100)
    (expect-absent (surface "Meter backlight"))))
