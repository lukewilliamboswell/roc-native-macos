; A 200 answer shows its status, its size and the start of its body.
(test "answer"
  (steps
    (fill (text-field) "https://example.com/")
    (click (button "Fetch"))
    (expect-request 1 :method "GET" :url "https://example.com/")
    (stub-http "hello" :url "https://example.com/" :status 200 :body "Hello, world." :headers (("content-type" "text/plain")))
    (run-effect 1)
    (expect-visible (text "200"))
    (expect-visible (text "Hello, world."))
    (expect-disabled (button "Cancel") true)
    (expect-dump (window :width 560 :height 274
                   (vstack :views 1
                     (vstack :views 5
                       (text "HTTP fetch" :text-style title2 :weight semibold)
                       (box
                         (vstack :views 2
                           (form :views 1
                             (hstack :views 4
                               (image globe)
                               (text-field "https://example.com/")
                               (button "Fetch")
                               (button "Cancel" :enabled #f)))
                           (checkbox "Time out after 2 s" :checked #f)))
                       (text "Response" :text-style headline)
                       (hstack :views 2
                         (box :fill green
                           (text "200" :color adaptive:ffffff:ffffff :text-style caption1 :weight bold))
                         (text "#1: 13 bytes from https://example.com/" :color secondary-label))
                       (box :border line:1:separator :fill text-background
                         (text "Hello, world." :design monospaced :text-style callout))))))))
