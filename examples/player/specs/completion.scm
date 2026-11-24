; A track played to its end, which stays ended until Play starts it again
; from the top, and ends a second time.
(test "completion"
  (setup
    (audio-clock manual))
  (steps
    (files "specs/fixtures/clicks.wav")
    (wait 300)
    (click (button "Play"))
    (render 1200)
    (wait 200)
    (expect-audio-status :state "Ended" :position 1000 :duration 1000 :track 1 :ended 1 :analysis false)
    (render 300)
    (wait 200)
    (expect-audio-status :state "Ended" :position 1000 :duration 1000 :track 1 :ended 1 :analysis false)
    (click (button "Play"))
    (render 500)
    (expect-audio-status :state "Playing" :position 500 :duration 1000 :track 1 :ended 1 :analysis false)
    (render 700)
    (wait 200)
    (expect-audio-status :state "Ended" :position 1000 :duration 1000 :track 1 :ended 2 :analysis false)
    (expect-dump (window :width 640 :height 581
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
                           (text "clicks.wav · Ended · 0:01.00 / 0:01.00" :design monospaced-digits :text-style headline)
                           (slider :value 1000.0)
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
                             (checkbox "Measure levels" :checked #f)
                             (spacer)
                             (text "—" :design monospaced-digits))
                           (progress :value 0 :max 60)))
                       (text "Played to the end (2 in all)" :color secondary-label :text-style caption1)))))))
