require "test_helper"

# Labels are a control-plane act with no box, so they land in Steward Console's own
# record, attributed to the signed-in human, and recorded together with the change.
class LabelsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @machine = Machine.create!(name: "box-#{SecureRandom.hex(3)}", ssh_host: "1.1.1.1")
    sign_in_as @user
  end

  test "adding a label creates it and records an attributed act" do
    assert_difference [ "Label.count", "Event.count" ], 1 do
      post machine_labels_path(@machine), params: { label: { key: "env", value: "prod" } }
    end
    assert_redirected_to @machine
    assert_equal "env=prod", @machine.labels.first.to_s

    e = Event.latest.first
    assert_equal @user.email_address, e.actor
    assert_equal "added label", e.action
    assert_equal @machine, e.machine
  end

  test "an invalid label records nothing and changes nothing (atomic)" do
    @machine.labels.create!(key: "env", value: "a")
    assert_no_difference [ "Label.count", "Event.count" ] do
      post machine_labels_path(@machine), params: { label: { key: "env", value: "b" } }
    end
  end

  test "removing a label records an attributed act" do
    label = @machine.labels.create!(key: "team", value: "web")
    assert_difference "Event.count", 1 do
      assert_difference "Label.count", -1 do
        delete label_path(label)
      end
    end
    e = Event.latest.first
    assert_equal "removed label", e.action
    assert_equal @user.email_address, e.actor
  end
end
