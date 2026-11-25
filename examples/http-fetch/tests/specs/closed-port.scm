; A stubbed connection refusal shows a network error and its message.
(test "closed-port"
  (steps
    (fill (text-field) "http://127.0.0.1:9/")
    (click (button "Fetch"))
    (expect-pending-effects 1)
    (expect-request 1 :method "GET" :url "http://127.0.0.1:9/" :timeout 0)
    (expect-disabled (button "Cancel") false)
    (fail-http "refused" :kind network :detail "Could not connect to the server.")
    (run-effect 1)
    (expect-pending-effects 0)
    (expect-visible (text "NETWORK"))
    (expect-dump (window :width 560 :height 274
                   (vstack :views 1
                     (vstack :views 5
                       (text "HTTP fetch" :text-style title2 :weight semibold)
                       (box
                         (vstack :views 2
                           (form :views 1
                             (hstack :views 4
                               (image globe)
                               (text-field "http://127.0.0.1:9/")
                               (button "Fetch")
                               (button "Cancel" :enabled #f)))
                           (checkbox "Time out after 2 s" :checked #f)))
                       (text "Response" :text-style headline)
                       (hstack :views 2
                         (box :fill orange
                           (text "NETWORK" :color adaptive:ffffff:ffffff :text-style caption1 :weight bold))
                         (text "#1: Could not connect to the server." :color secondary-label))
                       (box :border line:1:separator :fill text-background
                         (text "The start of the body appears here." :color tertiary-label :design monospaced :text-style callout))))))))
