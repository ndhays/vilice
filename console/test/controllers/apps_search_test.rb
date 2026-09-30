require "test_helper"

# One `?q=` over what identifies a placement — its name, the host it serves, the app
# it came from, and the box it runs on — plus `?group=`. Both live in the query
# string, so a narrowed list is a link you can send.
class AppsSearchTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @acme  = Project.create!(name: "Acme")
    @box   = Machine.create!(name: "node-005", ssh_host: "x")
    @other = Machine.create!(name: "node-999", ssh_host: "x")
    @nginx = AppTemplate.create!(name: "nginx")

    @web = @acme.apps.create!(name: "acme-web", image: "x@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                                 hostname: "shop.example.com", app_template: @nginx)
    @web.placements.create!(machine: @box, status: "running")

    @api = @acme.apps.create!(name: "billing-api", image: "x@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    @api.placements.create!(machine: @other, status: "running")
  end

  def names = css_select(".app-rows .row-name").map(&:text)

  test "search matches the app's own name" do
    get apps_path(q: "billing")
    assert_response :success
    assert_equal [ "billing-api" ], names
  end

  test "search matches the hostname it serves" do
    get apps_path(q: "shop.example")
    assert_equal [ "acme-web" ], names
  end

  test "search matches the app it was installed from" do
    get apps_path(q: "nginx")
    assert_equal [ "acme-web" ], names
  end

  # The box is the thing an operator most often has in hand ("what's on node-005?"),
  # and it is a join away, so it is worth reaching for.
  test "search matches the box it runs on" do
    get apps_path(q: "node-005")
    assert_equal [ "acme-web" ], names
  end

  test "a search that matches nothing says so and offers a way back" do
    get apps_path(q: "nothing-like-this")
    assert_response :success
    assert_select ".empty", /No apps match/
    assert_select ".empty a[href=?]", apps_path
  end

  test "an empty query is not a filter" do
    get apps_path(q: "   ")
    assert_equal [ "acme-web", "billing-api" ], names.sort
  end

  test "the grouped view is its own URL, and search survives changing the grouping" do
    get apps_path(q: "billing", group: "project")
    assert_response :success
    assert_select "input[name=q][value=?]", "billing"
    assert_equal [ "billing-api" ], names
    # Every group-by chip carries the active query, so switching axis never loses it.
    assert_select ".action-chips a[href=?]", apps_path(group: "fleet", q: "billing")
    # …and searching again keeps the grouping, through the toolbar's hidden field.
    assert_select ".toolbar-search input[type=hidden][name=group][value=?]", "project"
  end

  test "the page opens grouped by state, and the chip says so" do
    get apps_path
    assert_response :success
    assert_select ".action-chips .chip.on", text: "State"
    assert_select ".group-head .group-name", text: "Running"
    assert_select ".group-head .group-count", text: "2"
  end

  test "the headline counts placements and what needs a person" do
    get apps_path
    assert_select ".headline", /2 apps/
    assert_select ".headline .ok", /all running as asked/

    @api.placements.first.update!(status: "failed")
    get apps_path
    assert_select ".headline .bad", /1 need a look/
  end

  # A list must not ask the database once per row; the index preloads what both the
  # row and the groupings read.
  test "the list does not query per row" do
    counts = [ 2, 10 ].map do |n|
      n.times do |i|
        inst = @acme.apps.create!(name: "bulk-#{n}-#{i}", image: "x@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc")
        inst.placements.create!(machine: @box, status: "running")
      end
      queries = 0
      sub = ->(*) { queries += 1 }
      ActiveSupport::Notifications.subscribed(sub, "sql.active_record") { get apps_path }
      queries
    end
    assert_operator counts.last, :<=, counts.first + 2,
                    "query count grew with the number of rows: #{counts.inspect}"
  end
end
