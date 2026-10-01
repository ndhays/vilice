# One line of one box's rights ledger, as `vilice actors` reads it back.
#
# A presentation value, not a record: nothing here is stored. `authorized_keys` *is*
# the ledger (blueprint/vilice/auth.md), and a copy of it in our database would be a
# second answer to "who may act on this box" that could quietly disagree with the box.
# So this is assembled per request from a live read and thrown away.
class AccessLine < Data.define(:machine, :client, :scope, :key_type, :fingerprint,
                               :comment, :command, :pinned)
  # ── How far this key reaches ────────────────────────────────────────────────
  # The scope ladder is `observe ⊂ operate ⊂ grant` (blueprint/vilice/auth.md), and
  # an ungated line sits **above** all three rather than beside them: a key with no
  # forced command has no ceiling at all. One ordered axis, most reach first — which
  # is what makes the thing this page exists for land at the top by construction
  # rather than as a banner someone has to go looking behind.
  REACH_GROUPS = {
    "ungated" => [ 0, "Not written by Vilice — no ceiling at all" ],
    "grant"   => [ 1, "Grant — can admit other keys" ],
    "operate" => [ 2, "Operate — can act on the box" ],
    "observe" => [ 3, "Observe — read-only" ]
  }.freeze

  def self.from(machine, actor)
    key_type = actor["key_type"].presence
    new(machine: machine,
        client: actor["client"].presence,
        scope: actor["scope"].presence,
        key_type: key_type,
        fingerprint: actor["fingerprint"].presence,
        comment: actor["comment"].presence || comment_in(actor["raw"], key_type),
        command: actor["command"].presence,
        # `vilice actors` marks a line unpinned when it carries no forced command, or
        # one this binary did not write. A foreign command is never parsed into
        # something reassuring.
        pinned: actor["pinned"].present?)
  end

  # The trailing comment on a raw `authorized_keys` line — `<type> <blob> [comment]`.
  # Vilice parses a comment out only for lines it recognises as grants, so for a
  # hand-added key it survives nowhere but `raw` — and it is the only handle anyone
  # has on who holds that key, which on this page is the key that matters most.
  #
  # Only trusted when the line actually begins with the key type Vilice reported. A
  # line carrying options (a foreign forced command) does not have its comment in a
  # fixed position, and guessing at one would be inventing an owner for the most
  # dangerous row on the page.
  def self.comment_in(raw, key_type)
    return nil if raw.blank? || key_type.blank?
    fields = raw.to_s.strip.split(/\s+/, 3)
    return nil unless fields.first == key_type
    fields[2].presence
  end

  def ungated? = !pinned

  def reach = ungated? ? "ungated" : scope.to_s

  # Sort key for "most reach first", used to order lines *inside* a group that is not
  # itself the ladder.
  def reach_order = REACH_GROUPS.fetch(reach, [ 4 ]).first

  # What to call the holder. A Vilice grant is named; an ungated line has no client,
  # so the key's own comment is the only handle on it, and where there isn't one the
  # row says so rather than inventing a name.
  def name = client || comment || "unnamed key"

  # Free-text list search over what identifies a line: who holds it, which box it
  # opens, and the fingerprint — the one field you can compare against a key in hand.
  def matches?(query)
    return true if query.blank?
    haystack = [ client, comment, machine.name, fingerprint, key_type ].compact.join(" ")
    haystack.downcase.include?(query.downcase)
  end
end
