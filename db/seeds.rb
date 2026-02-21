# Development seed data
user = User.find_or_create_by!(email: "test@screenote.app") do |u|
  u.password = "password"
  u.confirmed_at = Time.current
end

project = user.owned_projects.find_or_create_by!(name: "Demo Project") do |p|
  p.description = "A sample project for testing."
end

project.pages.find_or_create_by!(name: "Home")

# Give test user a Pro subscription so all features are available
sub = user.subscription || user.create_subscription!(
  stripe_customer_id: "cus_seed_test_#{user.id}"
)
sub.update!(
  stripe_subscription_id: sub.stripe_subscription_id || "sub_seed_test_#{user.id}",
  plan: :pro,
  status: :active,
  current_period_end: 1.year.from_now
)

# Free-tier user for billing/subscription E2E tests
User.find_or_create_by!(email: "free@screenote.app") do |u|
  u.password = "password"
  u.confirmed_at = Time.current
end

puts "Seed data created."
puts "  Pro user:  test@screenote.app / password"
puts "  Free user: free@screenote.app / password"
