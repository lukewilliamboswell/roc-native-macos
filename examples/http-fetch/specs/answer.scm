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
    (expect-dump """
      --- 560x221
      ui-vstack [1 views]
        ui-vstack [6 views]
          ui-text "HTTP fetch" {text-style=title2 weight=semibold}
          ui-form [1 views]
            ui-hstack [4 views]
              ui-image globe
              ui-text-field "https://example.com/"
              ui-button "Fetch"
              ui-button "Cancel" (disabled)
          ui-checkbox "Time out after 2 s" [ ]
          ui-divider
          ui-hstack [2 views]
            ui-box {fill=green}
              ui-text "200" {color=adaptive:ffffff:ffffff text-style=caption1 weight=bold}
            ui-text "#1: 13 bytes from https://example.com/" {color=secondary-label}
          ui-box {border=line:1:separator fill=text-background}
            ui-text "Hello, world." {design=monospaced text-style=callout}
      """)))
