# The themes an operator can pick, and the modes each one comes in.
#
# A theme is a **named set of token values**; every theme declares the same names
# (blueprint/design/tokens.md), so nothing outside `tokens.css` changes when one is
# selected — the layout, components, and helpers never learn a theme's name. That
# is the whole point of the semantic token layer, and it is what makes adding a
# theme a two-step job: one entry here, one pair of blocks in `tokens.css`.
#
# A theme is *not* light or dark. Every theme carries both, and `mode` picks
# between them — or follows the operator's OS, which is the default.
Theme = Data.define(:name, :label, :blurb)

# Reopened rather than declared in a `Data.define` block: constants assigned inside
# that block take their lexical scope from the file and would land at top level.
class Theme
  # `vilice` is the default and the reference implementation: near-black on
  # near-white with the one yellow accent, matching the docs site. Its dark mode is
  # where the palette is allowed some voltage.
  ALL = [
    new(name: "vilice", label: "Vilice",
        blurb: "Black and yellow, the way the docs site reads. Neon in the dark.")
  ].freeze

  DEFAULT = ALL.first

  def self.names = ALL.map(&:name)
  def self.find(name) = ALL.find { |t| t.name == name } || DEFAULT

  # Light and dark are the two token sets a theme must provide; `system` picks
  # between them from the OS and is the default, so a fresh operator gets the
  # appearance they already asked their machine for.
  MODES = %w[ system light dark ].freeze
  MODE_LABELS = { "system" => "Follow my system", "light" => "Light", "dark" => "Dark" }.freeze
end
