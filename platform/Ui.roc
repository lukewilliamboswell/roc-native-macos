import Engine exposing [Elem, Handler, HandlerOf, Signal]
import Core

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
## | `scroll` | `ui-scroll` | `NSScrollView` around a vertical `NSStackView` |
## | `list`, `row` | `ui-list`, `ui-row` | view-based `NSTableView`; each `ui-row` is a table row |
## | `title`, `label`, `label_s`, `text`, `text_s`, `readout_s` | `ui-title`, `ui-label`, `ui-readout` | `NSTextField` label |
## | `button`, `button_s`, `action_button`, `submit_button` | `ui-button` | `NSButton` (push) |
## | `text_field` | `ui-text-field` | editable `NSTextField` |
## | `text_area` | `ui-text-area` | `NSTextView` in an `NSScrollView` |
## | `checkbox` | `ui-checkbox` | `NSButton` (checkbox) |
## | `slider` | `ui-slider` | `NSSlider` |
## | `dropdown` | `ui-dropdown` | `NSPopUpButton` |
## | `segmented`, `tabs` | `ui-segmented` | `NSSegmentedControl` (`tabs` adds an `Engine.switch`) |
## | `image` | `ui-image` | `NSImageView` of an SF Symbol |
## | `progress`, `busy` | `ui-progress` | `NSProgressIndicator` (bar) |
## | `shortcut` | `ui-shortcut` | none: a document key handler |
## | `file_button` | `ui-file-button` | `NSButton` opening an `NSOpenPanel` |
## | `drop_zone` | `ui-drop-zone` | an `NSView` registered for dragged file URLs |
## | `divider` | `ui-divider` | `NSBox` separator |
## | `spacer` | `ui-spacer` | flexible empty `NSView` |
##
## Events: a button's `click`, a field's, text area's or slider's `input`
## (the new text), a checkbox's `change` (its new state), a dropdown's or
## segmented control's `change` (the chosen title), a row's `select`, a
## form's `submit`, a shortcut's `keydown`, and the files a file button's
## `change` or a drop zone's `drop` delivers.
##
## Layout and style are props records of defaulted fields, which travel as
## attributes: `spacing`, `padding` and `align` on stacks, `height` and `min-height` on scrolls and lists,
## `font` and `color` on text. Colours are AppKit's semantic colours.
Ui := [].{

	## How a vertical stack lays out its children: the gap between them,
	## the margin around them, and where they sit across it (`Fill`
	## stretches each to the stack's width).
	VStackProps := { spacing : U32 ?? 8, padding : U32 ?? 0, align : [Leading, Center, Trailing, Fill] ?? Leading }

	## How a horizontal stack lays out its children; `align` places them
	## across it.
	HStackProps := { spacing : U32 ?? 8, padding : U32 ?? 0, align : [Top, Center, Bottom] ?? Center }

	## Children laid out top to bottom: `Ui.vstack({ spacing: 12, align: Fill }, kids)`,
	## or `Ui.vstack({}, kids)` for the defaults.
	vstack : VStackProps, List(Elem(ctx)) -> Elem(ctx)
	vstack = |props, kids| {
		align = match props.align {
			Leading => "leading"
			Center => "center"
			Trailing => "trailing"
			Fill => "fill"
		}
		Engine.element("ui-vstack", stack_attrs(props.spacing, props.padding, align), kids)
	}

	## Children laid out leading to trailing.
	hstack : HStackProps, List(Elem(ctx)) -> Elem(ctx)
	hstack = |props, kids| {
		align = match props.align {
			Top => "top"
			Center => "center"
			Bottom => "bottom"
		}
		Engine.element("ui-hstack", stack_attrs(props.spacing, props.padding, align), kids)
	}

	stack_attrs : U32, U32, Str -> List(Engine.Attr(ctx))
	stack_attrs = |spacing, padding, align|
		[Engine.attr("spacing", spacing.to_str()), Engine.attr("padding", padding.to_str()), Engine.attr("align", align)]

	## A scroll area's starting height (the window opens with it) and the
	## least height the window can shrink it to, in points, and the gap and
	## margin around what it holds. A window holding a scroll area or a list
	## stops growing to fit its content: the scroll area takes the slack.
	ScrollProps := { height : U32 ?? 240, min_height : U32 ?? 80, spacing : U32 ?? 8, padding : U32 ?? 0 }

	## A vertically scrolling area, as wide as its stack, holding `content`
	## top to bottom; each of its elements fills the area's width. `content`
	## may be several elements, such as the rows of an `Engine.table_view`.
	scroll : ScrollProps, Elem(ctx) -> Elem(ctx)
	scroll = |props, content|
		Engine.element(
			"ui-scroll",
			[Engine.attr("height", props.height.to_str()), Engine.attr("min-height", props.min_height.to_str()), Engine.attr("spacing", props.spacing.to_str()), Engine.attr("padding", props.padding.to_str())],
			[content],
		)

	## A list's starting and least height, in points.
	ListProps := { height : U32 ?? 320, min_height : U32 ?? 120 }

	## A scrolling table whose rows are the elements of `rows`, for long
	## lists: an `Engine.table_view` (or `each`) of `row`s. AppKit draws only
	## the rows on screen, each row the engine inserts, removes or moves is
	## one incremental change to the table, and a row's views are made when
	## it is first scrolled into sight.
	list : ListProps, Elem(ctx) -> Elem(ctx)
	list = |props, rows|
		Engine.element("ui-list", [Engine.attr("height", props.height.to_str()), Engine.attr("min-height", props.min_height.to_str())], [rows])

	## One row of a `list`: its children laid out leading to trailing.
	## `handler` runs when the user selects the row.
	row : Handler(ctx), List(Elem(ctx)) -> Elem(ctx)
	row = |h, kids| Engine.element("ui-row", [Engine.on("select", h)], kids)

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

	## A text style: AppKit's system fonts for body text, a title, a
	## headline, a caption or monospaced text.
	Font : [Body, Title, Headline, Caption, Mono]

	## A semantic AppKit colour, which follows light and dark mode.
	Color : [Primary, Secondary, Tertiary, Accent, Red, Orange, Green, Blue]

	## How a piece of text looks.
	TextProps := { font : Font ?? Body, color : Color ?? Primary }

	## Static text in a style: `Ui.text({ font: Caption, color: Secondary }, "Saved")`.
	text : TextProps, Str -> Elem(ctx)
	text = |props, t| Engine.element("ui-label", text_attrs(props.font, props.color), [Engine.text(t)])

	## Styled text that follows a value.
	text_s : TextProps, Signal(ctx, Str) -> Elem(ctx)
	text_s = |props, v| Engine.element("ui-label", text_attrs(props.font, props.color), [Engine.text_s(v)])

	text_attrs : Font, Color -> List(Engine.Attr(ctx))
	text_attrs = |font, color| [Engine.attr("font", font_name(font)), Engine.attr("color", color_name(color))]

	font_name : Font -> Str
	font_name = |font|
		match font {
			Body => "body"
			Title => "title"
			Headline => "headline"
			Caption => "caption"
			Mono => "mono"
		}

	color_name : Color -> Str
	color_name = |color|
		match color {
			Primary => "primary"
			Secondary => "secondary"
			Tertiary => "tertiary"
			Accent => "accent"
			Red => "red"
			Orange => "orange"
			Green => "green"
			Blue => "blue"
		}

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

	## A text area's least height, in points.
	TextAreaProps := { height : U32 ?? 96 }

	## An editable multi-line text area showing `value`; `handler` receives
	## the whole text on every edit.
	text_area : TextAreaProps, Signal(ctx, Str), Handler(ctx) -> Elem(ctx)
	text_area = |props, v, h|
		Engine.element("ui-text-area", [Engine.attr("height", props.height.to_str()), Engine.attr_s("value", v), Engine.on("input", h)], [])

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

	## A pop-up menu of `choices` showing `selected`; `handler` receives
	## the chosen title.
	dropdown : List(Str), Signal(ctx, Str), Handler(ctx) -> Elem(ctx)
	dropdown = |choices, selected, h|
		Engine.element("ui-dropdown", [Engine.attr("choices", Str.join_with(choices, "\n")), Engine.attr_s("value", selected), Engine.on("change", h)], [])

	## A segmented control of `choices` showing `selected`; `handler`
	## receives the chosen title.
	segmented : List(Str), Signal(ctx, Str), Handler(ctx) -> Elem(ctx)
	segmented = |choices, selected, h|
		Engine.element("ui-segmented", [Engine.attr("choices", Str.join_with(choices, "\n")), Engine.attr_s("value", selected), Engine.on("change", h)], [])

	## Tabs: a segmented control of `names` above `page(name)` for the
	## selected one. Only the shown page is built; switching disposes the
	## old page with any state inside it (`Engine.switch`).
	tabs : List(Str), Signal(ctx, Str), Handler(ctx), (Str -> Elem(ctx)) -> Elem(ctx)
	tabs = |names, selected, h, page|
		Engine.element("ui-vstack", [Engine.attr("spacing", "12"), Engine.attr("align", "fill")], [segmented(names, selected, h), Engine.switch(selected, names, page)])

	## An SF Symbol by name (`"star.fill"`) in a colour.
	image : Str, Color -> Elem(ctx)
	image = |symbol, color| Engine.element("ui-image", [Engine.attr("symbol", symbol), Engine.attr("color", color_name(color))], [])

	## A determinate progress bar from 0 to `max` following `value`.
	progress : { max : I64 }, Signal(ctx, I64) -> Elem(ctx)
	progress = |{ max }, v|
		Engine.element("ui-progress", [Engine.attr("max", max.to_str()), Engine.attr_s("value", v.map(|n| n.to_str()))], [])

	## An indeterminate progress bar, animating while `active` is true.
	busy : Signal(ctx, Bool) -> Elem(ctx)
	busy = |active|
		Engine.element("ui-progress", [Engine.attr("indeterminate", ""), Engine.attr_s("value", active.map(|on| if (on) "1" else "0"))], [])

	## A window-wide keyboard shortcut: `handler` runs when a key matching
	## one of `chords` is pressed and no control's own key handler heard it.
	## The key's default is prevented. Compare the payload's `heard` with a
	## chord to tell several apart:
	## `Ui.shortcut([Ui.command("n")], Engine.handle(|_key| ...))`.
	shortcut : List(Engine.Chord), HandlerOf(ctx, Engine.Key) -> Elem(ctx)
		where [ctx.outside_rows : () -> Engine.OutsideRows(ctx)]
	shortcut = |chords, h|
		Engine.element("ui-shortcut", [Engine.on_document_key({ keymap: Engine.const(Core.Keymap.prevent(chords)) }, h)], [])

	## The chord of Command and `key` (a lower-case letter, or a key name
	## such as `"Enter"`).
	command : Str -> Engine.Chord
	command = |key| Core.Chord.plain(key).with_meta()

	## The chord of `key` with no modifiers, such as `"Escape"`.
	plain_key : Str -> Engine.Chord
	plain_key = |key| Core.Chord.plain(key)

	## A push button titled `t` that opens an open panel (several files may
	## be chosen); `handler` receives the chosen files as handles, never
	## their bytes, in a `change` event. Read them with `Engine.read_utf8`,
	## `Engine.sha256` and the other file requests.
	file_button : Str, Engine.FilesHandler(ctx) -> Elem(ctx)
	file_button = |t, h| Engine.element("ui-file-button", [Engine.on_files(Change, h)], [Engine.text(t)])

	## A bordered area showing `t` that takes files dropped from the Finder;
	## `handler` receives them as handles in a `drop` event.
	drop_zone : Str, Engine.FilesHandler(ctx) -> Elem(ctx)
	drop_zone = |t, h| Engine.element("ui-drop-zone", [Engine.on_files(Drop, h)], [Engine.text(t)])

	## A horizontal separator line.
	divider : () -> Elem(ctx)
	divider = || Engine.element("ui-divider", [], [])

	## Empty space that grows to fill its stack.
	spacer : () -> Elem(ctx)
	spacer = || Engine.element("ui-spacer", [], [])
}
