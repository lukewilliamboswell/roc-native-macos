; Two expenses added, the second in another category, and the summary and
; the list showing both, newest first.
(test "add"
  (steps
    (fill (text-field) "Coffee 4.50")
    (submit (text-field))
    (choose "Transport")
    (fill (text-field) "Train to town 12")
    (submit (text-field))
    (expect-text (text "Added Train to town.") "Added Train to town.")
    (expect-dump (window :width 575 :height 495
                   (vstack :views 1
                     (vstack :views 5
                       (hstack :views 2
                         (asset-image icon.png :pixels 1024x1024 :width 36 :height 36)
                         (text "Expenses" :text-style large-title :weight bold))
                       (form :views 1
                         (hstack :views 3
                           (text-field "")
                           (dropdown "Transport" :items ("Food" "Transport" "Home" "Fun" "Other"))
                           (button "Add")))
                       (vstack :views 2
                         (hstack :views 3
                           (text "Summary" :text-style headline)
                           (spacer)
                           (button "Hide Summary"))
                         (hstack :views 3
                           (box
                             (vstack :views 2
                               (text "Spent" :color secondary-label :text-style caption1)
                               (text "16.50" :design monospaced-digits :text-style title3 :weight semibold)))
                           (box
                             (vstack :views 2
                               (text "Expenses" :color secondary-label :text-style caption1)
                               (text "2" :design monospaced-digits :text-style title3 :weight semibold)))
                           (box
                             (vstack :views 2
                               (text "Largest" :color secondary-label :text-style caption1)
                               (text "Train to town, 12.00" :design monospaced-digits :text-style title3 :weight semibold)))))
                       (vstack :views 2
                         (hstack :views 3
                           (text "Expenses" :text-style headline)
                           (spacer)
                           (button "Hide Expenses"))
                         (vstack :views 2
                           (hstack :views 3
                             (file-button "Import CSV…")
                             (spacer)
                             (button "Clear All"))
                           (box :border line:1:separator
                             (scroll :views 2 :height 180
                               (hstack :views 5
                                 (text "Train to town")
                                 (spacer)
                                 (text "Transport" :color secondary-label :text-style caption1)
                                 (text "12.00" :design monospaced-digits)
                                 (button "Remove"))
                               (hstack :views 5
                                 (text "Coffee")
                                 (spacer)
                                 (text "Food" :color secondary-label :text-style caption1)
                                 (text "4.50" :design monospaced-digits)
                                 (button "Remove"))))))
                       (text "Added Train to town." :color secondary-label :text-style callout)))))))
