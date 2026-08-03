require "test_helper"

class LabelTest < ActiveSupport::TestCase
  def machine(**attrs)
    Machine.create!({ name: "box-#{SecureRandom.hex(4)}", ssh_host: "10.0.0.1" }.merge(attrs))
  end

  test "a key with a value, and a bare key, are both valid" do
    m = machine
    assert m.labels.create(key: "env", value: "prod").valid?
    assert m.labels.create(key: "shared").valid?
  end

  test "key is required and format-checked" do
    m = machine
    refute m.labels.create(key: "").valid?
    refute m.labels.create(key: "no spaces").valid?
    assert m.labels.create(key: "team/web_1.0").valid?
  end

  test "a key is unique per record but shared across records" do
    a, b = machine, machine
    assert a.labels.create(key: "env", value: "prod").valid?
    refute a.labels.create(key: "env", value: "staging").valid?, "same key twice on one record"
    assert b.labels.create(key: "env", value: "prod").valid?, "same key on another record is fine"
  end

  test "blank value normalizes to nil; key is trimmed" do
    m = machine
    l = m.labels.create!(key: "  region  ", value: "  ")
    assert_equal "region", l.key
    assert_nil l.value
  end

  test "to_s renders key=value or a bare key" do
    assert_equal "env=prod", Label.new(key: "env", value: "prod").to_s
    assert_equal "shared", Label.new(key: "shared").to_s
  end

  test "labels are polymorphic across projects and machines" do
    p = Project.create!(name: "Proj-#{SecureRandom.hex(4)}")
    p.labels.create!(key: "tier", value: "gold")
    m = machine
    m.labels.create!(key: "tier", value: "gold")
    assert_equal "gold", p.labels.first.value
    assert_equal "gold", m.labels.first.value
    assert_equal 2, Label.with_key("tier").count
  end
end
