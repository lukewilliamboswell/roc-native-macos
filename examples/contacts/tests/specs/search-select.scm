; Filling the search field filters the rows. Selecting a match opens
; that contact's detail pane.
(test "search-select"
  (steps
    (fill (text-field) "ada")
    (wait 200)
    (select (list-row "Ada A. Liskov"))
    (expect-tree (list-row "Ada A. Liskov") (row :views 2 (image _) (vstack :views 2 (text "Ada A. Liskov" _ _) _)))
    (expect-dump (window :width 740 :height 486
                   (vstack :views 1
                     (vstack :views 2
                       (hstack :views 4
                         (text "Contacts" :text-style title2 :weight semibold)
                         (image magnifyingglass)
                         (text-field "ada")
                         (text "371 of 10000" :color secondary-label :design monospaced-digits :text-style caption1))
                       (hstack :views 2
                         (list :rows 371 :with-views 11 :selected 2 :height 400 :visible-from 0 :visible-to 10
                           (row :views 2
                             (image person.crop.circle.fill)
                             (vstack :views 2
                               (text "Ada A. Lovelace" :text-style headline)
                               (text "ada.lovelace0@example.com · Amsterdam" :color secondary-label :text-style caption1)))
                           (row :views 2
                             (image person.crop.circle.fill)
                             (vstack :views 2
                               (text "Ada A. Turing" :text-style headline)
                               (text "ada.turing27@example.com · Dublin" :color secondary-label :text-style caption1)))
                           (row :views 2
                             (image person.crop.circle.fill)
                             (vstack :views 2
                               (text "Ada A. Liskov" :text-style headline)
                               (text "ada.liskov54@example.com · Lisbon" :color secondary-label :text-style caption1)))
                           (more))
                         (box :border line:1:separator :fill text-background
                           (vstack :views 5
                             (image person.crop.circle.fill)
                             (text "Ada A. Liskov" :text-style title1 :weight semibold)
                             (divider)
                             (hstack :views 2
                               (image envelope)
                               (text "ada.liskov54@example.com"))
                             (hstack :views 2
                               (image mappin.and.ellipse)
                               (text "Lisbon")))))))))))
