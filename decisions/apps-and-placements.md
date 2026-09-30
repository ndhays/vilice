# Apps, placements, and app templates

> Decided 2026-09-30, while overhauling the console
> ([`what-the-console-is-for.md`](what-the-console-is-for.md)). The code takes the
> words the page and the operator already used.

## The question

The console had three models — `App`, `Install`, `InstallTarget` — and none of them
was called what an operator calls it. What they mean by "the app" was the `Install`: a
Library entry configured for a client. The `App` was the Library entry, which they
think of as a template. And one install on one box, the `InstallTarget`, was what every
page and doc already called a *placement* ("placement gap", "Place on a box", "placed
here but not reported running").

## The decision

The names follow the words:

| Was | Is | What it is |
|---|---|---|
| `App` | `AppTemplate` | A Library entry — a reusable definition, with its versions |
| `Install` | `App` | An app: a template configured for a client, with its intention |
| `InstallTarget` | `Placement` | One app on one box |

Tables, foreign keys, routes (`/apps`, `/apps/:id/placements`, `/app_templates`),
params and the blueprint all follow. The words on the page moved first, the code in the
same week; no compatibility was kept, because nothing outside the repo depended on the
old names.

Two things keep their names because they are formats read elsewhere, not names of these
models: the deploy envelope's `app` key (Steward reads it) and the Library manifest's
`apps` key (catalog files carry it).

## Roads not taken

- **Keep the code names, change only the page.** Cheap, and it leaves every reader of
  the code translating between two vocabularies — the drift this repo exists to avoid.
- **`AppTarget`** for the per-box row. A mechanical rename that keeps "target", a word
  no page uses. *Placement* is the word the pages already spoke.
- **`App` for the template, something else for the configured app.** The template is the
  thing an operator names least; the configured app is the one they act on all day. The
  plain word goes to the one used most.
