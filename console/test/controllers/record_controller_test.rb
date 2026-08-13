require "test_helper"

# The Record filter: four dimensions — who / what / for whom / when — all ANDed,
# plus free text. Each dropdown offers only values the record actually holds, so a
# filter can never be a wasted click.
class RecordControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @acme  = Project.create!(name: "Acme")
    @globex = Project.create!(name: "Globex")
    @box   = Machine.create!(name: "devbox", ssh_host: "10.0.0.3", ssh_private_key: "k")

    @deploy = Event.record!(actor: "ci-deployer", action: "deployed", machine: @box,
                            project: @acme, summary: "deployed acme-web on devbox",
                            at: 2.hours.ago)
    @label  = Event.record!(actor: "alice", action: "labelled", project: @globex,
                            summary: "Added env=prod on Globex", at: 3.days.ago)
    @old    = Event.record!(actor: "alice", action: "deployed", project: @acme,
                            summary: "deployed acme-api", at: 40.days.ago)
  end

  test "the dropdowns offer only values the record holds" do
    get record_path
    assert_response :success
    # Actors present, in order; no blank or invented entries beyond the "Anyone" default.
    assert_select "select[name=actor] option", text: "Anyone"
    assert_select "select[name=actor] option[value=?]", "ci-deployer"
    assert_select "select[name=actor] option[value=?]", "alice"
    # A project with no acts recorded against it is not offered.
    Project.create!(name: "Untouched")
    get record_path
    assert_select "select[name=project_id] option[value=?]", @acme.id.to_s
    assert_select "select[name=project_id] option", text: "Untouched", count: 0
  end

  test "actor narrows the record" do
    get record_path(actor: "ci-deployer")
    assert_select ".chain-entry", 1
    assert_select ".chain-what", text: /acme-web/
    assert_select "select[name=actor] option[selected][value=?]", "ci-deployer"
  end

  test "project narrows the record" do
    get record_path(project_id: @globex.id)
    assert_select ".chain-entry", 1
    assert_select ".chain-what", text: /Globex/
  end

  test "the dimensions compose, and Clear appears only when something is filtering" do
    # actor + action + project + time, all at once: only the recent Acme deploy survives.
    get record_path(actor: "ci-deployer", actions: [ "deployed" ],
                    project_id: @acme.id, since: "24h")
    assert_select ".chain-entry", 1
    assert_select ".result-count", /1 entry/
    assert_select ".filter-clear"

    get record_path
    assert_select ".chain-entry", 3
    assert_select ".filter-clear", count: 0
  end

  test "an unknown actor or project is ignored rather than emptying the record" do
    get record_path(actor: "nobody@example.com", project_id: "999999")
    assert_response :success
    assert_select ".chain-entry", 3
    assert_select ".filter-clear", count: 0
  end

  test "the action pills carry the same glyph the entries do" do
    get record_path
    # "deployed" is a box act, so pill and entry both wear the box glyph.
    assert_select ".action-chips .chip", /deployed/
    assert_select ".action-chips .chip svg"
  end

  test "the selector grammar still parses in the text box" do
    get record_path(q: 'actor=alice project="Acme"')
    assert_select ".chain-entry", 1
    assert_select ".chain-what", text: /acme-api/
  end
end
