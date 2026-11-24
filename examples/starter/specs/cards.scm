; The summary hidden and shown again, one expense removed and then all of
; them cleared.
(test "cards"
  (steps
    (fill (text-field) "Tea 3.20")
    (submit (text-field))
    (fill (text-field) "Cake 4")
    (submit (text-field))
    (click (button "Hide Summary"))
    (expect-absent (button "Hide Summary"))
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
                       (vstack :views 1
                         (hstack :views 3
                           (text "Summary" :text-style headline)
                           (spacer)
                           (button "Show Summary")))
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
                             (scroll :views 2 :height 238
                               (hstack :views 5
                                 (text "Cake")
                                 (spacer)
                                 (text "Food" :color secondary-label :text-style caption1)
                                 (text "4.00" :design monospaced-digits)
                                 (button "Remove"))
                               (hstack :views 5
                                 (text "Tea")
                                 (spacer)
                                 (text "Food" :color secondary-label :text-style caption1)
                                 (text "3.20" :design monospaced-digits)
                                 (button "Remove"))))))
                       (text "Added Cake." :color secondary-label :text-style callout)))))
    (click (button "Show Summary"))
    (click (button "Remove" 1))
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
                               (text "3.20" :design monospaced-digits :text-style title3 :weight semibold)))
                           (box
                             (vstack :views 2
                               (text "Expenses" :color secondary-label :text-style caption1)
                               (text "1" :design monospaced-digits :text-style title3 :weight semibold)))
                           (box
                             (vstack :views 2
                               (text "Largest" :color secondary-label :text-style caption1)
                               (text "Tea, 3.20" :design monospaced-digits :text-style title3 :weight semibold)))))
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
                                 (text "Tea")
                                 (spacer)
                                 (text "Food" :color secondary-label :text-style caption1)
                                 (text "3.20" :design monospaced-digits)
                                 (button "Remove"))))))
                       (text "Removed an expense." :color secondary-label :text-style callout)))))
    (click (button "Clear All"))
    (expect-dump (window :width 520 :height 318
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
                       (text "Cleared every expense." :color secondary-label :text-style callout)))))))
