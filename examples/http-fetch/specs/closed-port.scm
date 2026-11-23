; A refused connection is answered as the network's failure, with its message.
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
    (expect-dump """
      --- 560x221
      ui-vstack [1 views]
        ui-vstack [6 views]
          ui-text "HTTP fetch" {text-style=title2 weight=semibold}
          ui-form [1 views]
            ui-hstack [4 views]
              ui-image globe
              ui-text-field "http://127.0.0.1:9/"
              ui-button "Fetch"
              ui-button "Cancel" (disabled)
          ui-checkbox "Time out after 2 s" [ ]
          ui-divider
          ui-hstack [2 views]
            ui-box {fill=orange}
              ui-text "NETWORK" {color=adaptive:ffffff:ffffff text-style=caption1 weight=bold}
            ui-text "#1: Could not connect to the server." {color=secondary-label}
          ui-box {border=line:1:separator fill=text-background}
            ui-text "The start of the body appears here." {color=tertiary-label design=monospaced text-style=callout}
      """)))
