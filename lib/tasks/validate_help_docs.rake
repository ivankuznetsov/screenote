# frozen_string_literal: true

namespace :help_docs do
  desc "Validate that the help page tool documentation matches actual tool definitions"
  task validate: :environment do
    help_path = Rails.root.join("app/views/pages/help.html.erb")

    unless File.exist?(help_path)
      abort "ERROR: Help page not found at #{help_path}"
    end

    html = File.read(help_path)
    doc = Nokogiri::HTML.fragment(html)

    # Extract documented tools from the help page
    documented_tools = extract_documented_tools(doc)

    # Extract actual tool definitions from ApplicationTool subclasses
    actual_tools = extract_actual_tools

    mismatches = compare_tools(actual_tools, documented_tools)

    if mismatches.empty?
      puts "All #{actual_tools.size} tools match their documentation."
    else
      puts "MISMATCHES FOUND:\n\n"
      mismatches.each { |m| puts "  #{m}\n" }
      puts "\n#{mismatches.size} mismatch(es) found."
      exit 1
    end
  end
end

def extract_documented_tools(doc)
  tools = {}

  doc.css(".tool-card").each do |card|
    name = card.at_css(".tool-card__name")&.text&.strip
    next unless name

    params = {}
    card.css(".tool-card__params-list li").each do |li|
      param_name = li.at_css("code")&.text&.strip
      next unless param_name

      is_required = li.at_css(".tool-card__required").present?
      params[param_name] = { required: is_required }
    end

    tools[name] = params
  end

  tools
end

def extract_actual_tools(*)
  tools = {}

  ApplicationTool.subclasses.each do |klass|
    name = klass.tool_name
    schema = klass.input_schema_to_json

    properties = schema&.dig(:properties)&.keys&.map(&:to_s) || []
    required = schema&.dig(:required)&.map(&:to_s) || []

    params = {}
    properties.each do |prop|
      params[prop] = { required: required.include?(prop) }
    end

    tools[name] = params
  end

  tools
end

def compare_tools(actual_tools, documented_tools)
  mismatches = []

  # Check for tools missing from documentation
  (actual_tools.keys - documented_tools.keys).each do |name|
    mismatches << "Tool '#{name}' exists in code but is not documented on the help page."
  end

  # Check for tools documented but not existing
  (documented_tools.keys - actual_tools.keys).each do |name|
    mismatches << "Tool '#{name}' is documented on the help page but does not exist in code."
  end

  # Compare parameters for tools that exist in both
  (actual_tools.keys & documented_tools.keys).sort.each do |name|
    actual_params = actual_tools[name]
    doc_params = documented_tools[name]

    # Check for missing parameters in docs
    (actual_params.keys - doc_params.keys).each do |param|
      status = actual_params[param][:required] ? "required" : "optional"
      mismatches << "Tool '#{name}': parameter '#{param}' (#{status}) exists in code but is not documented."
    end

    # Check for extra parameters in docs
    (doc_params.keys - actual_params.keys).each do |param|
      mismatches << "Tool '#{name}': parameter '#{param}' is documented but does not exist in code."
    end

    # Check required/optional mismatches
    (actual_params.keys & doc_params.keys).each do |param|
      actual_required = actual_params[param][:required]
      doc_required = doc_params[param][:required]

      if actual_required && !doc_required
        mismatches << "Tool '#{name}': parameter '#{param}' is required in code but documented as optional."
      elsif !actual_required && doc_required
        mismatches << "Tool '#{name}': parameter '#{param}' is optional in code but documented as required."
      end
    end
  end

  mismatches
end
