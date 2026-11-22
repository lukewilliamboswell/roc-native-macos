# Styling: design

Status: proposal. Nothing here is implemented yet. It is written against
`main` at `4627e1c` plus the interim props work on the controls branch
(`9b70f91`: `VStackProps`, `TextProps`, `Ui.scroll`, `Ui.list`, …), which
lands first; [Migration](#migration-from-the-interim-props) says what changes
from it.

The question: how does a Roc app say how its UI looks, and how does that
reach AppKit? The answer in one paragraph:

> Every `Ui` builder takes its subject first and a **props record of
> defaulted fields** beside it: `Ui.vstack({ spacing: 12, align: Fill }, kids)`,
> `Ui.text("Saved", { style: Caption, color: SecondaryLabel })`. Values are
> closed tag unions in AppKit's own vocabulary (text styles, semantic colours,
> control sizes, bezel styles), so the app follows the system look, dark mode
> and accessibility settings without asking. **State is a signal; looks are
> values.** Fields that hold what a control shows (its text, value, checked
> state, enabled state) are `Signal`s, and a text literal already is one. Fields
> that say how it looks are plain values; when a look must change with state,
> the builder's `_s` form takes the whole props record as a signal. Each prop
> crosses as one attribute with a closed value grammar, always sent, so
> defaults live only in Roc. An app shares a look by keeping props values and
> updating them (`{ ..theme.card, padding: All(16) }`); there is no stylesheet
> and no cascade.

## Contents

1. [What RC1 can do](#what-rc1-can-do) (the compiler probe)
2. [Prior art](#prior-art)
3. [The model](#the-model): what is styleable, and what is not
4. [The Roc API](#the-roc-api): shared types and every builder
5. [Static and reactive props](#static-and-reactive-props): the decision
6. [Reuse and themes](#reuse-and-themes)
7. [The wire](#the-wire): attribute names and value grammar
8. [The host](#the-host): the AppKit mapping and the symbols it needs
9. [Example: todos](#example-todos)
10. [Migration from the interim props](#migration-from-the-interim-props)
11. [Tests](#tests)
12. [Trade-offs and open questions](#trade-offs-and-open-questions)

## What RC1 can do

Every claim the API below depends on was checked with Roc 0.1.0 RC1
(`~/roc-macos_apple_silicon-0.1.0_RC1/roc`) by `roc check`, `roc test
--opt=dev`, **and** `roc build` plus running the binary under `ROC_SCRIPT`
against a copy of this platform (with the host's `dump` extended to print
attributes). RC1 has cases where `check` passes and the binary crashes (the
single-field `.Engine.Cells` builder in the README), so a probe only counts
when it ran.

| # | Probe | check | build + run |
|---|---|---|---|
| 1 | Nominal record `StackProps := { spacing : U32 ?? 8, align : Align ?? Leading, width : Length ?? Auto, padding : Insets ?? {…} }` as an argument, called with a partial literal `stack({ spacing: 12 }, kids)` | ok | ok: unspecified fields take their defaults |
| 2 | `{}` (all defaults) | ok | ok |
| 3 | Defaulted field of tag-union type (`align: Center`, `width: Fixed(120)`) | ok | ok |
| 4 | Defaulted field of nested record type, and of a nested **nominal** record with its own defaults: `padding : Edges ?? {}`, called as `{ padding: { leading: 8 } }` | ok | ok |
| 5 | A defaulted nominal record as a **tag payload**: `padding: Each({ top: 4 })` with `Each(Edges)` | ok | ok |
| 6 | Single-field props type and single-field literals: `OneProps := { gap : U32 ?? 4 }`, `one({ gap: 9 })`, `{ colour: Secondary }`, `{ on_press: h }` | ok | ok (the README's crash is specific to the record *builder* syntax) |
| 7 | Required field beside defaulted ones: `ButtonProps := { label : Str, style : […] ?? Push, … }` | ok | ok |
| 8 | Fields whose type uses the props' **type parameter**: `ListProps(a) := { items : List(a) ?? [], describe : (a -> Str) ?? \|_\| "?" }` | ok | ok |
| 9 | Function-typed defaulted field (the `describe` above) and a handler as a required field (`on_press : HandlerOf(ctx, Engine.Click)`) | ok | ok |
| 10 | A field of type `Engine.Signal(ctx, Color) ?? Engine.const(Label)`; passing `Engine.const(Secondary)` or a live `count.signal().map(…)` | ok | ok: the attribute updated on click |
| 11 | `Signal(ctx, Props)` built by `.map(\|n\| if … { color: Green } else { color: Red, weight: Bold })` (partial literals inside a lambda, branches naming different fields) and `Engine.const({ weight: Bold })` | ok | ok: attributes updated on click |
| 12 | Per-field union `Live(ctx, a) : [Is(a), Follows(Signal(ctx, a))]` with default `Is(Label)` | ok | ok |
| 13 | Props types declared **inside the `Ui := [].{ … }` type block** and used from an app as `Ui.StackProps`, `Ui.TextProps`, including `card : Ui.StackProps` then `{ ..card, align: Center }` | ok | ok |
| 14 | A text **literal** where `Signal(ctx, Str)` is expected (`Ui.text("plain", {})`), and interpolation `"${clicks} clicks"` with `clicks : Signal(ctx, I64)` | ok | ok: literal is a constant, interpolation follows the signal |
| 15 | `Engine.attr_presence` with `Absent` removes the attribute; a `Signal(ctx, Bool)` `enabled` field drives `disabled` | ok | ok |
| 16 | Theme record `Theme : { panel : BoxProps, label : Ui.TextProps }`, `theme.panel`, `{ ..theme.panel, tint: Fill }` | ok | ok |
| 17 | Optional `?:` field: `OptProps := { tint ?: Str, gap : U32 ?? 2 }`, read with `props.?tint ?? "(none)"`, called with `{}` and `{ tint: "red" }` | ok | ok |
| 18 | **Unannotated** shared value `loose = { inset: All(4) }` passed where `BoxProps` is expected | **error** | n/a |

Probe 18 fails: an unannotated literal is inferred as its own closed record,
so it does not absorb the defaults:

```
This argument has the type:
    { inset: [All(U32), Axes({ horizontal: U32, vertical: U32 }), Zero] }
But describe_box needs the first argument to be:
    BoxProps
Hint: This record is missing these fields:
 - padding
 - tint
```

and `{ ..loose, padding: … }` then says "This record does not have a field
named padding … You cannot add new fields to a record with the record update
syntax." With `loose : BoxProps` it works. **A shared props value must be
annotated** (see [themes](#reuse-and-themes)).

How mistakes read (all `roc check`):

- **Misspelt field** `stack({ spaceing: 12 }, kids)`: a type mismatch whose
  found type lists `spaceing: c, spacing: U32 ?? 8, …` beside "needs
  `StackProps`". No "did you mean" hint; the reader spots the extra field.
  The same with a nominal-qualified literal `StackProps.{ spaceing: 12 }` reads
  "invalid nominal record … The record I found is … But the nominal type
  expects …". A misspelt nested field (`padding: { leadng: 8 }`) reads the same
  way, one level down.
- **Misspelt tag** `{ align: Centre }`: mismatch plus `Hint: Maybe Centre should
  be Center?`. Good.
- **Wrong payload** `Fixed("wide")`: "This string literal is being used where a
  non-string type is needed … U32", pointing at the literal. Good.
- **Extra field** `{ spacing: 12, colour: Red }`: mismatch listing `colour: [Red]`.
- **Missing required field** `button({ style: Toolbar })`: mismatch with
  `Hint: This record is missing these fields: - label - size`. The hint is
  **wrong about `size`**, which is defaulted; it lists every field the literal
  does not name. For `Ui.button("+", { on_pres: h })` it lists `bezel`,
  `enabled` and `on_press`. Worth an upstream issue: the hint should list
  required fields only, and a near-miss field name deserves the same "maybe"
  hint tags get.

Conclusions the design relies on: props records with defaults work end to
end in RC1 for every field type we need (tags, nested and nominal records,
tag payloads, generics, functions, handlers, signals); `{}` works; partial
literals coerce wherever the expected type is known, including inside `map`
lambdas and through `Engine.const`; and a literal is a constant text signal.

## Prior art

### roc-gui (`platform/Style.roc`, `Elem.roc`, `docs/platform-api.adoc`)

roc-gui is the closest relative: native widgets (GPUI), props records with
defaults, `Gui.col({ width: Fill, gap: 6 }, kids)`.

Borrow:

- Subject plus props record, `{}` for neutral defaults, a new option is a new
  defaulted field.
- `Length : [Auto, Fill, Px(U32)]` as a tag; `align` and `justify` as tags with
  a `Default` that keeps the native placement.
- Colour adaptivity as a value: `Color := [Default, Rgb(U32), Adaptive({ light,
  dark })]`, so a change of appearance repaints without rendering again.
- Text overflow as a tag (`[Wrap, NoWrap, Ellipsis]`).
- The `Appearance` module (scheme, reduced motion) as *facts* the app may
  read; most apps never need it because colours adapt by themselves.

Do not borrow:

- **Magic zeros.** `font_size : U32 ?? 0` and `font_weight : U32 ?? 0` mean
  "native default"; `shadow : U32 ?? 0` means "none". The style guide says a
  platform-decides default is a tag. Here they are `style : TextStyle ?? Body`
  and `weight : Weight ?? Standard`.
- **One giant shared `Style`** of ~40 fields repeated flat into every
  `ColProps`, `RowProps`, `ButtonProps` (hover, active, disabled and focus
  colours, per-side borders, shadows). It exists because GPUI draws
  everything; AppKit draws its own controls, and overriding their colours
  fights the system. Our props are per element and short.
- **Raw RGB as the normal colour.** `bg: 0x24404b` is the everyday spelling
  there; here the everyday spelling is a semantic colour and RGB is an
  adaptive-only escape hatch.
- **Modifier methods** (`elem.width(Fill).grow(True)`), the `with_*` chain the
  style guide replaces with props. roc-gui needs them because a caller
  receives elements built elsewhere; with signals, a component is a function
  and its caller passes the props in.
- `hover_bg`, `active_bg`, … : AppKit controls already have pressed and
  hover appearances.

### roc-signals (`platform/Html.roc`, `Engine.roc`)

- An attribute is static (`Engine.attr`) or follows a signal
  (`Engine.attr_s`); `attr_s` inspects the signal and emits a plain static
  attribute when it is a constant (`SignalCore.representation`), and mapping a
  constant stays a constant (`SignalCore.Value.map` on `Fixed`). So a builder
  written once against signals costs nothing when handed `Engine.const`.
  This is what makes the [`_s` decision](#static-and-reactive-props) cheap.
- `Signal` has `from_quote` and `from_interpolation`: a text literal *is* a
  constant `Signal(ctx, Str)`, and `"${count} left"` is a live one. So text
  never needs a `label`/`label_s` pair.
- Html already uses props with signal defaults:
  `PlaceholderProps(ctx) := { ready : Signal(ctx, Bool) ?? Engine.const(True) }`,
  and `FileInputProps := { selection : [Single, Multiple] ?? Single, accept :
  [Any, Types(Str)] ?? Any }`, destructured with `FileInputProps.({ … })`.
- The `_s` suffix means "follows a signal" (`p_s`, `button_s`, `class_s`).
  We keep that meaning, applied to the props record.
- Do not borrow `class`/`class_s` and CSS: there is no stylesheet here.

## The model

### What is styleable

| Area | Props | AppKit |
|---|---|---|
| **Container layout** | `spacing`, `padding`, `align` (cross axis), `distribution` (main axis); the axis is the builder (`vstack`, `hstack`) | `NSStackView` `spacing`, `edgeInsets`, `alignment`, `distribution`; fill by width/height constraints |
| **Size of any element** | `width`, `height` as `Length`: `Auto`, `Fill`, `Fixed`, `AtLeast`, `AtMost`, `Between`; `squeeze` for who truncates first | Auto Layout constraints; content hugging (implied by `Fill`); compression resistance |
| **Typography** | `style` (semantic text style), `weight`, `design` (proportional, monospaced digits, monospaced), `overflow` (truncate/wrap), `align` | `NSFont.preferredFont(forTextStyle:)`, `systemFont(ofSize:weight:)`, `monospacedDigitSystemFont`, `monospacedSystemFont`; `lineBreakMode`, `maximumNumberOfLines`, `alignment` |
| **Colour** | `color` on text and symbols; `fill`, `border` on boxes; semantic colours only, plus an adaptive escape hatch | `NSColor.labelColor`, `.secondaryLabelColor`, `.controlAccentColor`, `.systemRed`, …; `NSColor(name:dynamicProvider:)` for the escape hatch |
| **Surfaces** | a dedicated `Ui.box`: `fill`, `border`, `radius`, `padding` | `NSBox` with `boxType = .custom`: `fillColor`, `borderColor`, `borderWidth`, `cornerRadius`, `contentViewMargins` |
| **Controls** | button `bezel`, `role`; `size` (control size) on every control; text field `bezel`; slider ticks | `NSButton.bezelStyle`, `isBordered`, `keyEquivalent`, `hasDestructiveAction`; `NSControl.controlSize`; `NSTextField.bezelStyle` |

Surfaces use `NSBox(.custom)` rather than a layer-backed view's
`layer.backgroundColor`: `NSBox` resolves a dynamic `NSColor` each time it
draws, so a semantic fill follows light and dark mode, whereas a `CGColor`
copied into a layer is frozen at the appearance it was copied in and must be
re-set on every appearance change. `NSBox` is also already in the catalog and
needs no QuartzCore.

### What is deliberately not styleable

- **Fonts by family or size.** Text uses AppKit's text styles, so it follows
  the system font, Apple's sizes for each style and localisation. (A fixed
  point size is an [open question](#trade-offs-and-open-questions).)
- **Control colours**: a button's bezel colour, a checkbox's box, a field's
  background, focus rings, selection highlight, hover and pressed states.
  AppKit draws them to match the system and the user's accent colour.
- **Shadows, gradients, opacity, blur, transforms, animation.** Native
  controls do not take them well, and none is needed for an app that looks
  like a Mac app. Vibrancy (`NSVisualEffectView`) may come later as its own
  element.
- **Absolute positioning and z-order.** Layout is stacks and Auto Layout.
- **Per-side borders and per-corner radii.**
- **Inheritance and cascade.** A text inside a box does not inherit the box's
  colour; there are no selectors, classes or specificity. What an element
  looks like is written at the element, or in a value the app passes there.
  Reading one call site tells you everything about that element.

## The Roc API

All types live inside the `Ui := [].{ … }` type block, so apps write
`Ui.Length`, `Ui.TextProps` (probe 13). The spelling is **`Color`**, as in
AppKit (`NSColor`), roc-gui and the interim branch; prose says colour.

### Shared types

```roc
## A side of an element's frame. `Auto` is the element's natural size;
## `Fill` takes the space its stack offers along that side.
Length : [Auto, Fill, Fixed(U32), AtLeast(U32), AtMost(U32), Between({ min : U32, max : U32 })]

## Which element gives way first when a row is too narrow: `Yield` truncates
## or shrinks before its neighbours, `Resist` after them.
Squeeze : [Standard, Yield, Resist]

## Space inside a container's edges, in points.
Insets : [Zero, All(U32), Axes({ horizontal : U32, vertical : U32 }), Each(Edges)]

## Each edge, for `Each`: name only the edges that differ from zero.
Edges := { top : U32 ?? 0, leading : U32 ?? 0, bottom : U32 ?? 0, trailing : U32 ?? 0 }

## Where a vertical stack places children across its width, and where a
## horizontal stack places them across its height. `Fill` stretches each.
HorizontalAlign : [Leading, Center, Trailing, Fill]
VerticalAlign : [Top, Center, Bottom, FirstBaseline, Fill]

## How a stack shares out its length, as NSStackView.Distribution.
## `Gravity` packs children at the start (AppKit's default).
Distribution : [Gravity, Fill, FillEqually, FillProportionally, EqualSpacing, EqualCentering]

## AppKit's semantic text styles (NSFont.TextStyle).
TextStyle : [LargeTitle, Title1, Title2, Title3, Headline, Subheadline, Body, Callout, Footnote, Caption1, Caption2]

## A weight over the text style's own; `Standard` keeps the style's.
Weight : [Standard, Light, Regular, Medium, Semibold, Bold, Heavy]

## Figures: `MonospacedDigits` keeps changing numbers from jiggling.
Design : [Proportional, MonospacedDigits, Monospaced]

## What text does when it does not fit its width.
TextOverflow : [Clip, TruncateHead, TruncateMiddle, TruncateTail, Wrap, WrapUpTo(U32)]

TextAlign : [Natural, Leading, Center, Trailing, Justified]

## A semantic AppKit colour; each follows light and dark mode, high contrast
## and the user's accent colour. `Adaptive` is the escape hatch: a pair of
## 0xRRGGBB values for light and dark, never a single fixed colour.
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

## NSControl.ControlSize.
ControlSize : [Mini, Small, Regular, Large]

## How a button is drawn, as NSButton.BezelStyle (`Borderless` is
## `isBordered = false`).
Bezel : [Push, FlexiblePush, Toolbar, AccessoryBar, Badge, Circular, SmallSquare, Borderless]

## What a button means to the window: `Default` answers Return, `Cancel`
## answers Escape, `Destructive` is drawn as destructive (hasDestructiveAction).
ButtonRole : [Normal, Default, Cancel, Destructive]

Border : [NoBorder, Line({ color : Color, width : U32 })]
```

`Fill` appears in three unions (`Length`, the aligns, `Distribution`). They
are structural tags, so each reads correctly where it stands: `width: Fill`,
`align: Fill`, `distribution: Fill`.

Numbers that have a real native default are plain numbers with that default
(`spacing : U32 ?? 8`, NSStackView's own default), not a tag: 8 is a fact,
not a magic value. A default that means "the platform decides" is a tag:
`Auto`, `Standard`, `Gravity`, `Natural`.

### Props and builders

Every element's props carry the frame fields `width`, `height` and `squeeze`,
spelled out in each type (flat, so a call reads `{ width: Fill, spacing: 12 }`
rather than `{ frame: { width: Fill } }`). The implementation shares one
`frame_attrs` function; the declarations repeat three lines.

**Containers**

```roc
VStackProps := {
	spacing : U32 ?? 8,
	padding : Insets ?? Zero,
	align : HorizontalAlign ?? Leading,
	distribution : Distribution ?? Gravity,
	width : Length ?? Auto,
	height : Length ?? Auto,
	squeeze : Squeeze ?? Standard,
}

## The same fields, except `align : VerticalAlign ?? Center`.
HStackProps := { spacing : U32 ?? 8, align : VerticalAlign ?? Center, … }

vstack : VStackProps, List(Elem(ctx)) -> Elem(ctx)
hstack : HStackProps, List(Elem(ctx)) -> Elem(ctx)

## A surface: a fill, border and corner radius around one child.
BoxProps := {
	fill : Color ?? ControlBackground,
	border : Border ?? NoBorder,
	radius : U32 ?? 0,
	padding : Insets ?? All(12),
	width : Length ?? Auto,
	height : Length ?? Auto,
	squeeze : Squeeze ?? Standard,
}

box : BoxProps, Elem(ctx) -> Elem(ctx)

form : FormProps(ctx), List(Elem(ctx)) -> Elem(ctx)     # on_submit : Handler(ctx), then the VStackProps fields
scroll : ScrollProps, Elem(ctx) -> Elem(ctx)            # { height : Length ?? Between({ min: 80, max: 240 }), spacing, padding }
list : ListProps, Elem(ctx) -> Elem(ctx)
```

A `…` in a type here stands for the fields the text names; the real
declarations write each field out, since a nominal record type cannot be
spread into another. The subject comes first in every builder except the
containers, whose children come last because a long child list reads best
at the end, as `col({ width: Fill, gap: 12 }, children)` in the style guide.

**Text**

```roc
TextProps := {
	style : TextStyle ?? Body,
	weight : Weight ?? Standard,
	design : Design ?? Proportional,
	color : Color ?? Label,
	overflow : TextOverflow ?? TruncateTail,
	align : TextAlign ?? Natural,
	width : Length ?? Auto,
	height : Length ?? Auto,
	squeeze : Squeeze ?? Standard,
}

## Text. A literal is a constant; `"${count} left"` or a mapped signal follows it.
text : Signal(ctx, Str), TextProps -> Elem(ctx)

## Text whose look follows a signal.
text_s : Signal(ctx, Str), Signal(ctx, TextProps) -> Elem(ctx)
```

`title`, `label`, `label_s` and `readout_s` become
`Ui.text("To-do", { style: Title1 })`, `Ui.text("Hi", {})`,
`Ui.text(name, {})` and `Ui.text(elapsed, { style: LargeTitle, design:
MonospacedDigits })`.

**Controls**

```roc
ButtonProps(ctx) := {
	on_press : HandlerOf(ctx, Engine.Click),
	enabled : Signal(ctx, Bool) ?? Engine.const(Bool.True),
	bezel : Bezel ?? Push,
	role : ButtonRole ?? Normal,
	size : ControlSize ?? Regular,
	width : Length ?? Auto,
	height : Length ?? Auto,
	squeeze : Squeeze ?? Standard,
}

button : Signal(ctx, Str), ButtonProps(ctx) -> Elem(ctx)

## The form's default button: Return, or a click, submits the enclosing form.
SubmitProps(ctx) := { enabled : Signal(ctx, Bool) ?? Engine.const(Bool.True), bezel : Bezel ?? Push, size : ControlSize ?? Regular, width : Length ?? Auto, … }
submit_button : Signal(ctx, Str), SubmitProps(ctx) -> Elem(ctx)

TextFieldProps(ctx) := {
	on_input : Handler(ctx),
	placeholder : Str ?? "",
	enabled : Signal(ctx, Bool) ?? Engine.const(Bool.True),
	bezel : [Square, Rounded] ?? Square,
	size : ControlSize ?? Regular,
	style : TextStyle ?? Body,
	width : Length ?? AtLeast(220),
	height : Length ?? Auto,
	squeeze : Squeeze ?? Standard,
}

## The subject is the text the field shows.
text_field : Signal(ctx, Str), TextFieldProps(ctx) -> Elem(ctx)

CheckboxProps(ctx) := {
	checked : Signal(ctx, Bool),
	on_change : HandlerOf(ctx, Bool),
	enabled : Signal(ctx, Bool) ?? Engine.const(Bool.True),
	size : ControlSize ?? Regular,
	width : Length ?? Auto,
	…
}

checkbox : Signal(ctx, Str), CheckboxProps(ctx) -> Elem(ctx)

SliderProps(ctx) := {
	range : { min : I64, max : I64 },
	on_input : Handler(ctx),
	ticks : [NoTicks, Ticks({ count : U32, snap : [Snap, Free] })] ?? NoTicks,
	enabled : Signal(ctx, Bool) ?? Engine.const(Bool.True),
	size : ControlSize ?? Regular,
	width : Length ?? AtLeast(220),
	…
}

slider : Signal(ctx, I64), SliderProps(ctx) -> Elem(ctx)

## SF Symbols: the symbol's colour and scale beside the text it sits with.
SymbolProps := { color : Color ?? Label, scale : [Small, Medium, Large] ?? Medium, weight : Weight ?? Standard, … }
symbol : Str, SymbolProps -> Elem(ctx)

divider : () -> Elem(ctx)
spacer : () -> Elem(ctx)
```

The dropdown, segmented control, text area and progress bar from the
controls branch take the same shape: subject (the selection, the text, the
value), then `{ on_change, size, width, … }`.

Handlers are fields. A required handler field keeps the call to two
arguments (subject, props), names the handler at the call site
(`{ on_press: … }`), and lets a button with three handlers some day add
them without a new signature. This follows roc-gui's `on_press`.

`placeholder : Str ?? ""` is deliberately a plain string: an empty
placeholder is not a platform decision, it is the absence of text, and
AppKit shows nothing for it either.

## Static and reactive props

Four ways to let a look follow state were built and run (probes 10–12):

| | Static call | Reactive call | Cost to the reader |
|---|---|---|---|
| **A. Every field a signal** (`color : Signal(ctx, Color) ?? Engine.const(Label)`) | `{ color: Engine.const(SecondaryLabel) }` | `{ color: status.map(tint) }` | Every static look pays a wrapper. Static looks are almost all looks. |
| **B. Per-field union** (`color : Live(ctx, Color) ?? Is(Label)`) | `{ color: Is(SecondaryLabel) }` | `{ color: Follows(status.map(tint)) }` | A wrapper on every static look, and a new pair of words to learn. |
| **C. `_s` builder, whole props as a signal** | `Ui.text("Saved", { color: SecondaryLabel })` | `Ui.text_s("Saved", status.map(\|s\| if (s == Over) { color: Red } else {}))` | One rule: `_s` means the props follow a signal. Static calls are bare. |
| **D. `Engine.when` between two static elements** | as C | `Engine.when(over, \|\| red, \|\| plain)` | Rebuilds the view, losing control state; no good for fields. |

**Decision: state is a signal; looks are values; `_s` lifts the look.**

1. **State fields are signals**: a control's text, value, checked, selection,
   progress and `enabled`. They change all the time, and a text literal is
   already a constant signal (probe 14), so `Ui.button("Save", …)` and
   `Ui.button(title, …)` are the same builder. A Bool state's default is
   `Engine.const(…)`, written once, in `Ui`.
2. **Look fields are plain values**: the common case reads as a spec,
   `{ style: Headline, color: SecondaryLabel }`.
3. **When a look must change, the `_s` form takes the whole props record as
   a signal**: `text_s : Signal(ctx, Str), Signal(ctx, TextProps) -> Elem(ctx)`.
   The app writes the looks as ordinary partial literals in a `map` (probe 11).
   It matches roc-signals' meaning of `_s` ("follows a signal").
4. `_s` exists only for builders whose props hold **no** signals or handlers
   (text, stacks, box, symbol). A control's props already hold signals, and a
   signal of a record of signals has no meaning. So the rule a reader keeps is
   mechanical: a field typed `Signal` follows it; everything else is fixed
   when the element is built, unless the builder is `_s`.

Implementation is one path per element. The static builder is the reactive
one handed a constant:

```roc
text = |content, props| text_s(content, Engine.const(props))

text_s = |content, props|
	Engine.element(
		"ui-text",
		[
			Engine.attr_s("text-style", props.map(|p| text_style_word(p.style))),
			Engine.attr_s("weight", props.map(|p| weight_word(p.weight))),
			Engine.attr_s("color", props.map(|p| color_word(p.color))),
			…frame_attrs(props),
		],
		[Engine.text_s(content)],
	)
```

`Engine.const(props).map(f)` is still a constant, and `attr_s` of a constant
emits a plain static attribute (`SignalCore.Value.map`, `Engine.attr_s`), so
the static builder puts no reader in the graph and costs what a hand-written
`Engine.attr` would. A live props signal costs one derived reader per
attribute; the engine writes an attribute only when its text changes, so a
colour flip sends one `ATTR`.

## Reuse and themes

There is no stylesheet. A look is a value; reuse is ordinary Roc.

```roc
Theme : {
	page : Ui.VStackProps,
	toolbar : Ui.HStackProps,
	card : Ui.BoxProps,
	quiet : Ui.TextProps,
}

theme : Theme
theme = {
	page: { spacing: 12, padding: All(20), align: Fill },
	toolbar: { spacing: 4 },
	card: { fill: ControlBackground, radius: 8, padding: All(12) },
	quiet: { style: Caption1, color: SecondaryLabel },
}

Ui.box({ ..theme.card, padding: All(16) }, Ui.text("Draft", theme.quiet))
```

- **Annotate a shared props value** (`theme : Theme`, or `card : Ui.BoxProps`).
  An unannotated literal does not absorb defaults (probe 18). This is an
  exception to "omit annotations on simple constants", and the compiler
  enforces it.
- A component is a function that takes the props it lets its caller change:
  `badge : Signal(ctx, Str), Ui.TextProps -> Elem(ctx)`.
- A theme that follows state (compact mode, say) is a `Signal(ctx, Theme)`
  and its parts reach `_s` builders through `map`.
- Dark mode needs no theme: semantic colours adapt. An app that wants to know
  the scheme reads the boot media fact `(prefers-color-scheme: dark)`.

## The wire

Each prop crosses as one attribute on the `ui-*` element. Rules:

- **Every prop is always sent**, including defaults, as an explicit word
  (`auto`, `standard`, `gravity`). Defaults then live only in Roc (one home);
  the host has no defaults of its own to keep in step, and an `_s` look that
  returns to its default writes the default's word rather than removing an
  attribute. A template row's static attributes are part of its template, so
  this costs nothing per row.
- **Closed vocabularies.** Every value is a word from a fixed list, a decimal
  number, or one of the compound forms below. A word the host does not know is
  a fatal error, not a skip ("a bad request at the seam crashes").
- Names are lowercase with hyphens; words are the Roc tag in lowercase with
  hyphens (`SecondaryLabel` → `secondary-label`, `Caption1` → `caption1`).
- Static props use `Engine.attr`'s path; reactive ones `attr_s`. The host
  cannot tell them apart, and does not need to.

| Attribute | On | Grammar |
|---|---|---|
| `width`, `height` | every element | `auto` \| `fill` \| `fixed:N` \| `at-least:N` \| `at-most:N` \| `between:MIN:MAX` |
| `squeeze` | every element | `standard` \| `yield` \| `resist` |
| `spacing` | stacks, form, scroll | `N` |
| `padding` | stacks, form, scroll, box | `TOP LEADING BOTTOM TRAILING` (always four numbers; Roc expands `All`, `Axes`, `Each`) |
| `align` | `ui-vstack`, `ui-form` | `leading` \| `center` \| `trailing` \| `fill` |
| `align` | `ui-hstack` | `top` \| `center` \| `bottom` \| `first-baseline` \| `fill` |
| `distribution` | stacks | `gravity` \| `fill` \| `fill-equally` \| `fill-proportionally` \| `equal-spacing` \| `equal-centering` |
| `text-style` | text, text field | `large-title` \| `title1` … `caption2` |
| `weight` | text, symbol | `standard` \| `light` \| `regular` \| `medium` \| `semibold` \| `bold` \| `heavy` |
| `design` | text | `proportional` \| `monospaced-digits` \| `monospaced` |
| `overflow` | text | `clip` \| `truncate-head` \| `truncate-middle` \| `truncate-tail` \| `wrap` \| `wrap:N` |
| `text-align` | text | `natural` \| `leading` \| `center` \| `trailing` \| `justified` |
| `color` | text, symbol | colour (below) |
| `fill` | box | colour |
| `border` | box | `none` \| `line:WIDTH:COLOUR` |
| `radius` | box | `N` |
| `bezel` | button | `push` \| `flexible-push` \| `toolbar` \| `accessory-bar` \| `badge` \| `circular` \| `small-square` \| `borderless` |
| `bezel` | text field | `square` \| `rounded` |
| `role` | button | `normal` \| `default` \| `cancel` \| `destructive` |
| `size` | every control | `mini` \| `small` \| `regular` \| `large` |
| `enabled` | every control | `true` \| `false` (replaces `disabled` presence) |

A colour is a semantic word (`label`, `secondary-label`, `accent`, `red`, …,
`clear`) or `adaptive:RRGGBB:RRGGBB` (light, then dark, six hex digits each).

The words are produced by pure functions in `Ui.roc` (`length_word`,
`color_word`, `insets_words`, …), one per shared type, each with `expect`s.

## The host

`applyAttr` gains one case per attribute; each parses its grammar into a
Swift enum at the door (`Length`, `Squeeze`, `SemanticColor`) and fails
loudly otherwise. Layout attributes mark the view's stack dirty, as the
interim `configure` does, so constraints are rebuilt once per batch in
`sync()`.

| Prop | AppKit |
|---|---|
| `spacing` | `NSStackView.spacing` |
| `padding` | `NSStackView.edgeInsets` (`NSEdgeInsets`, leading/trailing flipped for right-to-left via `userInterfaceLayoutDirection`); `NSBox.contentViewMargins` |
| `align` | `NSStackView.alignment`: `.leading`, `.centerX`, `.trailing`; `.top`, `.centerY`, `.bottom`, `.firstBaseline`; `fill` is the interim `setFill`: each arranged view's cross-axis anchor equal to the stack's minus its insets |
| `distribution` | `NSStackView.distribution`: `.gravityAreas`, `.fill`, `.fillEqually`, `.fillProportionally`, `.equalSpacing`, `.equalCentering` |
| `width`/`height` | host-owned constraints keyed by purpose (the interim `setSize`): `fixed` is `==` at required priority; `at-least` `>=`; `at-most` `<=`; `between` both; `fill` sets content hugging to 1 on that axis (along the stack's axis) or a fill constraint (across it); `auto` removes them and restores hugging 250 |
| `squeeze` | `setContentCompressionResistancePriority` on the horizontal axis: `yield` 250, `standard` 750 (AppKit's default for most controls), `resist` 999 |
| `text-style` | `NSFont.preferredFont(forTextStyle:)` with `.largeTitle`, `.title1`, … `.caption2` |
| `weight` | `standard` keeps the text style's font; otherwise `NSFont.systemFont(ofSize: preferred.pointSize, weight:)` with `NSFont.Weight.light` … `.heavy` |
| `design` | `monospaced-digits`: `NSFont.monospacedDigitSystemFont(ofSize:weight:)`; `monospaced`: `NSFont.monospacedSystemFont(ofSize:weight:)`, at the style's size |
| `overflow` | `NSTextField.lineBreakMode` (`.byClipping`, `.byTruncatingHead/Middle/Tail`, `.byWordWrapping`), `maximumNumberOfLines` (1, 0 for `wrap`, N), `cell?.wraps`, `preferredMaxLayoutWidth` for wrapping inside a stack |
| `text-align` | `NSTextField.alignment` (`NSTextAlignment.natural`, `.left`/`.right` from layout direction, `.center`, `.justified`) |
| `color` | `NSTextField.textColor`; `NSImageView.contentTintColor` |
| colours | `NSColor.labelColor`, `.secondaryLabelColor`, `.tertiaryLabelColor`, `.quaternaryLabelColor`, `.controlAccentColor`, `.linkColor`, `.placeholderTextColor`, `.separatorColor`, `.windowBackgroundColor`, `.controlBackgroundColor`, `.underPageBackgroundColor`, `.textBackgroundColor`, `.selectedContentBackgroundColor`, `.systemRed` … `.systemBrown`, `.systemGray`, `.clear`; `adaptive` is `NSColor(name: nil, dynamicProvider:)` choosing `NSColor(srgbRed:green:blue:alpha:)` by `appearance.bestMatch(from: [.aqua, .darkAqua])` |
| box | `NSBox`, `boxType = .custom`, `titlePosition = .noTitle`, `fillColor`, `borderColor`, `borderWidth`, `cornerRadius`, `contentViewMargins`; its `contentView` holds the child's view |
| `bezel` | `NSButton.bezelStyle` (`.push`, `.flexiblePush`, `.toolbar`, `.accessoryBar`, `.badge`, `.circular`, `.smallSquare`); `borderless` sets `isBordered = false`. Text field: `NSTextField.bezelStyle` `.squareBezel` / `.roundedBezel` |
| `role` | `default`: `keyEquivalent = "\r"`; `cancel`: `keyEquivalent = "\u{1b}"`; `destructive`: `hasDestructiveAction = true` |
| `size` | `NSControl.controlSize` (`.mini`, `.small`, `.regular`, `.large`), and the control's font to `NSFont.systemFont(ofSize: NSFont.systemFontSize(for:))` so text matches |
| `enabled` | `NSControl.isEnabled` |

Priorities are written as raw values (`.init(250)`), as the interim host
already does, so no `NSLayoutPriority*` symbol is referenced.

### Catalog additions (`host/interfaces.json`)

Ownership by Apple's documentation (developer.apple.com/documentation/appkit),
not by reading SDK files. Most of the work is Objective-C messages to classes
already listed (`NSStackView`, `NSFont`, `NSColor`, `NSBox`, `NSButton`,
`NSTextField`, `NSLayoutConstraint`, `NSView`), which need no new symbol. The
new symbols are the exported constants:

- **AppKit**, `NSFont.TextStyle` constants (`NSFontTextStyle*`, macOS 11):
  `_NSFontTextStyleLargeTitle`, `_NSFontTextStyleTitle1`,
  `_NSFontTextStyleTitle2`, `_NSFontTextStyleTitle3`,
  `_NSFontTextStyleHeadline`, `_NSFontTextStyleSubheadline`,
  `_NSFontTextStyleBody`, `_NSFontTextStyleCallout`,
  `_NSFontTextStyleFootnote`, `_NSFontTextStyleCaption1`,
  `_NSFontTextStyleCaption2`.
- **AppKit**, `NSFont.Weight` constants (`NSFontWeight*`): `_NSFontWeightLight`,
  `_NSFontWeightSemibold`, `_NSFontWeightBold`, `_NSFontWeightHeavy`
  (`_NSFontWeightRegular` and `_NSFontWeightMedium` are already listed).
- **AppKit**, for `adaptive` only: `_NSAppearanceNameAqua`,
  `_NSAppearanceNameDarkAqua`, and `_OBJC_CLASS_$_NSAppearance` if Swift
  references the class for `bestMatch(from:)`'s array.
- **Swift overlay.** `NSEdgeInsets(top:left:bottom:right:)` and the
  `NSFont.TextStyle`/`NSFont.Weight` wrappers may compile to Swift AppKit
  overlay symbols (mangled `So…`/`6AppKit`, owned by
  `/usr/lib/swift/libswiftAppKit.dylib`). The `--audit` step names any that
  appear; each joins the catalog under that library with the same
  per-library evidence as `libswiftFoundation`.

No QuartzCore and no new CoreGraphics symbols: surfaces use `NSBox`, not
layers.

## Example: todos

The interim todos (scroll area, Command-N), in the proposed API. Only the
view changes; the store, `encode`/`decode`, `adding`, `added`, `plan` and the
tests are as they are.

```roc
Theme : {
	page : Ui.VStackProps,
	filters : Ui.HStackProps,
	quiet : Ui.TextProps,
}

theme : Theme
theme = {
	page: { spacing: 12, padding: All(20), align: Fill },
	filters: { spacing: 4 },
	quiet: { style: Caption1, color: SecondaryLabel },
}

view : () -> Elem(Engine.StoreRoot(_))
view = || {
	todos = cells.todos.signal()
	Ui.vstack(
		theme.page,
		[
			Ui.text("To-do", { style: Title1 }),
			## Every change to the table after mount is saved.
			Engine.watch_changes(todos.map(encode), |text| [Engine.command(StorageSet("todos", text))], Engine.ignore({})),
			Ui.form(
				{ on_submit: Engine.handle_by(adding(), |at, _| added(at)) },
				[
					Ui.hstack(
						{ align: FirstBaseline },
						[
							Ui.text_field(cells.draft.signal(), { placeholder: "What needs doing?", on_input: Engine.handle(|typed| [cells.draft.set(typed)]), width: Fill }),
							Ui.submit_button("Add", {}),
						],
					),
				],
			),
			Engine.state(
				All,
				|showing| Ui.vstack(
					{ align: Fill },
					[
						Ui.hstack(
							theme.filters,
							[
								Ui.button("All", { on_press: showing.update(|_| All), bezel: AccessoryBar }),
								Ui.button("Open", { on_press: showing.update(|_| Open), bezel: AccessoryBar }),
								Ui.button("Done", { on_press: showing.update(|_| Done), bezel: AccessoryBar }),
							],
						),
						Ui.divider(),
						Ui.scroll(
							{ height: Between({ min: 80, max: 200 }) },
							Engine.table_view(
								cells.todos,
								{ query: showing.signal(), plan, window: Engine.const(Engine.every_row) },
								|key, todo| row(key, todo),
							),
						),
					],
				),
			),
			Engine.when(todos.map(|table| table.len() == 0), || Ui.text("Nothing to do.", theme.quiet), || Engine.text("")),
			## The count turns green when everything is done.
			Ui.text_s(todos.map(remaining), todos.map(|table| if (open_count(table) == 0) { ..theme.quiet, color: Green } else theme.quiet)),
			# Command-N adds the draft too, from anywhere in the window.
			Ui.shortcut([Ui.command("n")], Engine.handle_by(adding(), |at, _| added(at))),
		],
	)
}

## One row: the checkbox writes this to-do and no other; removing it is a
## decision over the whole table.
row : Signal(r, U64), State(r, Todo) -> Elem(r)
	where [r.store : () -> Engine.Reach(r, _)]
row = |key, todo|
	Ui.hstack(
		{},
		[
			Ui.checkbox(
				todo.signal().map(|t| t.title),
				{ checked: todo.signal().map(|t| t.done), on_change: todo.set_value(|held, checked| { ..held, done: checked }), squeeze: Yield },
			),
			Ui.spacer(),
			Ui.button(
				"Remove",
				{ on_press: Engine.handle_by(key, |id, _| [cells.todos.update(|table| table.remove(id))]), bezel: Borderless, size: Small, role: Destructive },
			),
		],
	)

open_count : Table(U64, Todo) -> U64
open_count = |table| table.fold(0, |count, _, todo| if (todo.done) count else count + 1)
```

What it shows: one builder per element, each call a readable spec; the
theme is three annotated values; `Ui.text("To-do", …)` and
`Ui.text_s(todos.map(remaining), …)` are the same element, with a literal
and a live text; and the one look that changes (the count's colour) says so
with `_s` and two ordinary props values.

## Migration from the interim props

The controls branch's shapes, and what each becomes:

| Interim | Proposed |
|---|---|
| `Ui.text(props, "Saved")`, `Ui.text_s(props, signal)` (props first) | `Ui.text("Saved", props)`, `Ui.text(signal, props)`; `text_s` now means the props follow a signal |
| `Font : [Body, Title, Headline, Caption, Mono]`, field `font` | `style : TextStyle` (AppKit's eleven) plus `design : Design` for monospacing |
| `Color : [Primary, Secondary, Tertiary, …]` | `Primary` → `Label`, `Secondary` → `SecondaryLabel`, `Tertiary` → `TertiaryLabel`; more semantic colours; `Adaptive` |
| `padding : U32 ?? 0` | `padding : Insets ?? Zero` (`All(12)`, `Axes(…)`, `Each({ top: 4 })`) |
| `VStackProps.align : [Leading, Center, Trailing, Fill]` | unchanged (`HorizontalAlign`); `HStackProps.align` gains `FirstBaseline`, `Fill` |
| `ScrollProps { height : U32 ?? 240, min_height : U32 ?? 80 }` | `height : Length ?? Between({ min: 80, max: 240 })`, if `Between` maps cleanly to the scroll view's starting height (open question 4) |
| `title`, `label`, `label_s`, `readout_s` | `Ui.text` with a style |
| `button`, `button_s`, `action_button` | `Ui.button(title, { on_press, enabled })` |
| `text_field(placeholder, value, handler)` | `Ui.text_field(value, { on_input, placeholder })` |
| `checkbox(title, checked, handler)` | `Ui.checkbox(title, { checked, on_change })` |
| `slider({ min, max }, value, handler)` | `Ui.slider(value, { range: { min, max }, on_input })` |
| `form(handler, kids)` | `Ui.form({ on_submit }, kids)` |
| `disabled` attribute (presence) | `enabled` attribute (`true`/`false`) |
| attributes sent always (`spacing`, `padding`, `align`) | unchanged, extended to every prop |

## Tests

- `expect`s beside every word function in `Ui.roc` (`length_word(Between({
  min: 1, max: 2 })) == "between:1:2"`, every `Color`, every `TextStyle`,
  `insets_words(Axes({ horizontal: 8, vertical: 2 })) == "2 8 2 8"`), as a
  labelled multi-line report per type.
- A scripted run per example under `ROC_SCRIPT` with `dump` printing each
  element's attributes (the probe's change to `Script.swift`, worth keeping),
  so a test can see that `{ color: Green }` reached the label after a click.
- The host's grammar parsers fail on an unknown word; a script step that
  sends one is a negative test.

## Trade-offs and open questions

Chosen, with the alternative given up:

- **Static looks, `_s` for reactive looks** over signals in every field
  (noise on every static look) or a per-field `Is`/`Follows` union (noise
  plus vocabulary). Given up: making one look field reactive while others stay
  static in the same call; with `_s` the app maps the whole record, which in
  practice is one `if` returning two props values.
- **Always send every prop** over sending only non-defaults. Given up: short
  dumps and a few bytes per element. Gained: defaults in one place, and no
  presence juggling for `_s` looks.
- **Flat frame fields** (`width`, `height`, `squeeze` in every props type)
  over a nested `frame : Frame ?? {}`. Given up: three repeated declarations
  per props type in `Ui.roc`.
- **`Ui.box` for surfaces** over `fill`/`radius` on every stack: stacks stay a
  bare `NSStackView`, and a fill follows dark mode because `NSBox` redraws
  with the dynamic colour.
- **Semantic colours, `Adaptive` as the only escape hatch** over raw RGB: a
  fixed RGB colour is wrong in one of the two appearances.

Questions for you:

1. **Where `_s` exists.** Proposed: `text_s`, `vstack_s`, `hstack_s`, `box_s`,
   `symbol_s` (every look-only builder), or only `text_s` until another is
   needed?
2. **The RGB escape hatch.** Keep `Adaptive({ light, dark })` in `Color`, or
   leave it out until an app needs a brand colour?
3. **A fixed font size.** Text styles only, or also a `Points(U32)` size for
   a large readout (the interim `readout_s` is 36 pt; `LargeTitle` is 26)?
4. **Fill with a floor.** `Length` cannot say "fill, but at least 220"
   (`Fill` and `AtLeast` are exclusive). Add `FillAtLeast(U32)`, make
   `Fill` take bounds (`Fill({ min, max })` with defaulted fields), or let a
   field's `AtLeast(220)` plus the stack's `align: Fill` cover it? The
   scroll area's "starts at 240, shrinks to 80" also needs a starting size
   that is not a constraint.
5. **Dropping the old builders** (`title`, `label`, `label_s`, `readout_s`,
   `button_s`, `action_button`): one breaking change to every example, done
   with the implementation?
6. **Handlers in props** (`{ on_press: h }`) rather than as a third
   positional argument: agreed?
7. **Upstream.** Report the misleading "missing these fields" hint (it lists
   defaulted fields) and ask for a near-miss hint on misspelt field names?
