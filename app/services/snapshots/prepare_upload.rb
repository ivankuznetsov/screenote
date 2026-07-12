# frozen_string_literal: true

module Snapshots
  class PrepareUpload
    VERSION = 1
    MAX_ENTRIES = 100
    ISO8601_OFFSET_SUFFIX = /(?:Z|[+-]\d{2}:\d{2})\z/

    Result = Data.define(:snapshot, :created)
    Entry = Data.define(:page, :title, :viewport, :mime_type, :content_sha256, :file_ref_sha256)
    Group = Data.define(:digest, :page, :title, :entries)
    Contract = Data.define(:git_commit, :taken_at, :manifest_digest, :groups)

    class Error < StandardError
      attr_reader :code, :details

      def initialize(message, code:, details: nil)
        super(message)
        @code = code
        @details = details
      end
    end

    class InvalidContract < Error
      def initialize(message, details: nil)
        super(message, code: "invalid_manifest", details: details)
      end
    end

    class Conflict < Error
      def initialize(message)
        super(message, code: "manifest_conflict")
      end
    end

    class << self
      def call(project:, payload:)
        new(project:, payload:).call
      end

      def digest(namespace, components)
        encoded = String.new(encoding: Encoding::BINARY)
        encoded << namespace.b << "\0"
        components.each do |component|
          value = component.to_s.encode(Encoding::UTF_8)
          encoded << value.bytesize.to_s << ":" << value.b
        end
        Digest::SHA256.hexdigest(encoded)
      end
    end

    def initialize(project:, payload:)
      @project = project
      @payload = payload
      @attempts = 0
    end

    def call
      contract = normalize_contract
      existing = project.snapshots.find_by(manifest_digest: contract.manifest_digest)
      return resume_existing(existing, contract) if existing

      Result.new(snapshot: create_graph!(contract), created: true)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      existing = project.snapshots.find_by(manifest_digest: contract&.manifest_digest)
      return resume_existing(existing, contract) if existing

      @attempts += 1
      retry if @attempts == 1

      raise
    end

    private

    attr_reader :project, :payload

    def resume_existing(existing, contract)
      snapshot = verify_existing!(existing, contract)
      EnsureProcessing.call(snapshot: snapshot)
      Result.new(snapshot: snapshot, created: false)
    end

    def normalize_contract
      raw = payload.respond_to?(:to_h) ? payload.to_h.deep_symbolize_keys : {}
      invalid!("version must be 1") unless raw[:version] == VERSION

      git_commit = normalized_git_commit(raw[:git_commit])
      taken_at = normalized_taken_at(raw[:taken_at])
      supplied_digest = normalized_sha(raw[:manifest_digest], "manifest_digest")
      entries = normalized_entries(raw[:entries])
      groups = build_groups(entries)
      expected_digest = self.class.digest(
        "screenote-manifest-v1",
        [ VERSION, git_commit, taken_at.utc.iso8601(6), entries.length ] +
          entries.flat_map { |entry| entry.to_h.values }
      )
      invalid!("manifest_digest does not match the normalized contract") unless supplied_digest == expected_digest

      Contract.new(
        git_commit: git_commit,
        taken_at: taken_at,
        manifest_digest: supplied_digest,
        groups: groups
      )
    rescue EncodingError, TypeError, ArgumentError => e
      invalid!(e.message)
    end

    def normalized_git_commit(value)
      invalid!("git_commit must be a string") unless value.is_a?(String)

      normalized = value.strip.downcase
      invalid!("git_commit must be 7-40 hexadecimal characters") unless normalized.match?(Snapshot::GIT_COMMIT_FORMAT)
      normalized
    end

    def normalized_taken_at(value)
      invalid!("taken_at must be an ISO 8601 timestamp with an explicit UTC offset") unless value.is_a?(String) && value.match?(ISO8601_OFFSET_SUFFIX)

      parsed = Time.iso8601(value).utc
      invalid!("taken_at can't be in the future") if parsed > Time.current + Snapshot::FUTURE_SKEW
      parsed
    rescue ArgumentError
      invalid!("taken_at must be an ISO 8601 timestamp with an explicit UTC offset")
    end

    def normalized_entries(raw_entries)
      invalid!("entries must contain 1..#{MAX_ENTRIES} images") unless raw_entries.is_a?(Array) && (1..MAX_ENTRIES).cover?(raw_entries.length)

      entries = raw_entries.map.with_index { |entry, index| normalized_entry(entry, index) }
      duplicates = entries.group_by { |entry| [ entry.page, entry.title, entry.viewport ] }.select { |_key, grouped| grouped.length > 1 }
      invalid!("viewport must be unique within each page and title group") if duplicates.any?
      entries
    end

    def normalized_entry(raw_entry, index)
      invalid!("entries[#{index}] must be an object") unless raw_entry.respond_to?(:to_h)

      entry = raw_entry.to_h.deep_symbolize_keys
      page = normalized_label(entry[:page], "entries[#{index}].page")
      title = entry[:title].nil? ? page : normalized_label(entry[:title], "entries[#{index}].title")
      viewport = normalized_enum(entry[:viewport], ScreenshotImage.viewports.keys, "entries[#{index}].viewport")
      mime_type = normalized_enum(entry[:mime_type], ScreenshotImage::ALLOWED_CONTENT_TYPES, "entries[#{index}].mime_type")

      Entry.new(
        page: page,
        title: title,
        viewport: viewport,
        mime_type: mime_type,
        content_sha256: normalized_sha(entry[:content_sha256], "entries[#{index}].content_sha256"),
        file_ref_sha256: normalized_sha(entry[:file_ref_sha256], "entries[#{index}].file_ref_sha256")
      )
    end

    def normalized_label(value, field)
      invalid!("#{field} must be a string") unless value.is_a?(String)

      normalized = value.strip
      invalid!("#{field} can't be blank") if normalized.blank?
      invalid!("#{field} is too long (maximum is 255 characters)") if normalized.length > 255
      normalized
    end

    def normalized_enum(value, allowed, field)
      invalid!("#{field} must be a string") unless value.is_a?(String) || value.is_a?(Symbol)

      normalized = value.to_s.strip.downcase
      invalid!("#{field} must be one of #{allowed.join(', ')}") unless normalized.in?(allowed)
      normalized
    end

    def normalized_sha(value, field)
      invalid!("#{field} must be a string") unless value.is_a?(String)

      normalized = value.strip.downcase
      invalid!("#{field} #{Snapshot::SHA256_ERROR_MESSAGE}") unless normalized.match?(Snapshot::SHA256_FORMAT)
      normalized
    end

    def build_groups(entries)
      entries.group_by { |entry| [ entry.page, entry.title ] }.map do |(page, title), grouped_entries|
        components = [ page, title, grouped_entries.length ] + grouped_entries.flat_map do |entry|
          [ entry.viewport, entry.mime_type, entry.content_sha256, entry.file_ref_sha256 ]
        end
        Group.new(
          digest: self.class.digest("screenote-screenshot-v1", components),
          page: page,
          title: title,
          entries: grouped_entries
        )
      end
    end

    def create_graph!(contract)
      snapshot = nil
      Snapshot.transaction do
        snapshot = project.snapshots.create!(
          git_commit: contract.git_commit,
          taken_at: contract.taken_at,
          manifest_digest: contract.manifest_digest
        )
        contract.groups.each do |group|
          page = Page.find_or_create_by_name!(project, group.page)
          screenshot = snapshot.screenshots.create!(
            page: page,
            title: group.title,
            manifest_entry_digest: group.digest
          )
          group.entries.each do |entry|
            screenshot.screenshot_images.create!(
              viewport: entry.viewport,
              content_sha256: entry.content_sha256,
              expected_content_type: entry.mime_type
            )
          end
        end
      end
      snapshot
    end

    def verify_existing!(snapshot, contract)
      conflict!("manifest snapshot is missing") unless snapshot
      conflict!("snapshot metadata does not match its manifest") unless
        snapshot.git_commit == contract.git_commit &&
          snapshot.taken_at.utc.iso8601(6) == contract.taken_at.utc.iso8601(6)

      screenshots = snapshot.screenshots.includes(:page, :screenshot_images).index_by(&:manifest_entry_digest)
      conflict!("stored screenshot membership does not match the manifest") unless screenshots.length == contract.groups.length

      contract.groups.each do |group|
        screenshot = screenshots[group.digest]
        conflict!("stored screenshot membership does not match the manifest") unless screenshot
        conflict!("stored screenshot metadata does not match the manifest") unless
          screenshot.title == group.title && screenshot.page.name.casecmp?(group.page)

        images = screenshot.screenshot_images.index_by(&:viewport)
        conflict!("stored viewport membership does not match the manifest") unless images.length == group.entries.length
        group.entries.each do |entry|
          image = images[entry.viewport]
          conflict!("stored image identity does not match the manifest") unless
            image && image.content_sha256 == entry.content_sha256 && image.expected_content_type == entry.mime_type
        end
      end

      snapshot
    end

    def invalid!(message)
      raise InvalidContract, message
    end

    def conflict!(message)
      raise Conflict, message
    end
  end
end
