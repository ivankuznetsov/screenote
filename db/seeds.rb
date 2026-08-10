if Rails.env.development? && Screenote::Deployment.current.saas?
  user = User.find_or_create_by!(email: "test@screenote.app") do |record|
    record.password = "password"
    record.confirmed_at = Time.current
  end

  project = user.owned_projects.find_or_create_by!(name: "Demo Project") do |record|
    record.description = "A sample project for testing."
  end

  project.pages.find_or_create_by!(name: "Home")

  # Give the development user a Pro subscription so all features are available.
  subscription = user.subscription || user.create_subscription!(
    stripe_customer_id: "cus_seed_test_#{user.id}"
  )
  subscription.update!(
    stripe_subscription_id: subscription.stripe_subscription_id || "sub_seed_test_#{user.id}",
    plan: :pro,
    status: :active,
    current_period_end: 1.year.from_now
  )

  User.find_or_create_by!(email: "free@screenote.app") do |record|
    record.password = "password"
    record.confirmed_at = Time.current
  end

  puts "Seed data created."
  puts "  Pro user:  test@screenote.app / password"
  puts "  Free user: free@screenote.app / password"
elsif Rails.env.development?
  puts "Self-hosted development starts with zero accounts; open the application to create the administrator."
else
  puts "Seed data is development-only; no accounts were created."
end
