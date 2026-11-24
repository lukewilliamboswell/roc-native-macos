; A CSV file imported by a worker job, on a pool of two, and its expenses
; listed.
(test "import"
  (setup
    (worker-pool 2))
  (steps
    (files "specs/fixtures/expenses.csv")
    (await-work)
    (expect-workers :limit 2 :live 1 :running 0 :queued 0 :started 1 :answered 1 :lost 0 :stopped 0 :timed-out 0 :dropped 0)
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
                               (text "980.15" :design monospaced-digits :text-style title3 :weight semibold)))
                           (box
                             (vstack :views 2
                               (text "Expenses" :color secondary-label :text-style caption1)
                               (text "4" :design monospaced-digits :text-style title3 :weight semibold)))
                           (box
                             (vstack :views 2
                               (text "Largest" :color secondary-label :text-style caption1)
                               (text "Rent, 900.00" :design monospaced-digits :text-style title3 :weight semibold)))))
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
                             (scroll :views 4 :height 180
                               (hstack :views 5
                                 (text "Cinema, two tickets")
                                 (spacer)
                                 (text "Fun" :color secondary-label :text-style caption1)
                                 (text "15.00" :design monospaced-digits)
                                 (button "Remove"))
                               (hstack :views 5
                                 (text "Bus to work")
                                 (spacer)
                                 (text "Transport" :color secondary-label :text-style caption1)
                                 (text "2.80" :design monospaced-digits)
                                 (button "Remove"))
                               (hstack :views 5
                                 (text "Groceries")
                                 (spacer)
                                 (text "Food" :color secondary-label :text-style caption1)
                                 (text "62.35" :design monospaced-digits)
                                 (button "Remove"))
                               (hstack :views 5
                                 (text "Rent")
                                 (spacer)
                                 (text "Home" :color secondary-label :text-style caption1)
                                 (text "900.00" :design monospaced-digits)
                                 (button "Remove"))))))
                       (text "Imported 4 expenses from expenses.csv; 2 lines were not expenses." :color secondary-label :text-style callout)))))))
