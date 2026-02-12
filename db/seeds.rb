# Development seed data
user = User.find_or_create_by!(email: "test@screenote.app") do |u|
  u.password = "password"
  u.confirmed_at = Time.current
end

user.owned_projects.find_or_create_by!(name: "Demo Project") do |p|
  p.description = "A sample project for testing."
end

puts "Seed data created. Login: test@screenote.app / password"
