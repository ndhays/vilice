# Shared list search. `key=value` / bare-key tokens match labels; free text is a
# name substring (mirrors the record's selector grammar — see Event.search). Lifted
# out of AppTemplate.search so AppTemplate, Project (and later Machine) share one parser, per
# decisions/open/list-search.md. Requires the model to have a `name` column and to
# be polymorphically `labelable`.
module Searchable
  extend ActiveSupport::Concern

  class_methods do
    def search(query)
      scope = all
      free  = []
      query.to_s.split.each do |token|
        key, sep, value = token.partition("=")
        if sep == "=" && value.present?
          scope = scope.where(id: search_label_ids(key: key, value: value))
        else
          free << token
        end
      end
      if free.any?
        by_name  = where("name LIKE ?", "%#{free.join(' ')}%")
        by_label = where(id: search_label_ids(key: free))
        scope = scope.merge(by_name.or(by_label))
      end
      scope
    end

    # Label ids for this model's type — `name` is the AR class name ("App", "Project").
    def search_label_ids(**conditions)
      Label.where(labelable_type: name, **conditions).select(:labelable_id)
    end
  end
end
