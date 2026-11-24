; A dropdown choice, and a shortcut the app hears twice.
(test "controls"
  (steps
    (choose "Cherry")
    (press "cmd+n" :heard true)
    (press "cmd+n" :heard true)
    (expect-dump (window :width 560 :height 409
                   (vstack :views 1
                     (vstack :views 4
                       (hstack :views 2
                         (image square.grid.2x2.fill)
                         (vstack :views 2
                           (text "Gallery" :text-style title2 :weight semibold)
                           (text "Native AppKit controls driven by the roc-signals engine" :color secondary-label :text-style caption1)))
                       (vstack :views 2
                         (hstack :views 3
                           (spacer)
                           (segmented :items ("Controls" "Text" "Styles" "Shortcuts") :selected "Controls")
                           (spacer))
                         (vstack :views 3
                           (vstack :views 2
                             (text "CHOICE" :color secondary-label :text-style subheadline :weight semibold)
                             (box :border line:1:separator
                               (vstack :views 2
                                 (hstack :views 3
                                   (image leaf.fill)
                                   (text "Fruit")
                                   (dropdown "Cherry" :items ("Apple" "Banana" "Cherry")))
                                 (text "You picked Cherry" :color accent))))
                           (vstack :views 2
                             (text "LEVEL" :color secondary-label :text-style subheadline :weight semibold)
                             (box :border line:1:separator
                               (vstack :views 2
                                 (hstack :views 3
                                   (image speaker.wave.2.fill)
                                   (slider :value 40.0)
                                   (text "40" :design monospaced-digits))
                                 (progress :value 40 :max 100))))
                           (vstack :views 2
                             (text "ACTIVITY" :color secondary-label :text-style subheadline :weight semibold)
                             (box :border line:1:separator
                               (hstack :views 2
                                 (checkbox "Working" :checked #f)
                                 (progress idle))))))
                       (shortcut)
                       (shortcut)))))))
