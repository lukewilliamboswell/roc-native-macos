; The pointer over a hover target marks it, and leaving clears it.
(test "hover"
  (steps
    (choose "Styles")
    (hover (hover-target 3))
    (hover (hover-target 10))
    (expect-dump (window :width 560 :height 440
                   (vstack :views 1
                     (vstack :views 4
                       (hstack :views 2
                         (image square.grid.2x2.fill)
                         (vstack :views 2
                           (text "Gallery" :text-style title2 :weight semibold)
                           (text "Controls, typography, colors, and shortcuts" :color secondary-label :text-style caption1)))
                       (vstack :views 2
                         (hstack :views 3
                           (spacer)
                           (segmented :items ("Controls" "Text" "Styles" "Shortcuts") :selected "Styles")
                           (spacer))
                         (vstack :views 2
                           (vstack :views 2
                             (text "TEXT STYLES" :color secondary-label :text-style subheadline :weight semibold)
                             (box :border line:1:separator :fill text-background
                               (vstack :views 6
                                 (text "Large Title" :text-style large-title)
                                 (text "Title 1" :text-style title1)
                                 (text "Headline" :text-style headline)
                                 (text "Body, the default")
                                 (text "Caption, in the secondary label colour" :color secondary-label :text-style caption1)
                                 (text "Monospaced 0123456789" :design monospaced))))
                           (vstack :views 2
                             (text "COLOURS" :color secondary-label :text-style subheadline :weight semibold)
                             (box :border line:1:separator :fill text-background
                               (vstack :views 2
                                 (hstack :views 10
                                   (hover
                                     (box :fill red
                                       (spacer)))
                                   (hover
                                     (box :fill orange
                                       (spacer)))
                                   (hover
                                     (box :fill yellow
                                       (spacer)))
                                   (hover
                                     (box :fill green
                                       (spacer)))
                                   (hover
                                     (box :fill teal
                                       (spacer)))
                                   (hover
                                     (box :fill blue
                                       (spacer)))
                                   (hover
                                     (box :fill indigo
                                       (spacer)))
                                   (hover
                                     (box :fill purple
                                       (spacer)))
                                   (hover
                                     (box :fill pink
                                       (spacer)))
                                   (hover :pointer-inside #t
                                     (box :fill adaptive:24404b:9fc3cf
                                       (spacer))))
                                 (text "Slate" :color secondary-label :text-style caption1))))))
                       (shortcut)
                       (shortcut)))))
    (leave)
    (expect-dump (window :width 560 :height 440
                   (vstack :views 1
                     (vstack :views 4
                       (hstack :views 2
                         (image square.grid.2x2.fill)
                         (vstack :views 2
                           (text "Gallery" :text-style title2 :weight semibold)
                           (text "Controls, typography, colors, and shortcuts" :color secondary-label :text-style caption1)))
                       (vstack :views 2
                         (hstack :views 3
                           (spacer)
                           (segmented :items ("Controls" "Text" "Styles" "Shortcuts") :selected "Styles")
                           (spacer))
                         (vstack :views 2
                           (vstack :views 2
                             (text "TEXT STYLES" :color secondary-label :text-style subheadline :weight semibold)
                             (box :border line:1:separator :fill text-background
                               (vstack :views 6
                                 (text "Large Title" :text-style large-title)
                                 (text "Title 1" :text-style title1)
                                 (text "Headline" :text-style headline)
                                 (text "Body, the default")
                                 (text "Caption, in the secondary label colour" :color secondary-label :text-style caption1)
                                 (text "Monospaced 0123456789" :design monospaced))))
                           (vstack :views 2
                             (text "COLOURS" :color secondary-label :text-style subheadline :weight semibold)
                             (box :border line:1:separator :fill text-background
                               (vstack :views 2
                                 (hstack :views 10
                                   (hover
                                     (box :fill red
                                       (spacer)))
                                   (hover
                                     (box :fill orange
                                       (spacer)))
                                   (hover
                                     (box :fill yellow
                                       (spacer)))
                                   (hover
                                     (box :fill green
                                       (spacer)))
                                   (hover
                                     (box :fill teal
                                       (spacer)))
                                   (hover
                                     (box :fill blue
                                       (spacer)))
                                   (hover
                                     (box :fill indigo
                                       (spacer)))
                                   (hover
                                     (box :fill purple
                                       (spacer)))
                                   (hover
                                     (box :fill pink
                                       (spacer)))
                                   (hover
                                     (box :fill adaptive:24404b:9fc3cf
                                       (spacer))))
                                 (text "Point at a colour to name it" :color secondary-label :text-style caption1))))))
                       (shortcut)
                       (shortcut)))))))
