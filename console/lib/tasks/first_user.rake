namespace :console do
  desc "Create the first user from CONSOLE_ADMIN_EMAIL and CONSOLE_ADMIN_PASSWORD, if there is none"
  task first_user: :environment do
    if (user = User.create_first(ENV["CONSOLE_ADMIN_EMAIL"], ENV["CONSOLE_ADMIN_PASSWORD"]))
      puts "Created the first user: #{user.email_address}"
    elsif User.none?
      puts "No users yet. Deploy with CONSOLE_ADMIN_EMAIL and a secret CONSOLE_ADMIN_PASSWORD to create one."
    end
  end
end
