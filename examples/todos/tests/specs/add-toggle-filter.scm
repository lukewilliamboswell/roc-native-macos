; Two todos added, one done, and the filter showing each half.
(test "add-toggle-filter"
  (steps
    (fill (text-field) "Buy milk")
    (submit (text-field))
    (fill (text-field) "Walk the dog")
    (submit (text-field))
    (toggle (checkbox "Buy milk"))
    (choose "Done")
    (expect-dump (window :width 480 :height 416
                   (vstack :views 1
                     (vstack :views 4
                       (hstack :views 3
                         (text "To-do" :text-style large-title :weight bold)
                         (spacer)
                         (text "1 item left" :color secondary-label :design monospaced-digits :text-style subheadline))
                       (form :views 1
                         (hstack :views 2
                           (text-field "")
                           (button "Add")))
                       (vstack :views 2
                         (segmented :items ("All" "Open" "Done") :selected "Done")
                         (box :border line:1:separator :fill text-background
                           (scroll :views 1 :height 220
                             (hstack :views 4
                               (checkbox "Buy milk" :checked #t)
                               (text "Buy milk" :color secondary-label)
                               (spacer)
                               (button "Remove")))))
                       (shortcut)))))
    (choose "Open")
    (expect-dump (window :width 480 :height 416
                   (vstack :views 1
                     (vstack :views 4
                       (hstack :views 3
                         (text "To-do" :text-style large-title :weight bold)
                         (spacer)
                         (text "1 item left" :color secondary-label :design monospaced-digits :text-style subheadline))
                       (form :views 1
                         (hstack :views 2
                           (text-field "")
                           (button "Add")))
                       (vstack :views 2
                         (segmented :items ("All" "Open" "Done") :selected "Open")
                         (box :border line:1:separator :fill text-background
                           (scroll :views 1 :height 220
                             (hstack :views 4
                               (checkbox "Walk the dog" :checked #f)
                               (text "Walk the dog")
                               (spacer)
                               (button "Remove")))))
                       (shortcut)))))))
