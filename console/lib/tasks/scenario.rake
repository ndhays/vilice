namespace :console do
  desc "Load a demo scenario, e.g. rake console:scenario[all_broken] (or SCENARIO=all_broken)"
  task :scenario, [ :name ] => :environment do |_t, args|
    ENV["SCENARIO"] = args[:name] || ENV["SCENARIO"] || "realistic"
    puts "Loading scenario: #{ENV['SCENARIO']}"
    Rake::Task["db:seed"].invoke
  end
end
