; Inspect shows the file's size, type, SHA-256, preview and file URL.
(test "inspect"
  (steps
    (files "tests/fixtures/hello.txt")
    (click (button "Inspect"))
    (wait 500)
    (expect-dump (window :width _ :height _
                   (vstack :views 1
                     (vstack :views 5
                       (hstack :views 4
                         (text "File inspector" :text-style title2 :weight semibold)
                         (spacer)
                         (file-button "Choose Files…")
                         (button "Clear"))
                       (drop-zone
                         (vstack :views 3
                           (image arrow.down.doc)
                           (text "Drop files here" :color secondary-label :text-style headline)
                           (text "Choose a file to see its digest, preview, and URL." :color tertiary-label :text-style caption1)))
                       (text "1 file" :color secondary-label :text-style caption1)
                       (box :border line:1:separator
                         (vstack :views 1
                           (hstack :views 4
                             (image doc)
                             (vstack :views 2
                               (text "hello.txt")
                               (text "21 bytes · text/plain" :color secondary-label :text-style caption1))
                             (spacer)
                             (button "Inspect"))))
                       (box :border line:1:separator :fill text-background
                         (vstack :views 5
                           (hstack :views 4
                             (image doc.text.magnifyingglass)
                             (text "hello.txt" :text-style headline)
                             (spacer)
                             (button "Save Copy…"))
                           (divider)
                           (hstack :views 2
                             (text "SHA-256" :color secondary-label :text-style caption1)
                             (text "86501f780e3b0baedf53a16cae80a0defcffb5ce1bb167c09ebf9c4f2e669c87" :design monospaced :text-style callout))
                           (hstack :views 2
                             (text "Starts" :color secondary-label :text-style caption1)
                             (text "hello from a fixture" :design monospaced :text-style callout))
                           (hstack :views 2
                             (text "URL" :color secondary-label :text-style caption1)
                             (text "file://<app>/tests/fixtures/hello.txt" :design monospaced :text-style callout))))))))))
