# Apps, templates and machines — what each is for, and the gaps between them

> Opened 2026-10-23, from the first real install of an app (Zot) through the deployed
> console, and an audit of the model behind it. Three silent bugs from the same audit are
> already fixed: an app copies the names it takes values for at create (it read them live
> from its template), removing an in-use template is refused in a sentence (it ended on an
> error page), and the machine page's deploy form carries a template's secret files (it
> dropped them). What is left is below, each with a leaning, none settled.

The model today: an **AppTemplate** (the library entry) has versions; an **App** is one
configured thing made from a template or a custom image — its values, its secrets, its
intention (count, exposure), optionally owned by a Project; a **Placement** is that app on
one machine. Separately, the machine page can deploy straight to its box, keeping nothing
([`console-layers.md`](../console-layers.md), the machine-view ring).

## 1. Two ways to deploy, one of them weaker

The machine page's *Deploy an app* builds a spec, sends it, and keeps nothing. Add App
keeps the App, its secret values (encrypted), and its placements. So the machine-page
path has to be retyped on every redeploy — every secret value, every file — and until
today it silently dropped secret files. Two doors into the same act, one second-class, is
the problem; a person reaching for the one on the page they are on gets the weaker one.

- **Lean: one door.** Add App is the only deploy; the machine page's button becomes *Add an
  app here*, which opens Add App with this machine as the first box. An App needs no
  Project, so the homelab case loses nothing.
- **Cost:** it reverses the machine view's "a deploy sends an AppConfig and keeps
  nothing" in `console-layers.md`. That is the reason it needs deciding rather than doing.
- **Alternative:** keep both, and say on the machine page what it does not keep.

## 2. Which page holds an app's lifecycle verbs

Moved here from [`ui-roadmap.md`](ui-roadmap.md). The App page lists start, stop,
restart, remove per placement; the app's page on its box has the same ones. Either the
App page keeps only what spans boxes (the intention, deploy-to-every-placement, delete)
and links down for the rest, or the duplication is accepted. Decide with 1: both are
"which page does what".

## 3. Deleting an app

There is no way to delete an App. `remove` takes it off one box and retires the placement;
the App — spec, secret values, template link — stays for ever. Nothing in `decisions/`
chose that. It also means a template can never be removed once any app was made from it
(the refusal added today has no way through).

- **Lean:** *Delete app* only when it is on no machine; otherwise the page lists the boxes
  it is still on, each with its `remove`. Recorded. Its stored secret values go with it.
  History stays — events keep their text and drop the link (`Event` already nullifies).

## 4. Upgrading an app

The deploy step's image field is prefilled with the image the App had **at create**.
Adding v2 to the template reaches no app; moving one means pasting a digest. The App's own
`version`/`image` never move, so its page names v1 after v2 runs, and each placement keeps
its own `desired_image`, so one app can run different versions on different boxes with
nothing calling that an app-level state.

- **Lean:** when the template has a newer version, the App page says so (*v2 available*),
  and one act deploys it to every placement and moves the App's version — surfaced, chosen
  by a person, never automatic ([`drift-is-surfaced-never-closed.md`](../drift-is-surfaced-never-closed.md),
  [`a-tag-is-not-a-release.md`](../a-tag-is-not-a-release.md)). Placements on different
  images become a named state on the App.

## 5. A private image fits only some machines

A registry login is box state ([`registry-credentials.md`](../registry-credentials.md)),
so an app whose image is in a private registry deploys only to boxes logged in to it. The
App reads as placeable anywhere, and the mismatch surfaces at the last moment as
`registry_auth` from the box.

- **Lean: surface, don't constrain.** The image names its registry; `status` reports each
  box's logins. Mark boxes that are not logged in — in the first-box picker ("— not logged
  in to zot.agoraforge.org", the shape "— not yet authorized" already has) and in the
  ceremony — with a link to log the box in.
- **Not:** the console logging the box in (it would hold registry credentials, which the
  decision refuses), or an App declaring its allowed boxes (a list repeating what the
  boxes already report).

## 6. Words: "App Library", and where the project shows

"Library" next to "App" blurs a template (a definition) and an app (a configured thing
with its own values).

- **Lean:** call the page and its entries **Templates** (`/templates`); it moved to
  `/library` only on 2026-10-22, so moving again is cheap. "App Template Library" says the
  same in three more words.
- An App already belongs to a Project (optional), and the Apps list has a project column;
  it reads as missing because it is easy to skip. **Lean:** the project before the app's
  name wherever an app is named, and a nudge on Add App when none is chosen.

## 7. The one-box case

Machines and apps are separate, and should stay so: one box runs several apps (the Zot box
runs Zot and the console), and a balanced app runs on several boxes. But one app on one
box is the common case, and the UI makes it feel like two things to manage.

- **Lean:** keep the model; make the pages lead with the pairing — an App's page opens with
  the box it runs on, a machine's page with the apps on it.
