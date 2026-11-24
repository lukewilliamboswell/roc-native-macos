; An expense with no amount is refused with a hint beside the form, which
; goes once the amount is there.
(test "problem"
  (steps
    (fill (text-field) "Coffee")
    (submit (text-field))
    (expect-dump (window :width 520 :height 339
                   (vstack :views 1
                     (vstack :views 5
                       (hstack :views 2
                         (asset-image icon.png :pixels 1024x1024 :width 36 :height 36)
                         (text "Expenses" :text-style large-title :weight bold))
                       (form :views 2
                         (hstack :views 3
                           (text-field "Coffee")
                           (dropdown "Food" :items ("Food" "Transport" "Home" "Fun" "Other"))
                           (button "Add"))
                         (text "End with what it cost, as in “Coffee 4.50”." :color red :text-style caption1))
                       (vstack :views 2
                         (hstack :views 3
                           (text "Summary" :text-style headline)
                           (spacer)
                           (button "Hide Summary"))
                         (hstack :views 3
                           (box
                             (vstack :views 2
                               (text "Spent" :color secondary-label :text-style caption1)
                               (text "0.00" :design monospaced-digits :text-style title3 :weight semibold)))
                           (box
                             (vstack :views 2
                               (text "Expenses" :color secondary-label :text-style caption1)
                               (text "0" :design monospaced-digits :text-style title3 :weight semibold)))
                           (box
                             (vstack :views 2
                               (text "Largest" :color secondary-label :text-style caption1)
                               (text "None yet" :design monospaced-digits :text-style title3 :weight semibold)))))
                       (vstack :views 2
                         (hstack :views 3
                           (text "Expenses" :text-style headline)
                           (spacer)
                           (button "Hide Expenses"))
                         (vstack :views 2
                           (hstack :views 3
                             (file-button "Import CSV…")
                             (spacer)
                             (button "Clear All" :enabled #f))
                           (text "No expenses yet." :color tertiary-label :text-style callout)))
                       (text "Type what you bought and what it cost, then press Return." :color secondary-label :text-style callout)))))
    (fill (text-field) "Coffee 4.50")
    (submit (text-field))
    (expect-dump (window :width 520 :height 495
                   (vstack :views 1
                     (vstack :views 5
                       (hstack :views 2
                         (asset-image icon.png :pixels 1024x1024 :width 36 :height 36)
                         (text "Expenses" :text-style large-title :weight bold))
                       (form :views 1
                         (hstack :views 3
                           (text-field "")
                           (dropdown "Food" :items ("Food" "Transport" "Home" "Fun" "Other"))
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
                               (text "4.50" :design monospaced-digits :text-style title3 :weight semibold)))
                           (box
                             (vstack :views 2
                               (text "Expenses" :color secondary-label :text-style caption1)
                               (text "1" :design monospaced-digits :text-style title3 :weight semibold)))
                           (box
                             (vstack :views 2
                               (text "Largest" :color secondary-label :text-style caption1)
                               (text "Coffee, 4.50" :design monospaced-digits :text-style title3 :weight semibold)))))
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
                             (scroll :views 1 :height 180
                               (hstack :views 5
                                 (text "Coffee")
                                 (spacer)
                                 (text "Food" :color secondary-label :text-style caption1)
                                 (text "4.50" :design monospaced-digits)
                                 (button "Remove"))))))
                       (text "Added Coffee." :color secondary-label :text-style callout)))))))
