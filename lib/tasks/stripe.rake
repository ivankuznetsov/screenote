# frozen_string_literal: true

namespace :stripe do
  desc "Reconcile local Subscription rows against Stripe. Use APPLY=1 to commit changes."
  task reconcile_subscriptions: :environment do
    apply = ENV["APPLY"] == "1"
    mode = apply ? "APPLY" : "DRY-RUN"
    puts "[#{mode}] Reconciling subscriptions against Stripe..."
    puts "-" * 80

    stats = { ok: 0, diffs: 0, duplicates: 0, orphans: 0, errors: 0 }

    Subscription.where.not(stripe_customer_id: nil).find_each do |sub|
      user_email = sub.user&.email || "<no user>"

      begin
        stripe_subs = Stripe::Subscription.list(
          customer: sub.stripe_customer_id,
          status: "all",
          limit: 20
        ).data

        non_canceled = stripe_subs.reject { |s| s[:status] == "canceled" }

        if non_canceled.size > 1
          puts "!! #{user_email}: #{non_canceled.size} non-canceled Stripe subs — manual review required"
          non_canceled.each do |s|
            puts "   #{s[:id]} status=#{s[:status]} created=#{Time.at(s[:created]).utc.iso8601}"
          end
          stats[:duplicates] += 1
          next
        end

        stripe_sub = non_canceled.first

        unless stripe_sub
          if sub.plan != "free" || sub.stripe_subscription_id.present?
            puts "~ #{user_email}: no active Stripe sub; local is plan=#{sub.plan} status=#{sub.status} sub_id=#{sub.stripe_subscription_id}"
            sub.update!(plan: :free, status: :canceled, stripe_subscription_id: nil) if apply
            stats[:orphans] += 1
          else
            stats[:ok] += 1
          end
          next
        end

        new_status = Subscription.status_from_stripe(stripe_sub[:status])
        new_period = Subscription.period_end_from_stripe(stripe_sub)&.then { |t| Time.at(t).utc }
        new_sub_id = stripe_sub[:id]
        new_plan = new_status == :active ? :pro : sub.plan.to_sym

        changes = {}
        changes[:stripe_subscription_id] = new_sub_id if sub.stripe_subscription_id != new_sub_id
        changes[:status] = new_status if sub.status.to_sym != new_status
        changes[:plan] = new_plan if sub.plan.to_sym != new_plan
        if new_period && (sub.current_period_end.nil? || (sub.current_period_end.to_i - new_period.to_i).abs > 60)
          changes[:current_period_end] = new_period
        end

        if changes.empty?
          stats[:ok] += 1
        else
          puts "* #{user_email}: #{changes.inspect}"
          sub.update!(**changes) if apply
          stats[:diffs] += 1
        end
      rescue Stripe::StripeError => e
        puts "x #{user_email}: Stripe error — #{e.message}"
        stats[:errors] += 1
      end
    end

    puts "-" * 80
    puts "[#{mode}] Summary: #{stats.inspect}"
    puts "Re-run with APPLY=1 to commit changes." unless apply
  end
end
