class Event < ApplicationRecord
  # Steward Console's record. Two roles, kept distinct (decisions/two-records.md):
  #   - Steward Console's *own* acts — control-plane mutations a box never sees
  #     (created/linked/labelled…), attributed to the responsible human.
  #     Authoritative.
  #   - A re-derivable *mirror* of Steward's box record, for unified display.
  # `actor` is the responsible party; `action` is the past-tense fact.
  belongs_to :machine, optional: true
  belongs_to :install, optional: true
  belongs_to :project, optional: true

  validates :at, :actor, :action, presence: true

  scope :latest, -> { order(at: :desc) }
  scope :since,  ->(time) { where(at: time..) }

  # Forensics filters over the record. Mirror the label-selector grammar used on
  # the fleet list (decisions/open/list-search.md): `key=value` tokens narrow by
  # actor / action / target, bare words do a substring match across actor,
  # action, and summary. SQLite LIKE is case-insensitive for ASCII.
  scope :by_actor,  ->(v) { where("actor LIKE ?", "%#{v}%") }
  scope :by_action, ->(v) { where("action LIKE ?", "%#{v}%") }
  scope :by_text,   ->(v) { where("actor LIKE :q OR action LIKE :q OR summary LIKE :q", q: "%#{v}%") }

  # Target = the machine / project / install an act touched, matched by name.
  scope :by_target,  ->(v) {
    like = "%#{v}%"
    where(machine_id: Machine.where("name LIKE ?", like).ids)
      .or(where(project_id: Project.where("name LIKE ?", like).ids))
      .or(where(install_id: Install.where("name LIKE ?", like).ids))
  }
  # Project = the client an act was recorded under (its own dimension, since a
  # project is the context, not really a "target").
  scope :by_project, ->(v) { where(project_id: Project.where("name LIKE ?", "%#{v}%").ids) }

  SELECTORS = { "actor" => :by_actor, "action" => :by_action,
                "target" => :by_target, "project" => :by_project }.freeze

  # Parse a query into a filtered relation. `actor=`, `action=`, `target=`,
  # `project=` tokens become selector scopes (ANDed); anything else is free text,
  # substring-matched across actor/action/summary. Values may be **quoted** to
  # include spaces — `project="Acme Corp"`. The same grammar the fleet search uses.
  def self.search(query)
    free = []
    tokenize(query).reduce(all) do |rel, token|
      key, sep, value = token.partition("=")
      value = unquote(value)
      scope = SELECTORS[key.downcase] if sep == "="
      if scope && value.present?
        rel.public_send(scope, value)
      else
        free << unquote(token)
        rel
      end
    end.then { |rel| free.any? ? rel.by_text(free.join(" ")) : rel }
  end

  # Split on whitespace, but keep a quoted run together — as a `key="a b"` value or
  # a bare `"a b"` phrase — so names with spaces survive as one token.
  def self.tokenize(query)
    query.to_s.scan(/(?:\w+=)?"[^"]*"|\S+/)
  end

  def self.unquote(str)
    str.start_with?('"') && str.end_with?('"') ? str[1..-2] : str
  end

  # Append-only by convention (decisions/two-records.md, refined in
  # decisions/record-outcome-on-the-entry.md): the recorded *facts* are never
  # edited or deleted through the app. The one exception is an act's outcome,
  # which settles **once** — a witnessed act is recorded `pending` (record before
  # act), then stamped ok/failed on the same row when it finishes. Not
  # hash-chained — Steward's on-box chain is the external anchor; this guard is
  # hygiene. (dependent: :nullify uses update_all and bypasses these, as intended.)
  SETTLE_COLUMNS = %w[outcome finished_at detail updated_at].freeze

  before_update  :allow_only_a_single_settle
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "the record is append-only" }

  # Outcome lifecycle. nil = an instantaneous act with no result to await (a label
  # edit, a star). "pending" = a witnessed command in flight. Then ok/failed.
  def pending?    = outcome == "pending"
  def settled?    = outcome.present? && outcome != "pending"
  def outcome_ok? = outcome == "ok"

  # Stamp the result on the entry — the one permitted update (pending → settled).
  def settle!(outcome, detail: nil)
    update!(outcome: outcome, finished_at: Time.current, detail: detail)
  end

  # Write one entry. Used for Steward Console's own acts (with a human actor), for
  # mirroring Steward's record, and to open a witnessed act (outcome: "pending").
  def self.record!(actor:, action:, at: Time.current, **attrs)
    create!(actor: actor, action: action, at: at, **attrs)
  end

  private

  # The only legal update: settling a pending act's outcome, once. Any change to
  # a recorded fact, or a second settle, is a rewrite — refuse it.
  def allow_only_a_single_settle
    only_settle_columns = (changed - SETTLE_COLUMNS).empty?
    raise ActiveRecord::ReadOnlyRecord, "the record's facts are append-only" unless only_settle_columns
    raise ActiveRecord::ReadOnlyRecord, "the outcome has already settled" unless outcome_was == "pending"
  end
end
