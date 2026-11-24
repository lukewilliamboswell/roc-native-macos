import Engine exposing [Elem, Handler, HandlerOf, Signal]

## Native macOS controls for the roc-signals engine.
##
## Each builder is an ordinary `Engine.element` with a native element name;
## the engine's command stream is unchanged. The Swift host
## (`../host/Views.swift`) reads these names and builds the AppKit view each
## one stands for. Nothing here is HTML: there is no document, no CSS and no
## browser.
##
## Every builder takes its subject first (a text, a value, a selection) and a
## props record of defaulted fields beside it; containers take their props
## first and their children last:
##
## ```roc
## Ui.vstack({ spacing: 12, align: Fill }, [
##     Ui.text("Saved", { style: Caption1, color: SecondaryLabel }),
##     Ui.button("Save", { on_press: saved, role: Default }),
## ])
## ```
##
## State is a signal; looks are values. A field that holds what a control
## shows (its text, value, checked state, `enabled`) is a `Signal`, and a text
## literal already is one. A field that says how it looks is a plain value.
## When a look must follow state, the `_s` form of a look-only builder
## (`text_s`, `vstack_s`, `hstack_s`, `box_s`, `image_s`) takes the whole props
## record as a signal.
##
## | Builder | Element | AppKit view |
## |---|---|---|
## | `vstack`, `hstack`, `form` | `ui-vstack`, `ui-hstack`, `ui-form` | `NSStackView` |
## | `box` | `ui-box` | a view drawing a fill, border and corners around one child |
## | `scroll` | `ui-scroll` | `NSScrollView` around a vertical `NSStackView` |
## | `list`, `table_list`, `row` | `ui-list`, `ui-row` | view-based `NSTableView`; each `ui-row` is a table row |
## | `text`, `text_s` | `ui-text` | `NSTextField` label |
## | `button`, `submit_button` | `ui-button` | `NSButton` |
## | `text_field` | `ui-text-field` | editable `NSTextField` |
## | `text_area` | `ui-text-area` | `NSTextView` in an `NSScrollView` |
## | `checkbox` | `ui-checkbox` | `NSButton` (checkbox) |
## | `slider` | `ui-slider` | `NSSlider` |
## | `dropdown` | `ui-dropdown` | `NSPopUpButton` |
## | `segmented`, `tabs` | `ui-segmented` | `NSSegmentedControl` (`tabs` adds an `Engine.switch`) |
## | `image`, `image_s` | `ui-image` | `NSImageView` of an SF Symbol |
## | `asset_image`, `asset_image_s` | `ui-asset-image` | a view drawing an image from the app's `assets/` |
## | `progress`, `busy` | `ui-progress` | `NSProgressIndicator` (bar) |
## | `shortcut` | `ui-shortcut` | none: a document key handler |
## | `file_button` | `ui-file-button` | `NSButton` opening an `NSOpenPanel` |
## | `drop_zone` | `ui-drop-zone` | a dashed drop target around one child |
## | `hover` | `ui-hover` | none: its child's view, hit-tested on each pointer move |
## | `surface` | `ui-surface` | one view drawing a scene with Core Graphics |
## | `overlay` | `ui-overlay` | a view holding a background and a foreground over it |
## | `divider` | `ui-divider` | `NSBox` separator |
## | `spacer` | `ui-spacer` | flexible empty `NSView` |
##
## Every prop crosses as one attribute, always sent, so its default lives
## only here; `docs/architecture.adoc` lists the attribute grammar.
Ui := [].{

	# --- Shared looks ---

	## A side of an element's frame. `Auto` is its natural size; `Fill` takes
	## the room its stack offers on that side (`FillAtLeast(n)` too, but never
	## less than `n` points); the others bound it, in points.
	Length : [Auto, Fill, FillAtLeast(U32), Fixed(U32), AtLeast(U32), AtMost(U32), Between({ min : U32, max : U32 })]

	## Which element gives way first when its row is too narrow: `Yield`
	## truncates or shrinks before its neighbours, `Resist` after them.
	Squeeze : [Standard, Yield, Resist]

	## Each edge of an inset, in points; name only those that are not zero.
	Edges := { top : U32 ?? 0, leading : U32 ?? 0, bottom : U32 ?? 0, trailing : U32 ?? 0 }

	## Space inside a container's edges: `All(12)`, `Axes({ horizontal: 12,
	## vertical: 4 })` or `Each({ top: 8 })`.
	Insets : [Zero, All(U32), Axes({ horizontal : U32, vertical : U32 }), Each(Edges)]

	## Where a vertical stack places its children across its width; `Fill`
	## stretches each to it.
	HorizontalAlign : [Leading, Center, Trailing, Fill]

	## Where a horizontal stack places its children across its height;
	## `Fill` stretches each to it.
	VerticalAlign : [Top, Center, Bottom, FirstBaseline, Fill]

	## How a stack shares out its length (NSStackView.Distribution).
	## `Gravity`, AppKit's default, packs children at the start.
	Distribution : [Gravity, Fill, FillEqually, FillProportionally, EqualSpacing, EqualCentering]

	## AppKit's text styles (NSFont.TextStyle), which follow the system font.
	TextStyle : [LargeTitle, Title1, Title2, Title3, Headline, Subheadline, Body, Callout, Footnote, Caption1, Caption2]

	## A text's point size: the text style's own, or a fixed size for a
	## display such as a large readout.
	FontSize : [Standard, Fixed(U32)]

	## A weight over the text style's; `Standard` keeps the style's own.
	Weight : [Standard, Light, Regular, Medium, Semibold, Bold, Heavy]

	## Figures: `MonospacedDigits` keeps a changing number from jiggling;
	## `Monospaced` sets every character in the fixed-pitch system face.
	Design : [Proportional, MonospacedDigits, Monospaced]

	## What text does when it does not fit its width.
	TextOverflow : [Clip, TruncateHead, TruncateMiddle, TruncateTail, Wrap, WrapUpTo(U32)]

	## How lines of text sit in their frame. `Natural` follows the language.
	TextAlign : [Natural, Leading, Center, Trailing, Justified]

	## A colour. The named ones are AppKit's semantic colours, which follow
	## light and dark mode, increased contrast and the user's accent colour.
	## `Adaptive` is the escape hatch: a `0xRRGGBB` for light windows and one
	## for dark ones, so a chosen colour is never wrong in either.
	Color : [
		Label,
		SecondaryLabel,
		TertiaryLabel,
		QuaternaryLabel,
		Accent,
		Link,
		PlaceholderText,
		Separator,
		WindowBackground,
		ControlBackground,
		UnderPageBackground,
		TextBackground,
		SelectedContentBackground,
		Red,
		Orange,
		Yellow,
		Green,
		Mint,
		Teal,
		Cyan,
		Blue,
		Indigo,
		Purple,
		Pink,
		Brown,
		Gray,
		Clear,
		Adaptive({ light : U32, dark : U32 }),
	]

	## A control's size (NSControl.ControlSize).
	ControlSize : [Mini, Small, Regular, Large]

	## How a button is drawn (NSButton.BezelStyle); `Borderless` draws only
	## its title or symbol.
	Bezel : [Push, FlexiblePush, Toolbar, AccessoryBar, Badge, Circular, SmallSquare, Borderless]

	## What a button means to its window: `Default` answers Return and is
	## drawn in the accent colour, `Cancel` answers Escape, `Destructive` is
	## drawn as destructive.
	ButtonRole : [Normal, Default, Cancel, Destructive]

	## An SF Symbol beside a control's title, by name (`"trash"`).
	Icon : [NoIcon, Symbol(Str)]

	## Whether a control shows its title. A `Hidden` title still names the
	## control to VoiceOver, so an icon-only button keeps one.
	TitleDisplay : [Visible, Hidden]

	## The line around a box: none, solid or dashed, in points.
	Border : [NoBorder, Line({ color : Color, width : U32 }), Dashed({ color : Color, width : U32 })]

	## An SF Symbol's scale relative to its text style.
	SymbolScale : [Small, Medium, Large]

	# --- Containers ---

	## How a vertical stack lays out its children.
	VStackProps := {
		spacing : U32 ?? 8,
		padding : Insets ?? Zero,
		align : HorizontalAlign ?? Leading,
		distribution : Distribution ?? Gravity,
		width : Length ?? Auto,
		height : Length ?? Auto,
		squeeze : Squeeze ?? Standard,
	}

	## Children laid out top to bottom: `Ui.vstack({ spacing: 12, align: Fill }, kids)`,
	## or `Ui.vstack({}, kids)` for the defaults.
	vstack : VStackProps, List(Elem(ctx)) -> Elem(ctx)
	vstack = |props, kids| vstack_s(Engine.const(props), kids)

	## A vertical stack whose layout follows a signal.
	vstack_s : Signal(ctx, VStackProps), List(Elem(ctx)) -> Elem(ctx)
	vstack_s = |props, kids|
		Engine.element(
			"ui-vstack",
			[
				look("spacing", props, |p| p.spacing.to_str()),
				look("padding", props, |p| insets_word(p.padding)),
				look("align", props, |p| horizontal_align_word(p.align)),
				look("distribution", props, |p| distribution_word(p.distribution)),
			].concat(frame_attrs(props.map(|p| { width: p.width, height: p.height, squeeze: p.squeeze }))),
			kids,
		)

	## How a horizontal stack lays out its children.
	HStackProps := {
		spacing : U32 ?? 8,
		padding : Insets ?? Zero,
		align : VerticalAlign ?? Center,
		distribution : Distribution ?? Gravity,
		width : Length ?? Auto,
		height : Length ?? Auto,
		squeeze : Squeeze ?? Standard,
	}

	## Children laid out leading to trailing.
	hstack : HStackProps, List(Elem(ctx)) -> Elem(ctx)
	hstack = |props, kids| hstack_s(Engine.const(props), kids)

	## A horizontal stack whose layout follows a signal.
	hstack_s : Signal(ctx, HStackProps), List(Elem(ctx)) -> Elem(ctx)
	hstack_s = |props, kids| Engine.element("ui-hstack", horizontal_attrs(props), kids)

	## A form: a vertical stack whose `on_submit` runs when Return is pressed
	## in one of its text fields, or its `submit_button` is clicked.
	FormProps(ctx) := {
		on_submit : Handler(ctx),
		spacing : U32 ?? 8,
		padding : Insets ?? Zero,
		align : HorizontalAlign ?? Leading,
		width : Length ?? Auto,
		height : Length ?? Auto,
		squeeze : Squeeze ?? Standard,
	}

	## Children laid out top to bottom, submitted together.
	form : FormProps(ctx), List(Elem(ctx)) -> Elem(ctx)
	form = |props, kids| {
		layout = Engine.const({ spacing: props.spacing, padding: props.padding, align: props.align, width: props.width, height: props.height, squeeze: props.squeeze })
		Engine.element(
			"ui-form",
			[
				look("spacing", layout, |p| p.spacing.to_str()),
				look("padding", layout, |p| insets_word(p.padding)),
				look("align", layout, |p| horizontal_align_word(p.align)),
				Engine.attr("distribution", "gravity"),
				Engine.on("submit", props.on_submit),
			].concat(frame_attrs(layout.map(|p| { width: p.width, height: p.height, squeeze: p.squeeze }))),
			kids,
		)
	}

	## A surface around one child: a fill, a border and rounded corners,
	## with `padding` between them and the child.
	BoxProps := {
		fill : Color ?? ControlBackground,
		border : Border ?? NoBorder,
		radius : U32 ?? 8,
		padding : Insets ?? All(12),
		width : Length ?? Auto,
		height : Length ?? Auto,
		squeeze : Squeeze ?? Standard,
	}

	## A surface around `content`: `Ui.box({}, Ui.vstack({}, kids))`.
	box : BoxProps, Elem(ctx) -> Elem(ctx)
	box = |props, content| box_s(Engine.const(props), content)

	## A surface whose look follows a signal, such as a status badge.
	box_s : Signal(ctx, BoxProps), Elem(ctx) -> Elem(ctx)
	box_s = |props, content|
		Engine.element(
			"ui-box",
			[
				look("fill", props, |p| color_word(p.fill)),
				look("border", props, |p| border_word(p.border)),
				look("radius", props, |p| p.radius.to_str()),
				look("padding", props, |p| insets_word(p.padding)),
			].concat(frame_attrs(props.map(|p| { width: p.width, height: p.height, squeeze: p.squeeze }))),
			[content],
		)

	## A scroll area. It opens `opening_height` points high (the window opens
	## to fit it) and from then on the window decides its height, within
	## `height`. A window holding a scroll area or a list stops growing to
	## fit its content: the scroll area takes the slack.
	ScrollProps := {
		opening_height : U32 ?? 240,
		height : Length ?? AtLeast(80),
		width : Length ?? Fill,
		spacing : U32 ?? 8,
		padding : Insets ?? Zero,
	}

	## A vertically scrolling area holding `content` top to bottom; each of
	## its elements fills the area's width. `content` may be several
	## elements, such as the rows of an `Engine.table_view`.
	scroll : ScrollProps, Elem(ctx) -> Elem(ctx)
	scroll = |props, content|
		Engine.element(
			"ui-scroll",
			[
				Engine.attr("opening-height", props.opening_height.to_str()),
				Engine.attr("spacing", props.spacing.to_str()),
				Engine.attr("padding", insets_word(props.padding)),
			].concat(frame_attrs(Engine.const({ width: props.width, height: props.height, squeeze: Standard }))),
			[content],
		)

	## A list's opening height, and the bounds the window may then size it
	## within, in points.
	ListProps := {
		opening_height : U32 ?? 320,
		height : Length ?? AtLeast(120),
		width : Length ?? FillAtLeast(240),
	}

	## A scrolling table whose rows are the elements of `rows`: an
	## `Engine.table_view` (or `each`) of `row`s. AppKit draws only the rows
	## on screen, each row the engine inserts, removes or moves is one
	## incremental change to the table, and a row's views are made when it
	## is first scrolled into sight; but the engine draws every row in the
	## view's window. For the rows of a table, `table_list` draws only
	## those near the visible ones.
	list : ListProps, Elem(ctx) -> Elem(ctx)
	list = |props, rows|
		Engine.element(
			"ui-list",
			[Engine.attr("opening-height", props.opening_height.to_str())].concat(frame_attrs(Engine.const({ width: props.width, height: props.height, squeeze: Standard }))),
			[rows],
		)

	## What a `table_list` shows of its table: an `Engine.table_view`'s
	## `query` and `plan`, without the window, which the list keeps.
	ListView(ctx, q, k, v, s) : { query : Signal(ctx, q), plan : (q -> Engine.QueryPlan(k, v, s)) }

	## A `list` of the rows of a table, as `list` of an `Engine.table_view`,
	## that draws only the rows around those in sight: the list keeps the
	## view's window itself and moves it as the user scrolls, and the table
	## is sized for every row the query keeps. Mounting it, holding it and a
	## filter that lets many rows in or out cost the rows drawn (a screenful
	## or two), not the table; a row scrolled into sight is drawn then. The
	## template's context is the list's (`Engine.In(ctx, Engine.Window)`);
	## cells read and write there as anywhere, and a signal of the enclosing
	## context enters with `lift`.
	##
	## ```roc
	## Ui.table_list({}, cells.contacts, { query: cells.search.signal(), plan }, |key, contact| row(key, contact))
	## ```
	table_list : ListProps, Engine.Cell(st, Engine.Table(k, v)), ListView(Engine.In(ctx, Engine.Window), q, k, v, s), (Signal(Engine.Row(Engine.In(ctx, Engine.Window), k), k), Engine.State(Engine.Row(Engine.In(ctx, Engine.Window), k), v) -> Elem(Engine.Row(Engine.In(ctx, Engine.Window), k))) -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, st), k.is_eq : k, k -> Bool, k.to_hash : k, Hasher -> Hasher, q.is_eq : q, q -> Bool]
	table_list = |props, table, view, template|
		Engine.state(
			first_window,
			|window|
				Engine.element(
					"ui-list",
					[
						Engine.attr("opening-height", props.opening_height.to_str()),
						Engine.attr_s("window-start", window.signal().map(|w| w.start.to_str())),
						Engine.on("window", window.set_value(|_, asked| window_of(asked) ?? crash "Ui.table_list: the host asked for the window \"${asked}\", not \"start count\"")),
					].concat(frame_attrs(Engine.const({ width: props.width, height: props.height, squeeze: Standard }))),
					[Engine.table_view_counted(table, { query: view.query, plan: view.plan, window: window.signal() }, "view-rows", template)],
				),
		)

	## One row of a `list`; `on_select` runs when the user selects it.
	RowProps(ctx) := {
		on_select : Handler(ctx),
		spacing : U32 ?? 8,
		padding : Insets ?? Zero,
		align : VerticalAlign ?? Center,
	}

	## One row of a `list`: its children laid out leading to trailing.
	row : RowProps(ctx), List(Elem(ctx)) -> Elem(ctx)
	row = |props, kids|
		Engine.element(
			"ui-row",
			horizontal_attrs(Engine.const({ spacing: props.spacing, padding: props.padding, align: props.align, distribution: Gravity, width: Fill, height: Auto, squeeze: Standard }))
				.append(Engine.on("select", props.on_select)),
			kids,
		)

	# --- Text ---

	## How a piece of text looks.
	TextProps := {
		style : TextStyle ?? Body,
		size : FontSize ?? Standard,
		weight : Weight ?? Standard,
		design : Design ?? Proportional,
		color : Color ?? Label,
		overflow : TextOverflow ?? TruncateTail,
		align : TextAlign ?? Natural,
		width : Length ?? Auto,
		height : Length ?? Auto,
		squeeze : Squeeze ?? Standard,
	}

	## Text: `Ui.text("To-do", { style: Title1 })`. A literal is constant;
	## `"${count} left"` or a mapped signal follows its value.
	text : Signal(ctx, Str), TextProps -> Elem(ctx)
	text = |content, props| text_s(content, Engine.const(props))

	## Text whose look follows a signal:
	## `Ui.text_s(total, over.map(|o| if (o) { color: Red } else {}))`.
	text_s : Signal(ctx, Str), Signal(ctx, TextProps) -> Elem(ctx)
	text_s = |content, props|
		Engine.element(
			"ui-text",
			[
				look("text-style", props, |p| text_style_word(p.style)),
				look("font-size", props, |p| font_size_word(p.size)),
				look("weight", props, |p| weight_word(p.weight)),
				look("design", props, |p| design_word(p.design)),
				look("color", props, |p| color_word(p.color)),
				look("overflow", props, |p| overflow_word(p.overflow)),
				look("text-align", props, |p| text_align_word(p.align)),
			].concat(frame_attrs(props.map(|p| { width: p.width, height: p.height, squeeze: p.squeeze }))),
			[Engine.text_s(content)],
		)

	# --- Controls ---

	## A button: `on_press` runs when it is clicked.
	ButtonProps(ctx) := {
		on_press : HandlerOf(ctx, Engine.Click),
		enabled : Signal(ctx, Bool) ?? Engine.const(Bool.True),
		bezel : Bezel ?? Push,
		role : ButtonRole ?? Normal,
		icon : Icon ?? NoIcon,
		title_display : TitleDisplay ?? Visible,
		size : ControlSize ?? Regular,
		width : Length ?? Auto,
		height : Length ?? Auto,
		squeeze : Squeeze ?? Standard,
	}

	## A button titled `title`: `Ui.button("Save", { on_press: saved })`.
	button : Signal(ctx, Str), ButtonProps(ctx) -> Elem(ctx)
	button = |title, props|
		Engine.element(
			"ui-button",
			[
				Engine.attr("role", role_word(props.role)),
				Engine.on_click(props.on_press),
			]
				.concat(button_attrs({ enabled: props.enabled, bezel: props.bezel, icon: props.icon, title_display: props.title_display, size: props.size }))
				.concat(frame_attrs(Engine.const({ width: props.width, height: props.height, squeeze: props.squeeze }))),
			[Engine.text_s(title)],
		)

	## A form's submit button.
	SubmitProps(ctx) := {
		enabled : Signal(ctx, Bool) ?? Engine.const(Bool.True),
		bezel : Bezel ?? Push,
		icon : Icon ?? NoIcon,
		title_display : TitleDisplay ?? Visible,
		size : ControlSize ?? Regular,
		width : Length ?? Auto,
		height : Length ?? Auto,
		squeeze : Squeeze ?? Standard,
	}

	## The window's default button, which submits its enclosing `form`:
	## Return presses it.
	submit_button : Signal(ctx, Str), SubmitProps(ctx) -> Elem(ctx)
	submit_button = |title, props|
		Engine.element(
			"ui-button",
			[Engine.attr("role", "default"), Engine.attr("submit", "")]
				.concat(button_attrs({ enabled: props.enabled, bezel: props.bezel, icon: props.icon, title_display: props.title_display, size: props.size }))
				.concat(frame_attrs(Engine.const({ width: props.width, height: props.height, squeeze: props.squeeze }))),
			[Engine.text_s(title)],
		)

	## A single-line text field; `on_input` receives the text on every edit.
	TextFieldProps(ctx) := {
		on_input : Handler(ctx),
		placeholder : Str ?? "",
		enabled : Signal(ctx, Bool) ?? Engine.const(Bool.True),
		bezel : [Square, Rounded] ?? Square,
		size : ControlSize ?? Regular,
		width : Length ?? AtLeast(220),
		height : Length ?? Auto,
		squeeze : Squeeze ?? Standard,
	}

	## An editable single-line text field showing `value`.
	text_field : Signal(ctx, Str), TextFieldProps(ctx) -> Elem(ctx)
	text_field = |value, props|
		Engine.element(
			"ui-text-field",
			[
				Engine.attr_s("value", value),
				Engine.attr("placeholder", props.placeholder),
				Engine.attr_s("enabled", props.enabled.map(bool_word)),
				Engine.attr(
					"bezel",
					match props.bezel {
						Square => "square"
						Rounded => "rounded"
					},
				),
				Engine.attr("size", control_size_word(props.size)),
				Engine.on("input", props.on_input),
			].concat(frame_attrs(Engine.const({ width: props.width, height: props.height, squeeze: props.squeeze }))),
			[],
		)

	## A multi-line text area; `on_input` receives the whole text on every edit.
	TextAreaProps(ctx) := {
		on_input : Handler(ctx),
		design : Design ?? Proportional,
		width : Length ?? FillAtLeast(220),
		height : Length ?? AtLeast(96),
	}

	## An editable multi-line text area showing `value`.
	text_area : Signal(ctx, Str), TextAreaProps(ctx) -> Elem(ctx)
	text_area = |value, props|
		Engine.element(
			"ui-text-area",
			[Engine.attr_s("value", value), Engine.attr("design", design_word(props.design)), Engine.on("input", props.on_input)].concat(frame_attrs(Engine.const({ width: props.width, height: props.height, squeeze: Standard }))),
			[],
		)

	## A checkbox; `on_change` receives its new state.
	CheckboxProps(ctx) := {
		checked : Signal(ctx, Bool),
		on_change : HandlerOf(ctx, Bool),
		enabled : Signal(ctx, Bool) ?? Engine.const(Bool.True),
		title_display : TitleDisplay ?? Visible,
		size : ControlSize ?? Regular,
		width : Length ?? Auto,
		squeeze : Squeeze ?? Standard,
	}

	## A checkbox titled `title`.
	checkbox : Signal(ctx, Str), CheckboxProps(ctx) -> Elem(ctx)
	checkbox = |title, props|
		Engine.element(
			"ui-checkbox",
			[
				Engine.attr_s("title", title),
				Engine.attr_s("checked", props.checked.map(bool_word)),
				Engine.attr_s("enabled", props.enabled.map(bool_word)),
				Engine.attr("title-display", title_display_word(props.title_display)),
				Engine.attr("size", control_size_word(props.size)),
				Engine.on_checked(props.on_change),
			].concat(frame_attrs(Engine.const({ width: props.width, height: Auto, squeeze: props.squeeze }))),
			[],
		)

	## A slider over `range`; `on_input` receives the new whole value as
	## text while it is dragged.
	SliderProps(ctx) := {
		range : { min : I64, max : I64 },
		on_input : Handler(ctx),
		enabled : Signal(ctx, Bool) ?? Engine.const(Bool.True),
		size : ControlSize ?? Regular,
		width : Length ?? AtLeast(220),
		squeeze : Squeeze ?? Standard,
	}

	## A horizontal slider following `value`.
	slider : Signal(ctx, I64), SliderProps(ctx) -> Elem(ctx)
	slider = |value, props|
		Engine.element(
			"ui-slider",
			[
				Engine.attr("min", props.range.min.to_str()),
				Engine.attr("max", props.range.max.to_str()),
				Engine.attr_s("value", value.map(|n| n.to_str())),
				Engine.attr_s("enabled", props.enabled.map(bool_word)),
				Engine.attr("size", control_size_word(props.size)),
				Engine.on("input", props.on_input),
			].concat(frame_attrs(Engine.const({ width: props.width, height: Auto, squeeze: props.squeeze }))),
			[],
		)

	## A choice among `choices`; `on_change` receives the chosen title.
	ChoiceProps(ctx) := {
		choices : List(Str),
		on_change : Handler(ctx),
		enabled : Signal(ctx, Bool) ?? Engine.const(Bool.True),
		size : ControlSize ?? Regular,
		width : Length ?? Auto,
		squeeze : Squeeze ?? Standard,
	}

	## A pop-up menu showing `selected`.
	dropdown : Signal(ctx, Str), ChoiceProps(ctx) -> Elem(ctx)
	dropdown = |selected, props| Engine.element("ui-dropdown", choice_attrs(selected, props), [])

	## A segmented control showing `selected`.
	segmented : Signal(ctx, Str), ChoiceProps(ctx) -> Elem(ctx)
	segmented = |selected, props| Engine.element("ui-segmented", choice_attrs(selected, props), [])

	## Tabs: a segmented control of `choices` above `page(name)` for the
	## selected one. Only the shown page is built; switching disposes the
	## old page with any state inside it (`Engine.switch`).
	TabsProps(ctx) := {
		choices : List(Str),
		on_change : Handler(ctx),
		page : Str -> Elem(ctx),
		spacing : U32 ?? 16,
		size : ControlSize ?? Regular,
	}

	## Tabs showing `selected`.
	tabs : Signal(ctx, Str), TabsProps(ctx) -> Elem(ctx)
	tabs = |selected, props|
		vstack(
			{ spacing: props.spacing, align: Fill },
			[
				hstack({ width: Fill }, [spacer(), segmented(selected, { choices: props.choices, on_change: props.on_change, size: props.size }), spacer()]),
				Engine.switch(selected, props.choices, props.page),
			],
		)

	## How an SF Symbol is drawn: its colour, and its size as the text style
	## it sits beside, at a scale.
	ImageProps := {
		color : Color ?? Label,
		style : TextStyle ?? Body,
		scale : SymbolScale ?? Medium,
		width : Length ?? Auto,
		height : Length ?? Auto,
		squeeze : Squeeze ?? Standard,
	}

	## An SF Symbol by name: `Ui.image("star.fill", { color: Yellow })`.
	image : Str, ImageProps -> Elem(ctx)
	image = |symbol, props| image_s(symbol, Engine.const(props))

	## An SF Symbol whose look follows a signal.
	image_s : Str, Signal(ctx, ImageProps) -> Elem(ctx)
	image_s = |symbol, props|
		Engine.element(
			"ui-image",
			[
				Engine.attr("symbol", symbol),
				look("color", props, |p| color_word(p.color)),
				look("text-style", props, |p| text_style_word(p.style)),
				look("scale", props, |p| symbol_scale_word(p.scale)),
			].concat(frame_attrs(props.map(|p| { width: p.width, height: p.height, squeeze: p.squeeze }))),
			[],
		)

	## How an image fits a frame of another shape: `Fit` shows all of it,
	## `Fill` covers the frame and crops what overflows, `Stretch` distorts
	## it to the frame, and `Original` draws it at its own size, centred and
	## clipped.
	ImageScaling : [Fit, Fill, Stretch, Original]

	## How an image from the app's assets is drawn. Its natural size is the
	## image's own, in points; bound one side and the other follows the
	## image's aspect ratio, bound both and `scaling` fits it. `label` names
	## it to VoiceOver; without one it is decorative and VoiceOver skips it.
	AssetImageProps := {
		label : Str ?? "",
		scaling : ImageScaling ?? Fit,
		width : Length ?? Auto,
		height : Length ?? Auto,
		squeeze : Squeeze ?? Standard,
	}

	## An image from the app's `assets/` directory, by its path there:
	## `Ui.asset_image("logo.png", { width: Fixed(64), label: "Logo" })`.
	## PNG, JPEG, PDF or any other file AppKit reads as an image. A name that
	## is not in `assets/` stops the app with an error naming it.
	asset_image : Signal(ctx, Str), AssetImageProps -> Elem(ctx)
	asset_image = |name, props| asset_image_s(name, Engine.const(props))

	## An image from the app's assets whose look follows a signal.
	asset_image_s : Signal(ctx, Str), Signal(ctx, AssetImageProps) -> Elem(ctx)
	asset_image_s = |name, props|
		Engine.element(
			"ui-asset-image",
			[
				Engine.attr_s("asset", name),
				look("label", props, |p| p.label),
				look("scaling", props, |p| image_scaling_word(p.scaling)),
			].concat(frame_attrs(props.map(|p| { width: p.width, height: p.height, squeeze: p.squeeze }))),
			[],
		)

	## A progress bar's range and size.
	ProgressProps := {
		max : I64 ?? 100,
		size : ControlSize ?? Regular,
		width : Length ?? FillAtLeast(160),
	}

	## A determinate progress bar from 0 to `max` following `value`.
	progress : Signal(ctx, I64), ProgressProps -> Elem(ctx)
	progress = |value, props|
		Engine.element(
			"ui-progress",
			[
				Engine.attr("max", props.max.to_str()),
				Engine.attr_s("value", value.map(|n| n.to_str())),
				Engine.attr("size", control_size_word(props.size)),
			].concat(frame_attrs(Engine.const({ width: props.width, height: Auto, squeeze: Standard }))),
			[],
		)

	## A busy indicator's size.
	BusyProps := {
		size : ControlSize ?? Regular,
		width : Length ?? FillAtLeast(160),
	}

	## An indeterminate progress bar, animating while `active` is true.
	busy : Signal(ctx, Bool), BusyProps -> Elem(ctx)
	busy = |active, props|
		Engine.element(
			"ui-progress",
			[
				Engine.attr("indeterminate", ""),
				Engine.attr_s("value", active.map(|on| if (on) "1" else "0")),
				Engine.attr("size", control_size_word(props.size)),
			].concat(frame_attrs(Engine.const({ width: props.width, height: Auto, squeeze: Standard }))),
			[],
		)

	## A shortcut's handler.
	ShortcutProps(ctx) := { on_key : HandlerOf(ctx, Engine.Key) }

	## A window-wide keyboard shortcut: `on_key` runs when a key matching
	## one of `chords` is pressed and no control's own key handler heard it.
	## The key's default is prevented. Compare the payload's `heard` with a
	## chord to tell several apart:
	## `Ui.shortcut([Ui.command("n")], { on_key: Engine.handle(|_key| ...) })`.
	shortcut : List(Engine.Chord), ShortcutProps(ctx) -> Elem(ctx)
		where [ctx.outside_rows : () -> Engine.OutsideRows(ctx)]
	shortcut = |chords, props|
		Engine.element("ui-shortcut", [Engine.on_document_key({ keymap: Engine.const(Engine.Keymap.prevent(chords)) }, props.on_key)], [])

	## The chord of Command and `key` (a lower-case letter, or a key name
	## such as `"Enter"`).
	command : Str -> Engine.Chord
	command = |key| Engine.Chord.plain(key).with_meta()

	## The chord of `key` with no modifiers, such as `"Escape"`.
	plain_key : Str -> Engine.Chord
	plain_key = |key| Engine.Chord.plain(key)

	## A button that opens an open panel (several files may be chosen).
	FileButtonProps(ctx) := {
		on_files : Engine.FilesHandler(ctx),
		bezel : Bezel ?? Push,
		icon : Icon ?? NoIcon,
		title_display : TitleDisplay ?? Visible,
		size : ControlSize ?? Regular,
		width : Length ?? Auto,
		squeeze : Squeeze ?? Standard,
	}

	## A button titled `title` that opens an open panel; `on_files`
	## receives the chosen files as handles, never their bytes, in a
	## `change` event. Read them with `Engine.read_utf8`, `Engine.sha256` and
	## the other file requests.
	file_button : Signal(ctx, Str), FileButtonProps(ctx) -> Elem(ctx)
	file_button = |title, props|
		Engine.element(
			"ui-file-button",
			[Engine.attr("role", "normal"), Engine.on_files(Change, props.on_files)]
				.concat(button_attrs({ enabled: Engine.const(Bool.True), bezel: props.bezel, icon: props.icon, title_display: props.title_display, size: props.size }))
				.concat(frame_attrs(Engine.const({ width: props.width, height: Auto, squeeze: props.squeeze }))),
			[Engine.text_s(title)],
		)

	## A drop target: a dashed outline, accent while files are dragged over.
	DropZoneProps(ctx) := {
		on_drop : Engine.FilesHandler(ctx),
		padding : Insets ?? All(16),
		radius : U32 ?? 10,
		width : Length ?? Fill,
		height : Length ?? Auto,
	}

	## A drop target around `content` that takes files dropped from the
	## Finder; `on_drop` receives them as handles in a `drop` event.
	drop_zone : DropZoneProps(ctx), Elem(ctx) -> Elem(ctx)
	drop_zone = |props, content|
		Engine.element(
			"ui-drop-zone",
			[
				Engine.attr("padding", insets_word(props.padding)),
				Engine.attr("radius", props.radius.to_str()),
				Engine.on_files(Drop, props.on_drop),
			].concat(frame_attrs(Engine.const({ width: props.width, height: props.height, squeeze: Standard }))),
			[content],
		)

	## What the pointer passing over an element does.
	HoverProps(ctx) := { on_hover : HandlerOf(ctx, Bool) }

	## `content`, hearing the pointer: `on_hover` receives `True` when the
	## pointer enters it and `False` when it leaves it or the window. Hovers
	## nest: an outer one stays entered while the pointer is over an inner
	## one. It adds no view: `content` keeps its place and its frame.
	## `Ui.hover({ on_hover: Engine.handle(|inside| [cells.hot.set(inside)]) }, Ui.box_s(look, Ui.text("Hover me", {})))`.
	hover : HoverProps(ctx), Elem(ctx) -> Elem(ctx)
	hover = |props, content|
		Engine.element(
			"ui-hover",
			[Engine.on("hover", props.on_hover.from_payload_by(Engine.const({}), |_, word| word == "enter"))],
			[content],
		)

	# --- Drawing ---

	## A point of a surface's scene, in its `space`'s units.
	Point : { x : F64, y : F64 }

	## A rectangle of a scene: its top-left corner and its size.
	Area : { x : F64, y : F64, width : F64, height : F64 }

	## A number in a scene: a constant, the latest scalar of the native
	## source named `source` (`Source`), or the value at `index` (from 0) of
	## its latest series (`Element`), as `offset + scale * value`. A source
	## that is not registered, or has nothing yet, and an index past the end
	## of the series, count as 0, so the number is `offset`.
	Number : [
		Value(F64),
		Source({ source : Str, scale : F64, offset : F64 }),
		Element({ source : Str, index : U64, scale : F64, offset : F64 }),
	]

	## One step of a `Path`, from where the last one ended.
	Segment : [MoveTo(Point), LineTo(Point), QuadTo(Point, Point), CurveTo(Point, Point, Point), Close]

	## A shape. `Wave`, `Ring` and `Bars` draw the latest series of the
	## native source named `source`: each value `v` counts as
	## `(v - low) / (high - low)`, 0 at `low` and 1 at `high`. `Wave` is a
	## polyline across `area`, its first value at the left edge, its last at
	## the right, 0 on the bottom edge and 1 on the top. `Ring` is a closed
	## polyline around (`x`, `y`), the first value at the top and the rest
	## clockwise, each `radius + depth * t` from the centre. `Bars` divides
	## `area` into one column per value, `gap` apart, each bar rising from the
	## bottom edge to `t` of the height. A source that is not registered, or
	## has nothing yet, draws nothing.
	Shape : [
		Rect(Area),
		Oval(Area),
		Polyline(List(Point)),
		Polygon(List(Point)),
		Path(List(Segment)),
		Wave({ source : Str, area : Area, low : F64, high : F64 }),
		Ring({ source : Str, x : F64, y : F64, radius : F64, depth : F64, low : F64, high : F64 }),
		Bars({ source : Str, area : Area, low : F64, high : F64, gap : F64 }),
	]

	## How a shape's outline is drawn: its colour and its line width, in the
	## scene's units, with round joins and caps. The width is a `Number`, so
	## a source can drive it; a width below 0 draws as 0, so nothing.
	Pen : { color : Color, width : Number }

	## One step of a surface's scene, drawn in order, as a canvas draws.
	## `Fill` and `Stroke` draw a shape; `Translate`, `Rotate` (radians,
	## clockwise), `Scale` and `Matrix` (`x' = a x + c y + tx`, `y' = b x + d y
	## + ty`) move what is drawn after them, and `Opacity` multiplies its
	## opacity; `Save` keeps the current transform and opacity, and the
	## matching `Restore` returns to them.
	Mark : [
		Fill(Shape, Color),
		Stroke(Shape, Pen),
		Save,
		Restore,
		Translate(Number, Number),
		Rotate(Number),
		Scale(Number, Number),
		Matrix({ a : F64, b : F64, c : F64, d : F64, tx : F64, ty : F64 }),
		Opacity(Number),
	]

	## A scene's units. `Points`: one unit is one point, from the surface's
	## top-left corner, y down. `Fit({ width, height })`: a `width` by
	## `height` scene scaled, without distortion, to the largest size that
	## fits the surface, and centred in it, so it follows the surface as it
	## resizes.
	Space : [Points, Fit({ width : F64, height : F64 })]

	## When a surface draws a new frame. `OnDemand`: when its scene, look or
	## size changes, or a source it reads says it changed. `Display`: at
	## every refresh of its display, while it is in a window and not hidden,
	## reading its native sources each time without a turn of the engine; a
	## change of scene, look or size shows from the next refresh.
	Pacing : [OnDemand, Display]

	## Each new frame first draws the previous one beneath it (`Trail`), or
	## not. `half_life_ms` is how long the old picture takes to fade to half
	## its opacity; `zoom` is how much it grows each second (1 for none),
	## `turn` how far it turns each second (radians, clockwise), both about
	## the surface's centre, and `shift` how far it moves each second, in
	## points. All four are rates, so a trail lasts as long at any refresh
	## rate.
	Trail : [NoTrail, Trail({ half_life_ms : F64, zoom : F64, turn : F64, shift : Point })]

	## A surface's own GPU shaders, in two stages (docs/ui.adoc, "Shaders").
	## Each is Metal Shading Language source defining one function,
	## `float4 warp(Frame f, Params p)` or `float4 composite(Frame f, Params p)`,
	## and any helpers above it; the host supplies the header (`Frame`,
	## `Params` and the helpers) and the entry point around it.
	##
	## Each frame, `warp` makes the new frame from the previous one (`f.image`)
	## in place of the trail, the scene's marks are drawn over it, and the
	## result is the next frame's `f.image`. `composite` then maps that frame
	## (its `f.image`) to the screen without feeding back. With `composite`
	## alone, the frame under it is the scene over the background (and the
	## trail, if there is one), drawn fresh.
	##
	## `params` name numbers the stages read as `p.NAME` (a `float`): each a
	## `Number`, so a native source can drive it, read once per frame in the
	## host without a turn of the engine. A name is lowercase letters, digits
	## and `_`, not starting with a digit, at most 32 bytes, and there are at
	## most 16.
	##
	## Shaders run only with the Metal renderer, on a display-paced surface.
	## Elsewhere the surface draws its marks and its trail, as without them:
	## `on_shader` reports which (`Fallback`).
	Shader : [NoShader, Shaders({ warp : [None, Some(Str)], composite : [None, Some(Str)], params : List((Str, Number)) })]

	## Which stage an error is in.
	ShaderStage : [Warp, Composite]

	## A compile error at the line and column of the stage's own source,
	## counting from 1; 0 for an error outside it (a missing function, too
	## long a source, a bad param name, the GPU stopping a frame).
	ShaderError : { stage : ShaderStage, line : U32, column : U32, message : Str }

	## What a surface's shaders are doing, reported by `on_shader` whenever
	## it changes: none asked for (`NoShader`); both stages compiled and
	## drawing (`Running`); drawing with Core Graphics, so the marks and the
	## trail alone (`Fallback`); or a stage that does not compile (`Failed`),
	## while the surface keeps drawing that stage's last good source, or none.
	ShaderStatus : [NoShader, Running, Fallback, Failed(List(ShaderError))]

	## How a drawing surface draws. `label` names it to VoiceOver. A change of
	## `reset` (any new value) clears the trail; it is also cleared when the
	## surface is first shown and whenever its size or backing scale changes.
	## `shader` adds GPU stages to it (`Shader`), and `on_shader`, when
	## `Handled(handler)`, hears what they are doing (`ShaderStatus`).
	SurfaceProps(ctx) := {
		label : Str,
		space : Signal(ctx, Space) ?? Engine.const(Points),
		background : Signal(ctx, Color) ?? Engine.const(Clear),
		pacing : Signal(ctx, Pacing) ?? Engine.const(OnDemand),
		trail : Signal(ctx, Trail) ?? Engine.const(NoTrail),
		reset : Signal(ctx, U64) ?? Engine.const(0),
		shader : Signal(ctx, Shader) ?? Engine.const(NoShader),
		on_shader : [Ignored, Handled(HandlerOf(ctx, ShaderStatus))] ?? Ignored,
		width : Length ?? Fill,
		height : Length ?? Fixed(160),
		squeeze : Squeeze ?? Standard,
	}

	## A drawing surface: one native view drawing `scene`, an ordered list of
	## marks, over `background`. A new scene redraws only this view, with no
	## view per shape and no layout pass.
	## `Ui.surface(points.map(|ps| [Stroke(Polyline(ps), { color: Green, width: Value(2) })]), { label: "Plot" })`.
	surface : Signal(ctx, List(Mark)), SurfaceProps(ctx) -> Elem(ctx)
	surface = |scene, props|
		Engine.element(
			"ui-surface",
			[
				Engine.attr("label", props.label),
				Engine.attr_s("space", props.space.map(space_word)),
				Engine.attr_s("background", props.background.map(color_word)),
				Engine.attr_s("pacing", props.pacing.map(pacing_word)),
				Engine.attr_s("trail", props.trail.map(trail_word)),
				Engine.attr_s("reset", props.reset.map(|n| n.to_str())),
				Engine.attr_s("shader-params", props.shader.map(shader_params_text)),
				Engine.attr_s("shader-warp", props.shader.map(|s| shader_source(s, Warp))),
				Engine.attr_s("shader-composite", props.shader.map(|s| shader_source(s, Composite))),
				Engine.attr_s("scene", scene.map(scene_text)),
			]
				.concat(
					match props.on_shader {
						Handled(handler) => [Engine.on("shader", handler.from_payload_by(Engine.const({}), |_, word| shader_status(word)))]
						Ignored => []
					},
				)
				.concat(frame_attrs(Engine.const({ width: props.width, height: props.height, squeeze: props.squeeze }))),
			[],
		)

	## Where an overlay places its foreground over its background, and how
	## far inside the background's edges.
	OverlayProps := {
		horizontal : HorizontalAlign ?? Fill,
		vertical : [Top, Center, Bottom, Fill] ?? Bottom,
		padding : Insets ?? All(16),
		width : Length ?? Fill,
		height : Length ?? Auto,
		squeeze : Squeeze ?? Standard,
	}

	## `foreground` over `background`, in its frame: the background (a
	## `surface`, say) fills the overlay and sizes it, and the foreground is
	## an ordinary native view tree, inside `padding`, that wraps, scrolls and
	## reads to VoiceOver as anywhere else, and never draws into a surface's
	## trail. `Ui.overlay({ vertical: Bottom }, plot, Ui.text(line, { overflow: Wrap, width: Fill }))`.
	overlay : OverlayProps, Elem(ctx), Elem(ctx) -> Elem(ctx)
	overlay = |props, background, foreground|
		Engine.element(
			"ui-overlay",
			[
				Engine.attr("horizontal", horizontal_align_word(props.horizontal)),
				Engine.attr(
					"vertical",
					match props.vertical {
						Top => "top"
						Center => "center"
						Bottom => "bottom"
						Fill => "fill"
					},
				),
				Engine.attr("padding", insets_word(props.padding)),
			].concat(frame_attrs(Engine.const({ width: props.width, height: props.height, squeeze: props.squeeze }))),
			[background, foreground],
		)

	## A horizontal separator line.
	divider : () -> Elem(ctx)
	divider = || Engine.element("ui-divider", [], [])

	## Empty space that grows to fill its stack.
	spacer : () -> Elem(ctx)
	spacer = || Engine.element("ui-spacer", [], [])
}

# --- Attribute encoding (private) ---

## An element's frame props.
Frame : { width : Ui.Length, height : Ui.Length, squeeze : Ui.Squeeze }

## The look props every button shares.
ButtonLook(ctx) : { enabled : Signal(ctx, Bool), bezel : Ui.Bezel, icon : Ui.Icon, title_display : Ui.TitleDisplay, size : Ui.ControlSize }

## One look attribute following `props` through `word`. A constant props
## signal maps to a constant, which the engine sends as a static attribute.
look : Engine.AttrName, Signal(ctx, p), (p -> Str) -> Engine.Attr(ctx)
look = |name, props, word| Engine.attr_s(name, props.map(word))

frame_attrs : Signal(ctx, Frame) -> List(Engine.Attr(ctx))
frame_attrs = |frame|
	[
		look("width", frame, |f| length_word(f.width)),
		look("height", frame, |f| length_word(f.height)),
		look("squeeze", frame, |f| squeeze_word(f.squeeze)),
	]

## A `table_list`'s window until the host first asks for one: more rows
## than a list opening at any height shows, so a list that fits them never
## moves its window.
first_window : Engine.Window
first_window = { start: 0, count: 100 }

## The window a list's host asks for, as `start count` (`window` event).
window_of : Str -> Try(Engine.Window, [BadWindow])
window_of = |asked|
	match Str.split_on(asked, " ") {
		[start, count] =>
			match (U64.from_str(start), U64.from_str(count)) {
				(Ok(s), Ok(c)) => Ok({ start: s, count: c })
				_ => Err(BadWindow)
			}
		_ => Err(BadWindow)
	}

expect window_of("40 120") == Ok({ start: 40, count: 120 })
expect window_of("40") == Err(BadWindow)

horizontal_attrs : Signal(ctx, Ui.HStackProps) -> List(Engine.Attr(ctx))
horizontal_attrs = |props|
	[
		look("spacing", props, |p| p.spacing.to_str()),
		look("padding", props, |p| insets_word(p.padding)),
		look("align", props, |p| vertical_align_word(p.align)),
		look("distribution", props, |p| distribution_word(p.distribution)),
	].concat(frame_attrs(props.map(|p| { width: p.width, height: p.height, squeeze: p.squeeze })))

button_attrs : ButtonLook(ctx) -> List(Engine.Attr(ctx))
button_attrs = |props|
	[
		Engine.attr_s("enabled", props.enabled.map(bool_word)),
		Engine.attr("bezel", bezel_word(props.bezel)),
		Engine.attr("icon", icon_word(props.icon)),
		Engine.attr("title-display", title_display_word(props.title_display)),
		Engine.attr("size", control_size_word(props.size)),
	]

choice_attrs : Signal(ctx, Str), Ui.ChoiceProps(ctx) -> List(Engine.Attr(ctx))
choice_attrs = |selected, props|
	[
		Engine.attr("choices", Str.join_with(props.choices, "\n")),
		Engine.attr_s("value", selected),
		Engine.attr_s("enabled", props.enabled.map(bool_word)),
		Engine.attr("size", control_size_word(props.size)),
		Engine.on("change", props.on_change),
	].concat(frame_attrs(Engine.const({ width: props.width, height: Auto, squeeze: props.squeeze })))

bool_word : Bool -> Str
bool_word = |on| if (on) "true" else "false"

length_word : Ui.Length -> Str
length_word = |length|
	match length {
		Auto => "auto"
		Fill => "fill"
		FillAtLeast(points) => "fill-at-least:${points.to_str()}"
		Fixed(points) => "fixed:${points.to_str()}"
		AtLeast(points) => "at-least:${points.to_str()}"
		AtMost(points) => "at-most:${points.to_str()}"
		Between({ min, max }) => "between:${min.to_str()}:${max.to_str()}"
	}

squeeze_word : Ui.Squeeze -> Str
squeeze_word = |squeeze|
	match squeeze {
		Standard => "standard"
		Yield => "yield"
		Resist => "resist"
	}

## Top, leading, bottom and trailing, in points.
insets_word : Ui.Insets -> Str
insets_word = |insets| {
	edges : { top : U32, leading : U32, bottom : U32, trailing : U32 }
	edges = match insets {
		Zero => { top: 0, leading: 0, bottom: 0, trailing: 0 }
		All(points) => { top: points, leading: points, bottom: points, trailing: points }
		Axes({ horizontal, vertical }) => { top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal }
		Each(each) => { top: each.top, leading: each.leading, bottom: each.bottom, trailing: each.trailing }
	}
	Str.join_with([edges.top, edges.leading, edges.bottom, edges.trailing].map(|n| n.to_str()), " ")
}

horizontal_align_word : Ui.HorizontalAlign -> Str
horizontal_align_word = |align|
	match align {
		Leading => "leading"
		Center => "center"
		Trailing => "trailing"
		Fill => "fill"
	}

vertical_align_word : Ui.VerticalAlign -> Str
vertical_align_word = |align|
	match align {
		Top => "top"
		Center => "center"
		Bottom => "bottom"
		FirstBaseline => "first-baseline"
		Fill => "fill"
	}

distribution_word : Ui.Distribution -> Str
distribution_word = |distribution|
	match distribution {
		Gravity => "gravity"
		Fill => "fill"
		FillEqually => "fill-equally"
		FillProportionally => "fill-proportionally"
		EqualSpacing => "equal-spacing"
		EqualCentering => "equal-centering"
	}

text_style_word : Ui.TextStyle -> Str
text_style_word = |style|
	match style {
		LargeTitle => "large-title"
		Title1 => "title1"
		Title2 => "title2"
		Title3 => "title3"
		Headline => "headline"
		Subheadline => "subheadline"
		Body => "body"
		Callout => "callout"
		Footnote => "footnote"
		Caption1 => "caption1"
		Caption2 => "caption2"
	}

font_size_word : Ui.FontSize -> Str
font_size_word = |size|
	match size {
		Standard => "standard"
		Fixed(points) => points.to_str()
	}

weight_word : Ui.Weight -> Str
weight_word = |weight|
	match weight {
		Standard => "standard"
		Light => "light"
		Regular => "regular"
		Medium => "medium"
		Semibold => "semibold"
		Bold => "bold"
		Heavy => "heavy"
	}

design_word : Ui.Design -> Str
design_word = |design|
	match design {
		Proportional => "proportional"
		MonospacedDigits => "monospaced-digits"
		Monospaced => "monospaced"
	}

overflow_word : Ui.TextOverflow -> Str
overflow_word = |overflow|
	match overflow {
		Clip => "clip"
		TruncateHead => "truncate-head"
		TruncateMiddle => "truncate-middle"
		TruncateTail => "truncate-tail"
		Wrap => "wrap"
		WrapUpTo(lines) => "wrap:${lines.to_str()}"
	}

text_align_word : Ui.TextAlign -> Str
text_align_word = |align|
	match align {
		Natural => "natural"
		Leading => "leading"
		Center => "center"
		Trailing => "trailing"
		Justified => "justified"
	}

color_word : Ui.Color -> Str
color_word = |color|
	match color {
		Label => "label"
		SecondaryLabel => "secondary-label"
		TertiaryLabel => "tertiary-label"
		QuaternaryLabel => "quaternary-label"
		Accent => "accent"
		Link => "link"
		PlaceholderText => "placeholder-text"
		Separator => "separator"
		WindowBackground => "window-background"
		ControlBackground => "control-background"
		UnderPageBackground => "under-page-background"
		TextBackground => "text-background"
		SelectedContentBackground => "selected-content-background"
		Red => "red"
		Orange => "orange"
		Yellow => "yellow"
		Green => "green"
		Mint => "mint"
		Teal => "teal"
		Cyan => "cyan"
		Blue => "blue"
		Indigo => "indigo"
		Purple => "purple"
		Pink => "pink"
		Brown => "brown"
		Gray => "gray"
		Clear => "clear"
		Adaptive({ light, dark }) => "adaptive:${hex6(light)}:${hex6(dark)}"
	}

## Six lowercase hexadecimal digits; a value above 0xffffff keeps its low 24 bits.
hex6 : U32 -> Str
hex6 = |value| {
	digits = "0123456789abcdef".to_utf8()
	nibbles = [0x100000.U32, 0x10000, 0x1000, 0x100, 0x10, 1].map(|place| ((value // place) % 16).to_u64())
	Str.from_utf8(nibbles.map(|n| digits.get(n) ?? '0')) ?? crash "Ui.hex6: hex digits are UTF-8"
}

control_size_word : Ui.ControlSize -> Str
control_size_word = |size|
	match size {
		Mini => "mini"
		Small => "small"
		Regular => "regular"
		Large => "large"
	}

bezel_word : Ui.Bezel -> Str
bezel_word = |bezel|
	match bezel {
		Push => "push"
		FlexiblePush => "flexible-push"
		Toolbar => "toolbar"
		AccessoryBar => "accessory-bar"
		Badge => "badge"
		Circular => "circular"
		SmallSquare => "small-square"
		Borderless => "borderless"
	}

role_word : Ui.ButtonRole -> Str
role_word = |role|
	match role {
		Normal => "normal"
		Default => "default"
		Cancel => "cancel"
		Destructive => "destructive"
	}

icon_word : Ui.Icon -> Str
icon_word = |icon|
	match icon {
		NoIcon => "none"
		Symbol(name) => "symbol:${name}"
	}

title_display_word : Ui.TitleDisplay -> Str
title_display_word = |display|
	match display {
		Visible => "visible"
		Hidden => "hidden"
	}

border_word : Ui.Border -> Str
border_word = |border|
	match border {
		NoBorder => "none"
		Line({ color, width }) => "line:${width.to_str()}:${color_word(color)}"
		Dashed({ color, width }) => "dashed:${width.to_str()}:${color_word(color)}"
	}

symbol_scale_word : Ui.SymbolScale -> Str
symbol_scale_word = |scale|
	match scale {
		Small => "small"
		Medium => "medium"
		Large => "large"
	}

image_scaling_word : Ui.ImageScaling -> Str
image_scaling_word = |scaling|
	match scaling {
		Fit => "fit"
		Fill => "fill"
		Stretch => "stretch"
		Original => "original"
	}

space_word : Ui.Space -> Str
space_word = |space|
	match space {
		Points => "points"
		Fit({ width, height }) => "fit ${num(width)} ${num(height)}"
	}

pacing_word : Ui.Pacing -> Str
pacing_word = |pacing|
	match pacing {
		OnDemand => "on-demand"
		Display => "display"
	}

trail_word : Ui.Trail -> Str
trail_word = |trail|
	match trail {
		NoTrail => "none"
		Trail({ half_life_ms, zoom, turn, shift }) => "trail ${num(half_life_ms)} ${num(zoom)} ${num(turn)} ${num(shift.x)} ${num(shift.y)}"
	}

## A stage's source, or empty for none.
shader_source : Ui.Shader, Ui.ShaderStage -> Str
shader_source = |shader, stage|
	match shader {
		NoShader => ""
		Shaders({ warp, composite, .. }) =>
			match (if (stage == Warp) warp else composite) {
				Some(source) => source
				None => ""
			}
	}

## The params, one `NAME NUMBER` a line, NUMBER as a scene's.
shader_params_text : Ui.Shader -> Str
shader_params_text = |shader|
	match shader {
		NoShader => ""
		Shaders({ params, .. }) => Str.join_with(params.map(|(name, number)| "${name} ${number_word(number)}"), "\n")
	}

## The `shader` event's payload: `none`, `running`, `fallback`, or `failed`
## and then one `STAGE LINE COLUMN MESSAGE` a line.
shader_status : Str -> Ui.ShaderStatus
shader_status = |word|
	match word.split_on("\n") {
		["running"] => Running
		["fallback"] => Fallback
		["failed", .. as lines] => Failed(lines.map(shader_error))
		_ => NoShader
	}

shader_error : Str -> Ui.ShaderError
shader_error = |line|
	match line.split_on(" ") {
		[stage, row, column, .. as words] =>
			{
				stage: if (stage == "composite") Composite else Warp,
				line: U32.from_str(row) ?? 0,
				column: U32.from_str(column) ?? 0,
				message: Str.join_with(words, " "),
			}
		_ => { stage: Warp, line: 0, column: 0, message: line }
	}

## A scene, one mark per line (docs/architecture.adoc, "Drawing surfaces").
scene_text : List(Ui.Mark) -> Str
scene_text = |marks| Str.join_with(marks.map(mark_line), "\n")

mark_line : Ui.Mark -> Str
mark_line = |mark|
	match mark {
		Fill(shape, color) => "fill ${color_word(color)} ${shape_words(shape)}"
		Stroke(shape, { color, width }) => "stroke ${color_word(color)} ${number_word(width)} ${shape_words(shape)}"
		Save => "save"
		Restore => "restore"
		Translate(x, y) => "translate ${number_word(x)} ${number_word(y)}"
		Rotate(angle) => "rotate ${number_word(angle)}"
		Scale(x, y) => "scale ${number_word(x)} ${number_word(y)}"
		Matrix({ a, b, c, d, tx, ty }) => "matrix ${nums([a, b, c, d, tx, ty])}"
		Opacity(amount) => "opacity ${number_word(amount)}"
	}

shape_words : Ui.Shape -> Str
shape_words = |shape|
	match shape {
		Rect(area) => "rect ${area_words(area)}"
		Oval(area) => "oval ${area_words(area)}"
		Polyline(points) => "line ${points.len().to_str()} ${points_words(points)}".trim()
		Polygon(points) => "polygon ${points.len().to_str()} ${points_words(points)}".trim()
		Path(segments) => "path ${segments.len().to_str()} ${Str.join_with(segments.map(segment_words), " ")}".trim()
		Wave({ source, area, low, high }) => "wave ${source} ${area_words(area)} ${num(low)} ${num(high)}"
		Ring({ source, x, y, radius, depth, low, high }) => "ring ${source} ${nums([x, y, radius, depth, low, high])}"
		Bars({ source, area, low, high, gap }) => "bars ${source} ${area_words(area)} ${nums([low, high, gap])}"
	}

segment_words : Ui.Segment -> Str
segment_words = |segment|
	match segment {
		MoveTo(p) => "M ${point_words(p)}"
		LineTo(p) => "L ${point_words(p)}"
		QuadTo(c, p) => "Q ${point_words(c)} ${point_words(p)}"
		CurveTo(c1, c2, p) => "C ${point_words(c1)} ${point_words(c2)} ${point_words(p)}"
		Close => "Z"
	}

area_words : Ui.Area -> Str
area_words = |{ x, y, width, height }| nums([x, y, width, height])

point_words : Ui.Point -> Str
point_words = |{ x, y }| "${num(x)} ${num(y)}"

points_words : List(Ui.Point) -> Str
points_words = |points| Str.join_with(points.map(point_words), " ")

## A constant, `@source:scale:offset`, or `@source[index]:scale:offset`.
number_word : Ui.Number -> Str
number_word = |number|
	match number {
		Value(v) => num(v)
		Source({ source, scale, offset }) => "@${source}:${num(scale)}:${num(offset)}"
		Element({ source, index, scale, offset }) => "@${source}[${index.to_str()}]:${num(scale)}:${num(offset)}"
	}

nums : List(F64) -> Str
nums = |values| Str.join_with(values.map(num), " ")

num : F64 -> Str
num = |value| value.to_str()

## A scene's marks in their grammar.
expect {
	scene : List(Ui.Mark)
	scene = [
		Fill(Rect({ x: 10, y: 20, width: 30.5, height: 40 }), Red),
		Save,
		Translate(Source({ source: "synthetic.level", scale: 200, offset: 10 }), Value(0)),
		Scale(Element({ source: "audio.bands", index: 3, scale: 0.5, offset: 1 }), Value(1)),
		Opacity(Value(0.5)),
		Stroke(Polyline([{ x: 0, y: 0 }, { x: 4, y: 2 }]), { color: Adaptive({ light: 0x112233, dark: 0xffffff }), width: Value(2) }),
		Restore,
		Fill(Path([MoveTo({ x: 0, y: 0 }), LineTo({ x: 1, y: 0 }), Close]), Green),
		Stroke(Wave({ source: "synthetic.wave", area: { x: 0, y: 0, width: 100, height: 50 }, low: -1, high: 1 }), { color: Green, width: Value(1.5) }),
		Fill(Bars({ source: "audio.bands", area: { x: 0, y: 0, width: 240, height: 60 }, low: 0, high: 1, gap: 2 }), Orange),
		Stroke(Ring({ source: "audio.waveform", x: 50, y: 50, radius: 20, depth: 8, low: -1, high: 1 }), { color: Yellow, width: Source({ source: "synthetic.level", scale: 4, offset: 1 }) }),
		Matrix({ a: 1, b: 0, c: 0, d: 1, tx: 3, ty: 4 }),
		Stroke(Polygon([]), { color: Blue, width: Value(1) }),
	]
	actual = scene_text(scene)
	expected =
		\\fill red rect 10 20 30.5 40
		\\save
		\\translate @synthetic.level:200:10 0
		\\scale @audio.bands[3]:0.5:1 1
		\\opacity 0.5
		\\stroke adaptive:112233:ffffff 2 line 2 0 0 4 2
		\\restore
		\\fill green path 3 M 0 0 L 1 0 Z
		\\stroke green 1.5 wave synthetic.wave 0 0 100 50 -1 1
		\\fill orange bars audio.bands 0 0 240 60 0 1 2
		\\stroke yellow @synthetic.level:4:1 ring audio.waveform 50 50 20 8 -1 1
		\\matrix 1 0 0 1 3 4
		\\stroke blue 1 polygon 0
	actual == expected
}

## A surface's space, pacing and trail in their grammar.
expect {
	actual = "${space_word(Points)}|${space_word(Fit({ width: 400, height: 300 }))}|${pacing_word(Display)}|${trail_word(NoTrail)}|${trail_word(Trail({ half_life_ms: 300, zoom: 1.25, turn: 0, shift: { x: 100, y: -2 } }))}"
	actual == "points|fit 400 300|display|none|trail 300 1.25 0 100 -2"
}

## A surface's shaders in their attributes, and its status read back.
expect {
	shader : Ui.Shader
	shader = Shaders({ warp: Some("float4 warp(Frame f, Params p) { return sample(f, f.uv); }"), composite: None, params: [("zoom", Value(1.5)), ("push", Source({ source: "audio.bass", scale: 0.2, offset: 1 }))] })
	attrs = (shader_source(shader, Warp), shader_source(shader, Composite), shader_params_text(shader), shader_params_text(NoShader))
	statuses = ["none", "running", "fallback", "failed\nwarp 3 12 use of undeclared identifier 'x'\ncomposite 0 0 too long"].map(shader_status)
	attrs == ("float4 warp(Frame f, Params p) { return sample(f, f.uv); }", "", "zoom 1.5\npush @audio.bass:0.2:1", "")
		and statuses
			== [
				NoShader,
				Running,
				Fallback,
				Failed([{ stage: Warp, line: 3, column: 12, message: "use of undeclared identifier 'x'" }, { stage: Composite, line: 0, column: 0, message: "too long" }]),
			]
}

## Image scalings in their grammar.
expect {
	cases : List(Ui.ImageScaling)
	cases = [Fit, Fill, Stretch, Original]
	Str.join_with(cases.map(image_scaling_word), " ") == "fit fill stretch original"
}

## Every `Length` reaches the host in its grammar.
expect {
	cases : List(Ui.Length)
	cases = [Auto, Fill, FillAtLeast(240), Fixed(36), AtLeast(220), AtMost(400), Between({ min: 80, max: 200 })]
	actual = Str.join_with(cases.map(length_word), "\n")
	expected =
		\\auto
		\\fill
		\\fill-at-least:240
		\\fixed:36
		\\at-least:220
		\\at-most:400
		\\between:80:200
	actual == expected
}

## Insets expand to four numbers: top, leading, bottom, trailing.
expect {
	cases : List(Ui.Insets)
	cases = [Zero, All(12), Axes({ horizontal: 8, vertical: 2 }), Each({ top: 4 }), Each({ leading: 1, trailing: 3 })]
	actual = Str.join_with(cases.map(insets_word), "\n")
	expected =
		\\0 0 0 0
		\\12 12 12 12
		\\2 8 2 8
		\\4 0 0 0
		\\0 1 0 3
	actual == expected
}

## Colours: semantic words, and adaptive pairs as six hex digits each.
expect {
	cases : List(Ui.Color)
	cases = [Label, SecondaryLabel, SelectedContentBackground, Red, Clear, Adaptive({ light: 0x24404b, dark: 0xF0F0F0 }), Adaptive({ light: 0, dark: 0x0a0b0c })]
	actual = Str.join_with(cases.map(color_word), "\n")
	expected =
		\\label
		\\secondary-label
		\\selected-content-background
		\\red
		\\clear
		\\adaptive:24404b:f0f0f0
		\\adaptive:000000:0a0b0c
	actual == expected
}

## Text styles, sizes, borders and icons in their grammar.
expect {
	actual =
		\\${text_style_word(LargeTitle)} ${text_style_word(Caption2)} ${text_style_word(Title1)}
		\\${font_size_word(Standard)} ${font_size_word(Fixed(36))}
		\\${overflow_word(WrapUpTo(2))} ${overflow_word(TruncateMiddle)}
		\\${border_word(NoBorder)} ${border_word(Line({ color: Separator, width: 1 }))} ${border_word(Dashed({ color: Accent, width: 2 }))}
		\\${icon_word(NoIcon)} ${icon_word(Symbol("trash"))}
		\\${distribution_word(FillEqually)} ${vertical_align_word(FirstBaseline)} ${bezel_word(AccessoryBar)}
	expected =
		\\large-title caption2 title1
		\\standard 36
		\\wrap:2 truncate-middle
		\\none line:1:separator dashed:2:accent
		\\none symbol:trash
		\\fill-equally first-baseline accessory-bar
	actual == expected
}
