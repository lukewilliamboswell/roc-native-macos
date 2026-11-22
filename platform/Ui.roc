import Engine exposing [Elem, Handler, HandlerOf, Signal]

## Native macOS controls for the roc-signals engine.
##
## Each builder is an ordinary `Engine.element` with a native element name;
## the engine's command stream is unchanged. The Swift host
## (`../host/Host.swift`) reads these names and builds the AppKit view each one
## stands for. Nothing here is HTML: there is no document, no CSS and no
## browser. A control's state crosses as plain attributes (`value`,
## `checked`, `disabled`), which the host applies to the live control.
##
## | Builder | Element | AppKit view |
## |---|---|---|
## | `vstack`, `hstack` | `ui-vstack`, `ui-hstack` | `NSStackView` |
## | `form` | `ui-form` | vertical `NSStackView`; Return submits |
## | `title`, `label`, `label_s`, `readout_s` | `ui-title`, `ui-label`, `ui-readout` | `NSTextField` label |
## | `button`, `button_s`, `action_button`, `submit_button` | `ui-button` | `NSButton` (push) |
## | `text_field` | `ui-text-field` | editable `NSTextField` |
## | `checkbox` | `ui-checkbox` | `NSButton` (checkbox) |
## | `slider` | `ui-slider` | `NSSlider` |
## | `divider` | `ui-divider` | `NSBox` separator |
## | `spacer` | `ui-spacer` | flexible empty `NSView` |
##
## Events: a button's `click`, a field's or slider's `input` (the new text),
## a checkbox's `change` (its new state) and a form's `submit`.
Ui := [].{

	## Children laid out top to bottom.
	vstack : List(Elem(ctx)) -> Elem(ctx)
	vstack = |kids| Engine.element("ui-vstack", [], kids)

	## Children laid out leading to trailing.
	hstack : List(Elem(ctx)) -> Elem(ctx)
	hstack = |kids| Engine.element("ui-hstack", [], kids)

	## A vertical stack whose `handler` runs when Return is pressed in one
	## of its text fields, or its `submit_button` is clicked.
	form : Handler(ctx), List(Elem(ctx)) -> Elem(ctx)
	form = |h, kids| Engine.element("ui-form", [Engine.on("submit", h)], kids)

	## Large bold text.
	title : Str -> Elem(ctx)
	title = |t| Engine.element("ui-title", [], [Engine.text(t)])

	## Static text.
	label : Str -> Elem(ctx)
	label = |t| Engine.element("ui-label", [], [Engine.text(t)])

	## Text that follows a value.
	label_s : Signal(ctx, Str) -> Elem(ctx)
	label_s = |v| Engine.element("ui-label", [], [Engine.text_s(v)])

	## Large monospaced text that follows a value, for numbers that change.
	readout_s : Signal(ctx, Str) -> Elem(ctx)
	readout_s = |v| Engine.element("ui-readout", [], [Engine.text_s(v)])

	## A push button with a static title.
	button : Str, HandlerOf(ctx, Engine.Click) -> Elem(ctx)
	button = |t, h| Engine.element("ui-button", [Engine.on_click(h)], [Engine.text(t)])

	## A push button whose title follows a value.
	button_s : Signal(ctx, Str), HandlerOf(ctx, Engine.Click) -> Elem(ctx)
	button_s = |t, h| Engine.element("ui-button", [Engine.on_click(h)], [Engine.text_s(t)])

	## A push button whose title follows a value and that is enabled while
	## `enabled` is true.
	action_button : Signal(ctx, Str), Signal(ctx, Bool), HandlerOf(ctx, Engine.Click) -> Elem(ctx)
	action_button = |t, enabled, h|
		Engine.element(
			"ui-button",
			[Engine.attr_presence("disabled", enabled.map(|on| if (on) Absent else Present(""))), Engine.on_click(h)],
			[Engine.text_s(t)],
		)

	## A push button that submits its enclosing `form`; it is the window's
	## default button, so Return presses it.
	submit_button : Str -> Elem(ctx)
	submit_button = |t| Engine.element("ui-button", [Engine.attr("submit", "")], [Engine.text(t)])

	## An editable single-line text field showing `value`, with `placeholder`
	## while empty. `handler` receives the text on every edit.
	text_field : Str, Signal(ctx, Str), Handler(ctx) -> Elem(ctx)
	text_field = |placeholder, v, h|
		Engine.element(
			"ui-text-field",
			[Engine.attr("placeholder", placeholder), Engine.attr_s("value", v), Engine.on("input", h)],
			[],
		)

	## A checkbox titled `t` that follows `checked`; `handler` receives its
	## new state.
	checkbox : Signal(ctx, Str), Signal(ctx, Bool), HandlerOf(ctx, Bool) -> Elem(ctx)
	checkbox = |t, checked, h|
		Engine.element(
			"ui-checkbox",
			[Engine.attr_s("title", t), Engine.attr_s("checked", checked.map(|on| if (on) "true" else "false")), Engine.on_checked(h)],
			[],
		)

	## A horizontal slider from `min` to `max` following `value`; `handler`
	## receives the new whole value as text while it is dragged.
	slider : { min : I64, max : I64 }, Signal(ctx, I64), Handler(ctx) -> Elem(ctx)
	slider = |{ min, max }, v, h|
		Engine.element(
			"ui-slider",
			[Engine.attr("min", min.to_str()), Engine.attr("max", max.to_str()), Engine.attr_s("value", v.map(|n| n.to_str())), Engine.on("input", h)],
			[],
		)

	## A horizontal separator line.
	divider : () -> Elem(ctx)
	divider = || Engine.element("ui-divider", [], [])

	## Empty space that grows to fill its stack.
	spacer : () -> Elem(ctx)
	spacer = || Engine.element("ui-spacer", [], [])
}
