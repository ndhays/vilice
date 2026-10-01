# A deploy from the machine page: fields in, the box's deploy envelope out.
#
# Stateless on purpose, like the paste box it replaces (Machines::AppsController): no App
# row, no stored spec. The envelope is sent to the box on stdin and discarded; what
# happened is read back from the box. An app that should be tracked — its intention, its
# placements, its drift — goes through Apps instead.
#
# The envelope is the shape `vilice deploy` reads (vilice/internal/app/deploy.go,
# deployEnvelope): `{ "app" => spec, "secret_values" => { NAME => value } }`. The spec is
# recorded on the box by digest; secret values ride beside it and are never recorded.
#
# The fields are the common case — image, hostnames, port, health, env, secrets,
# volumes. What a template carries beyond them (release, accessories, processes) rides
# along in `extras`, untouched. A spec pasted whole replaces the fields entirely, for
# anything the form does not have a field for.
class BoxDeploy
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :name, :string
  attribute :image, :string
  attribute :hostnames, :string   # one per line
  attribute :port, :string
  attribute :health, :string
  attribute :env, :string         # KEY=value, one per line — recorded
  attribute :secrets, :string     # NAME=value, one per line — off-record
  attribute :volumes, :string     # name:/path, one per line
  attribute :extras, :string      # JSON: spec fields the form has no field for
  attribute :pasted, :string      # JSON: a whole spec, instead of the fields
  attribute :template_id, :integer

  validates :name, presence: true,
                   format: { with: AppTemplate::NAME_FORMAT, allow_blank: true,
                             message: "must start with a letter or digit, then letters, digits, dashes, and underscores" }
  validate :spec_is_readable
  validate :image_given, unless: :pasted?
  validate :pairs_well_formed, unless: :pasted?

  # Prefill from a template: its defaults and its latest version's image. Secret names
  # are listed with no value — the value is the operator's to type, every time.
  def self.from_template(template, name: nil)
    new(template_id: template.id,
        name: name.presence || template.name,
        image: template.latest_version&.image,
        port: template.port&.to_s, health: template.health,
        env: template.env_recorded.map { |k| "#{k}=" }.join("\n"),
        secrets: template.secret_keys.map { |k| "#{k}=" }.join("\n"),
        extras: extras_of(template))
  end

  def self.extras_of(template)
    x = { "release" => template.release.presence, "accessories" => template.accessories.presence,
          "processes" => template.processes.presence }.compact
    x.empty? ? nil : JSON.generate(x)
  end

  def pasted? = pasted.present?

  # The spec as the box will record it (by digest). No values that are secret.
  def spec
    return pasted_spec if pasted?

    s = { "image" => image.to_s.strip, "hostnames" => lines(hostnames) }
    s["port"]    = port.to_i if port.present?
    s["health"]  = health.strip if health.present?
    s["env"]     = pairs(env) if pairs(env).any?
    s["secrets"] = pairs(secrets).keys if pairs(secrets).any?
    s["volumes"] = lines(volumes) if lines(volumes).any?
    s.merge(parsed(extras) || {})
  end

  def secret_values = pasted? ? {} : pairs(secrets)

  # What goes to the box on stdin.
  def envelope
    e = { "app" => spec }
    e["secret_values"] = secret_values if secret_values.any?
    e
  end

  # The envelope as shown on the page: every secret value replaced. The page shows what
  # will be sent, and a value typed a moment ago is not something to print back.
  def shown_envelope
    e = { "app" => spec }
    e["secret_values"] = secret_values.transform_values { "••••••" } if secret_values.any?
    e
  end

  def command = Mutation.command("deploy", nil, name: name)

  private

  def lines(text) = text.to_s.split("\n").map(&:strip).reject(&:blank?)

  # KEY=value lines to a hash. The value may itself contain "=".
  def pairs(text)
    lines(text).to_h { |l| k, v = l.split("=", 2); [ k.strip, v.to_s ] }
  end

  def parsed(json)
    return nil if json.blank?
    v = JSON.parse(json)
    v.is_a?(Hash) ? v : nil
  rescue JSON::ParserError
    nil
  end

  # A pasted spec may be the spec itself or a whole envelope; either reads as the spec.
  def pasted_spec
    v = parsed(pasted) || {}
    v.key?("app") && v["app"].is_a?(Hash) ? v["app"] : v.except("name")
  end

  def spec_is_readable
    errors.add(:pasted, "is not a JSON object") if pasted? && parsed(pasted).nil?
    errors.add(:base, "The template's extra fields could not be read") if extras.present? && parsed(extras).nil?
  end

  # Only what the form must check; everything else — the digest pin, the port range,
  # the volume paths — is the box's to judge, and it refuses at the render boundary.
  # Two sets of rules would drift apart.
  def image_given
    errors.add(:image, "is required") if image.blank?
  end

  def pairs_well_formed
    { env: env, secrets: secrets }.each do |field, text|
      lines(text).each do |l|
        key = l.split("=", 2).first.to_s.strip
        errors.add(field, "has a line without a NAME=value: #{l.truncate(40)}") unless l.include?("=")
        errors.add(field, "name #{key.inspect} must be letters, digits and underscores, not starting with a digit") unless key.match?(AppTemplate::ENV_NAME)
      end
    end
    pairs(secrets).each { |k, v| errors.add(:secrets, "#{k} has no value") if v.blank? }
  end
end
