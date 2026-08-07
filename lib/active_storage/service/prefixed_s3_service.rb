# frozen_string_literal: true

require "active_storage/service/s3_service"

module ActiveStorage
  class Service::PrefixedS3Service < Service::S3Service
    def initialize(prefix:, **options)
      @prefix = prefix
      super(**options)
    end

    def delete_prefixed(prefix)
      instrument :delete_prefixed, prefix: prefix do
        bucket.objects(prefix: namespaced_key(prefix)).batch_delete!
      end
    end

    private

    attr_reader :prefix

    def object_for(key)
      bucket.object(namespaced_key(key))
    end

    def upload_stream(key:, **options, &block)
      namespaced = namespaced_key(key)
      if @transfer_manager
        @transfer_manager.upload_stream(key: namespaced, bucket: bucket.name, **options, &block)
      else
        bucket.object(namespaced).upload_stream(**options, &block)
      end
    end

    def namespaced_key(key)
      "#{prefix}/#{key}"
    end
  end
end
