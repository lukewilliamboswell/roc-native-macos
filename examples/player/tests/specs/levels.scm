; The measurements of two tones at two sample rates and of silence, the
; sources a surface reads from them, and the volume halving the output.
(test "levels"
  (setup
    (audio-clock manual))
  (steps
    (toggle (checkbox "Measure levels"))
    (files "tests/fixtures/tones-44100.wav")
    (wait 300)
    (click (button "Play"))
    (render 300)
    (wait 200)
    (expect-snapshot :present true :at "267.0" :rate 44100 :rms -20 :peak -14 :finite true :loudest "7 -20, 18 -20")
    (expect-sources :waveform "1024 -0.20 0.20" :bands "24 0.00 0.67" :level "0.67" :bass "0.48" :mids "0.66" :treble "0.67")
    (slide (slider 2) 50)
    (render 100)
    (expect-eq :bypass false :preamp 0 :bands "0 0 0 0 0 0 0 0 0 0" :volume 50)
    (expect-tone 4000 -26)
    (expect-snapshot :present true :at "371.5" :rate 44100 :rms -20 :peak -14 :finite true :loudest "7 -20, 18 -20")
    (files "tests/fixtures/tones-48000.wav")
    (wait 300)
    (click (button "Play"))
    (render 300)
    (expect-snapshot :present true :at "277.3" :rate 48000 :rms -20 :peak -14 :finite true :loudest "7 -21, 18 -20")
    (files "tests/fixtures/silence-44100.wav")
    (wait 300)
    (click (button "Play"))
    (render 200)
    (expect-snapshot :present true :at "174.1" :rate 44100 :rms -120 :peak -120 :finite true :loudest "none")
    (files "tests/fixtures/silence-48000.wav")
    (wait 300)
    (click (button "Play"))
    (render 200)
    (expect-snapshot :present true :at "170.7" :rate 48000 :rms -120 :peak -120 :finite true :loudest "none")
    (expect-sources :waveform "1024 0.00 0.00" :bands "24 0.00 0.00" :level "0.00" :bass "0.00" :mids "0.00" :treble "0.00")
    (wait 200)
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
                           (text "silence-48000.wav · Playing · 0:00.20 / 0:00.25" :design monospaced-digits :text-style headline)
                           (slider :value 200.0)
                           (hstack :views 7
                             (button "Play")
                             (button "Pause")
                             (button "Resume")
                             (button "Stop")
                             (spacer)
                             (text "Volume" :color secondary-label :text-style caption1)
                             (slider :value 50.0))))
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
                             (text "level -120 dB · peak -120 dB" :design monospaced-digits))
                           (overlay :vertical center
                             (surface "Meter backlight" :width 564 :height 32 :pacing display :ticking #t :shader fallback)
                             (progress :value 0 :max 60))))
                       (text "Loaded: 0:00.25, 48000 Hz, 1 channel" :color secondary-label :text-style caption1)))))))
