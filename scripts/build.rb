#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'erb'
require 'erb/util'
require 'yaml'
require 'grim'
require 'date'

include ERB::Util

ROOT_DIR      = File.expand_path('..', __dir__)
SITE_DIR      = File.join(ROOT_DIR, '_site')
TEMPLATES_DIR = File.join(ROOT_DIR, 'templates')
BASE_URL      = 'https://maimux2x.github.io/slides'

IGNORED_DIRS = %w[. .. .git .github scripts templates _site node_modules].freeze

def humanize(folder_name)
  folder_name
    .gsub(/([a-z\d])([A-Z])/, '\1 \2')
    .gsub(/[_-]/, ' ')
    .gsub(/\b(\w)/) { $1.upcase }
end

def load_metadata(folder_path, folder_name)
  meta_path = File.join(folder_path, 'metadata.yml')

  if File.exist?(meta_path)
    meta = YAML.safe_load(File.read(meta_path), permitted_classes: [Date, Time]) || {}
    {
      title:       meta['title'] || humanize(folder_name),
      description: meta['description'] || ''
    }
  else
    {
      title:       humanize(folder_name),
      description: ''
    }
  end
end

def u(value)
  ERB::Util.url_encode(value.to_s)
end

def find_pdf(folder_path)
  pdfs = Dir.glob(File.join(folder_path, '*.pdf'))

  pdfs.first
end

def convert_pdf_to_images(pdf_path, output_dir)
  FileUtils.mkdir_p(output_dir)

  pdf        = Grim.reap(pdf_path)
  page_count = pdf.count

  puts "  Converting #{page_count} pages..."

  pdf.each_with_index do |page, index|
    page_num    = format('%03d', index + 1)
    output_path = File.join(output_dir, "page_#{page_num}.png")

    page.save(output_path, width: 1280)

    print "  Page #{index + 1}/#{page_count}\r"
  end
  puts

  page_count
end

def render_template(template_name, locals = {})
  template_path = File.join(TEMPLATES_DIR, template_name)
  template      = ERB.new(File.read(template_path), trim_mode: '-')

  template.result_with_hash(locals)
end

def build_slide(folder_name, folder_path)
  pdf_path = find_pdf(folder_path)

  return nil unless pdf_path

  puts "Processing: #{folder_name} (#{File.basename(pdf_path)})"

  metadata    = load_metadata(folder_path, folder_name)
  title       = metadata[:title]
  description = metadata[:description]
  site_folder = File.join(SITE_DIR, folder_name)
  pages_dir   = File.join(site_folder, 'pages')

  FileUtils.mkdir_p(pages_dir)

  page_count = convert_pdf_to_images(pdf_path, pages_dir)

  # OGP image: copy first page
  ogp_src = File.join(pages_dir, 'page_001.png')
  ogp_dst = File.join(site_folder, 'ogp.png')

  FileUtils.cp(ogp_src, ogp_dst)

  # Copy original PDF
  pdf_filename = File.basename(pdf_path)

  FileUtils.cp(pdf_path, File.join(site_folder, pdf_filename))

  # Render slide viewer HTML
  html = render_template(
    'slide_viewer.html.erb',
    {
      title:        title,
      description:  description,
      base_url:     BASE_URL,
      folder:       folder_name,
      page_count:   page_count,
      pdf_filename: pdf_filename
    }
  )

  File.write(File.join(site_folder, 'index.html'), html)

  puts "Done: #{page_count} pages, OGP image, HTML generated"

  {
    folder:       folder_name,
    title:        title,
    description:  description,
    page_count:   page_count,
    pdf_filename: pdf_filename
  }
end

def build_index(slides)
  html = render_template('index.html.erb', { base_url: BASE_URL, slides: slides })

  File.write(File.join(SITE_DIR, 'index.html'), html)

  puts "Root index.html generated with #{slides.length} slides"
end

def main
  FileUtils.rm_rf(SITE_DIR)
  FileUtils.mkdir_p(SITE_DIR)

  # Copy .nojekyll
  nojekyll_src = File.join(ROOT_DIR, '.nojekyll')

  FileUtils.cp(nojekyll_src, File.join(SITE_DIR, '.nojekyll')) if File.exist?(nojekyll_src)

  entries = Dir.entries(ROOT_DIR)
    .select { |e| File.directory?(File.join(ROOT_DIR, e)) }
    .reject { |e| IGNORED_DIRS.include?(e) }
    .sort

  slides = []

  entries.each do |folder_name|
    folder_path = File.join(ROOT_DIR, folder_name)
    result      = build_slide(folder_name, folder_path)

    slides << result if result
  end

  build_index(slides)

  puts "Build complete! #{slides.length} slides processed."
  puts "Output: #{SITE_DIR}"
end

main
