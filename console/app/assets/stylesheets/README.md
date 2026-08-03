# Stylesheets

Plain CSS, split by concern and loaded **in cascade order** by the layout
(`stylesheet_link_tag "tokens", "base", …`). Order matters: tokens must come first,
components last. Theming is **CSS custom properties** (see `tokens.css`) — light/dark
swap variables and nothing else changes; never use a preprocessor variable for a
themed value.

| File | What's in it |
|---|---|
| `tokens.css` | Theme variables — the palette + light/dark/OS-follow. The only file with colours. |
| `base.css` | Reset, body type, links, the sidebar rail/shell, focus rings. |
| `layout.css` | Breadcrumb, headings, cards, the card grid, page/section heads, Settings, Access. |
| `forms.css` | `.stack-form` fields/inputs/select, **and the install form** (`.install-form` steps + the catalog `.pick-*` picker). |
| `lists.css` | `.rows` list machinery (machines + App Library), version lists, badges, the `.tag` badge. |
| `record.css` | The observe/mutate spine: panels, the mutate ceremony, compose, the chain, integrity. |
| `widgets.css` | Shared bits: buttons, flash, mono, icons, health dots/lines, labels + editor, the record filter, the **list toolbar** (`.list-toolbar`, paired with `shared/_list_toolbar` + the `selection` Stimulus controller), the **header menu** popover (`details.menu`), the theme toggle, the `.hint` tooltip. |

This started as a behaviour-preserving split of a former single `application.css`. The
collisions it surfaced have since been cleaned up:

- `.section-head` (layout.css, an h2 + action) no longer collides with the small-caps
  kicker heading, now `.section-kicker` (widgets.css).
- the former `install_form.css` has been folded into `forms.css` / `lists.css` /
  `widgets.css` (and `[hidden] { display: none !important }` into `base.css`).
