require 'thor'
require 'yaml'
YAML::ENGINE.yamler = 'syck' if defined? Syck
require 'abbrev'
require 'base64'
require 'fileutils'
require 'json'
require 'filewatcher'
require 'mimemagic'

module PosthavenTheme
  EXTENSIONS = [
    {mimetype: 'application/x-liquid', extensions: %w(liquid), parents: 'text/plain'},
    {mimetype: 'application/json', extensions: %w(json), parents: 'text/plain'},
    {mimetype: 'application/js', extensions: %w(map), parents: 'text/plain'},
    {mimetype: 'application/vnd.ms-fontobject', extensions: %w(eot)},
    {mimetype: 'image/svg+xml', extensions: %w(svg svgz)}
  ]

  def self.configure_mime_magic
    PosthavenTheme::EXTENSIONS.each do |extension|
      MimeMagic.add(extension.delete(:mimetype), extension)
    end
  end

  class Cli < Thor
    include Thor::Actions

    IGNORE = %w(config.yml)
    DEFAULT_WHITELIST = %w(layouts/ assets/ config/ snippets/ templates/)
    TIMEFORMAT = "%H:%M:%S"

    NON_CONFIG_COMMANDS = %w{help configure systeminfo}

    def initialize(args = [], local_options = {}, config = {})
      unless NON_CONFIG_COMMANDS.include?(config[:current_command].name)
        setup_config
        validate_config!
      end
      super
    end

    desc "check", "Check configuration"
    def check
      say('Configuration [OK]', :green)  if PosthavenTheme.asset_list
    rescue PosthavenTheme::APIError => e
      report_error(Time.now, 'Configuration [FAIL]', e)
    end

    desc 'configure EMAIL API_KEY [THEME_ID]',
         'Generate a config file – See https://github.com/posthaven/posthaven_theme/#posthaven ' +
         'for information on how to get your api key. Omit theme id to select from existing ' +
         'themes on your account or create a new theme.'
    def configure(email=nil, api_key=nil, theme_id=nil)
      if [email, api_key].any? { |v| v.nil? }
        say('An email and api key are required!', :red)
        help(:configure)
      else
        config = {email: email, api_key: api_key, theme_id: theme_id}
        PosthavenTheme.config = config
        themes = PosthavenTheme.theme_list
        config[:theme_id] ||= select_theme(themes)
        create_file('config.yml', config.to_yaml)
      end
    rescue PosthavenTheme::APIError => e
      report_error(Time.now, 'Configuration Failed', e)
    end

    no_commands do
    end

    desc 'upload FILE', 'Upload all theme assets to site'
    method_option :quiet, type: :boolean, default: false
    def upload(*paths)
      assets = paths.empty? ? local_assets_list : paths
      assets.each do |asset|
        send_asset(asset, options['quiet'])
      end
      say("Done.", :green) unless options['quiet']
    end

    desc 'replace FILE', 'Completely replace site theme assets with local theme assets'
    method_option :quiet, type: :boolean, default: false
    def replace(*paths)
      say('Are you sure you want to completely replace your site theme assets? ' +
          'This is not undoable.',
          :yellow)
      if ask('Continue? (Y/N): ') == 'Y'
        # only delete files on remote that are not present locally
        # files present on remote and present locally get overridden anyway
        remote_assets = if paths.empty?
                          (PosthavenTheme.asset_list.map { |a| a['path'] } - local_assets_list)
                        else
                          paths
                        end
        remote_assets.each do |asset|
          unless PosthavenTheme.ignore_files.any? { |regex| regex =~ asset }
            delete_asset(asset, options['quiet'])
          end
        end
        local_assets = paths.empty? ? local_assets_list : paths
        local_assets.each do |asset|
          send_asset(asset, options['quiet'])
        end
        say("Done.", :green) unless options['quiet']
      end
    rescue PosthavenTheme::APIError => e
      report_error(Time.now, "Replacement failed.", e)
    end

    desc 'remove FILE', 'Remove theme asset'
    method_option :quiet, type: :boolean, default: false
    def remove(*paths)
      paths.each do |path|
        delete_asset(path, options['quiet'])
      end
      say("Done.", :green) unless options['quiet']
    end

    desc 'watch',
         'upload and delete individual theme assets as they change, ' +
         'use the --keep_files flag to disable remote file deletion'
    method_option :quiet, type: :boolean, default: false
    method_option :keep_files, type: :boolean, default: false
    def watch
      puts "Watching current folder: #{Dir.pwd}"
      watcher do |filename, event|
        filename = filename.gsub("#{Dir.pwd}/", '')

        next unless local_assets_list.include?(filename)
        action = if [:changed, :new].include?(event)
          :send_asset
        elsif event == :delete
          :delete_asset
        else
          raise NotImplementedError, "Unknown event -- #{event} -- #{filename}"
        end

        send(action, filename, options['quiet'])
      end
    end

    desc 'systeminfo',
         'print out system information and actively loaded libraries for aiding in submitting bug reports'
    def systeminfo
      ruby_version = "#{RUBY_VERSION}"
      ruby_version += "-p#{RUBY_PATCHLEVEL}" if RUBY_PATCHLEVEL
      puts "Ruby: v#{ruby_version}"
      puts "Operating System: #{RUBY_PLATFORM}"
      %w(Thor Listen HTTParty).each do |lib|
        require "#{lib.downcase}/version"
        puts "#{lib}: v" +  Kernel.const_get("#{lib}::VERSION")
      end
    end

    protected

    def config
      @config ||= YAML.load_file 'config.yml'
    end

    def site_theme_url
      url = config[:site]
      url += "?preview_theme_id=#{config[:theme_id]}" if config[:theme_id] && config[:theme_id].to_i > 0
      url
    end

    private

    def watcher
      FileWatcher.new(Dir.pwd).watch() do |filename, event|
        yield(filename, event)
      end
    end

    def local_assets_list
      local_files.reject do |p|
        @permitted_files ||= (DEFAULT_WHITELIST | PosthavenTheme.whitelist_files).map{|pattern| Regexp.new(pattern)}
        @permitted_files.none? { |regex| regex =~ p } || PosthavenTheme.ignore_files.any? { |regex| regex =~ p }
      end
    end

    def local_files
      Dir.glob(File.join('**', '*')).reject do |f|
        File.directory?(f)
      end
    end

    def download_asset(path)
      return unless valid?(path)
      notify_and_sleep("Approaching limit of API permits. Naptime until more permits become available!") if PosthavenTheme.needs_sleep?
      asset = PosthavenTheme.get_asset(path)
      if asset['value']
        # For CRLF line endings
        content = asset['value'].gsub("\r", "")
        format = "w"
      elsif asset['attachment']
        content = Base64.decode64(asset['attachment'])
        format = "w+b"
      end

      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, format) {|f| f.write content} if content
    rescue PosthavenTheme::APIError => e
      report_error(Time.now, "Could not download #{path}", e)
    end

    def send_asset(asset, quiet=false)
      return unless valid?(asset)
      data = {path: asset}
      content = File.read(asset)
      if binary_file?(asset) || PosthavenTheme.is_binary_data?(content)
        content = File.open(asset, "rb") { |io| io.read }
        data.merge!(attachment: Base64.encode64(content))
      else
        data.merge!(value: content)
      end

      response = show_during("[#{timestamp}] Uploading: #{asset}", quiet) do
        PosthavenTheme.send_asset(data)
      end
      if response.success?
        say("[#{timestamp}] Uploaded: #{asset}", :green) unless quiet
      end
    rescue PosthavenTheme::APIError => e
      report_error(Time.now, "Could not upload #{asset}", e)
    end

    def delete_asset(path, quiet=false)
      return unless valid?(path)
      response = show_during("[#{timestamp}] Removing: #{path}", quiet) do
        PosthavenTheme.delete_asset(path)
      end
      if response.success?
        say("[#{timestamp}] Removed: #{path}", :green) unless quiet
      end
    rescue PosthavenTheme::APIError => e
      report_error(Time.now, "Could not remove #{path}", e)
    end

    def select_theme(existing)
      if yes?('Would you like to use an existing theme? [y/n]')
        existing.sort_by! { |t| t['name'] }
        say("Select from your existing themes:")
        existing.each.with_index do |t, idx|
          say("  %2d – %s" % [idx + 1, t['name']])
        end
        n = ask('Enter the number of the theme above:',
                limited_to: (1..existing.size).map(&:to_s))
        existing[n.to_i - 1]['id']
      else
        create_theme['id']
      end
    end

    def create_theme
      name = ''
      begin
        if (name = ask('What would you like to name your theme?')).size = 0
          say('Oops, the theme needs a name (you can change it later).', :red)
        end
      end  until name.size > 0
      PosthavenTheme.create_theme(name: name)
    end

    def notify_and_sleep(message)
      say(message, :red)
      PosthavenTheme.sleep
    end

    def valid?(path)
      return true if DEFAULT_WHITELIST.include?(path.split('/').first + "/")
      say("'#{path}' is not in a valid file for theme uploads", :yellow)
      say("Files need to be in one of the following subdirectories: #{DEFAULT_WHITELIST.join(' ')}", :yellow)
      false
    end

    def binary_file?(path)
      mime = MimeMagic.by_path(path)
      say("'#{path}' is an unknown file-type, uploading asset as binary", :yellow) if mime.nil? && ENV['TEST'] != 'true'
      mime.nil? || !mime.text?
    end

    def report_error(time, message, error)
      say("[#{timestamp(time)}] Error: #{message}", :red)
      say("Error Details: #{error.message}", :yellow)
    end

    def show_during(message = '', quiet = false, &block)
      print(message) unless quiet
      result = yield
      print("\r#{' ' * message.length}\r") unless quiet
      result
    end

    def timestamp(time = Time.now)
      time.strftime(TIMEFORMAT)
    end

    def setup_config
      if File.exist?('config.yml')
        PosthavenTheme.config = YAML.load(File.read('config.yml'))
      end
    end

    def validate_config!
      if PosthavenTheme.config.empty?
        say 'config.yml does not exist or is empty!', :red
        exit
      elsif %i{api_key theme_id}.any? { |k| PosthavenTheme.config[k].nil? }
        say 'config.yml must include :api_key: and :theme_id:!', :red
        exit
      end
    end
  end
end

PosthavenTheme.configure_mime_magic
