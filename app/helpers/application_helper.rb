require "digest"

module ApplicationHelper
  ANNOTATION_AUTHOR_COLOR_COUNT = 10

  def annotation_author_initials(author)
    return "AI" unless author.respond_to?(:email) && author.email.present?

    local_part, domain = author.email.downcase.split("@", 2)
    words = local_part.scan(/[a-z0-9]+/)

    if words.length > 1
      words.first(2).filter_map { |word| word[0] }.join.upcase
    elsif local_part.present?
      first = local_part[0]
      domain_label = domain.to_s.split(".").first.to_s
      second = if domain_label.start_with?(first) && domain_label.length > 1
        domain_label[1]
      else
        local_part[1]
      end

      [ first, second ].compact.join.upcase
    else
      "?"
    end
  end

  def annotation_author_color(author)
    return "annotation-author-color--ai" unless author.respond_to?(:email) && author.email.present?

    digest = Digest::SHA256.hexdigest(author.email.downcase)
    "annotation-author-color--#{digest.first(8).to_i(16) % ANNOTATION_AUTHOR_COLOR_COUNT}"
  end
end
