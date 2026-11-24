; A file that is not audio is refused, the session idle, and a good file
; after it loads as the second track.
(test "invalid"
  (setup
    (audio-clock manual))
  (steps
    (files "specs/fixtures/invalid.wav")
    (wait 400)
    (expect-audio-status :state "Idle" :position 0 :duration 0 :track 1 :ended 0 :analysis false)
    (expect-dump (window :width 600 :height 583
                   (vstack :views 1
                     (vstack :views 12
                       (hstack :views 6
                         (image music.note)
                         (text "Player" :text-style title2 :weight semibold)
                         (spacer)
                         (button "Play Sample")
                         (button "Escape Assets")
                         (file-button "Choose Audio…"))
                       (drop-zone
                         (text "Drop an audio file here" :color secondary-label :text-style headline))
                       (text "Nothing loaded" :design monospaced-digits)
                       (slider :value 0.0)
                       (hstack :views 7
                         (button "Play" :enabled #f)
                         (button "Pause" :enabled #f)
                         (button "Resume" :enabled #f)
                         (button "Stop" :enabled #f)
                         (spacer)
                         (text "Volume" :color secondary-label :text-style caption1)
                         (slider :value 100.0))
                       (divider)
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
                           (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1)))
                       (divider)
                       (hstack :views 3
                         (checkbox "Measure levels" :checked #f)
                         (spacer)
                         (text "—" :design monospaced-digits))
                       (progress :value 0 :max 60)
                       (text "Could not play it: not audio (the file's data is not valid audio ('dta?'))" :color secondary-label :text-style caption1)))))
    (files "specs/fixtures/clicks.wav")
    (wait 300)
    (expect-audio-status :state "Stopped" :position 0 :duration 1000 :track 2 :ended 0 :analysis false)))
