# Rails security update

Updated Rails from 8.1.3.1 to 8.1.4.1 for the November 4, 2026 security release. The conservative dependency resolution also updates the required HTML sanitizer chain: rails-html-sanitizer 1.7.2, Loofah 2.25.3, and Nokogiri 1.19.7. No application or schema changes.

The dependency audit also identified vulnerable Rack, Addressable, Crass, Net::SSH, and SQLite3 versions; these are updated conservatively to patched releases.
