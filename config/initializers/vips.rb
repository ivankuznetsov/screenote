# frozen_string_literal: true

require "vips"

# Treat screenshot decodes as a bounded shared resource. The application-level
# guard limits simultaneous operations; these libvips limits bound the worker
# fan-out and retained operation cache inside each web or job process.
Vips.concurrency_set(1)
Vips.cache_set_max(100)
Vips.cache_set_max_mem(64.megabytes)
Vips.cache_set_max_files(20)
