# frozen_string_literal: true

module ::MashReviewDashboard
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace MashReviewDashboard
    config.autoload_paths << File.join(config.root, "lib")

    scheduled_job_dir = "#{config.root}/app/jobs/scheduled"
    config.to_prepare do
      if Dir.exist?(scheduled_job_dir)
        Rails.autoloaders.main.eager_load_dir(scheduled_job_dir)
      end
    end
  end
end
