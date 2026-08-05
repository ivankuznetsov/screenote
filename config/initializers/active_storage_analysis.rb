# frozen_string_literal: true

# Active Storage enqueues its own analyzer whenever a blob is attached. Keep
# that decoder path behind the same process-wide guard as Screenote's explicit
# dimension, thumbnail, crop, and upload work.
Rails.application.config.after_initialize do
  ActiveStorage::AnalyzeJob.around_perform do |_job, operation|
    ImageDecoding::Guard.synchronize(&operation)
  end
end
