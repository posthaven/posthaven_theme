require 'thor'
require 'yaml'
YAML::ENGINE.yamler = 'syck' if defined? Syck
require 'abbrev'
require 'base64'
require 'fileutils'
require 'json'
require 'filewatcher'
require 'launchy'
require 'mimemagic'

module PosthavenTheme
  EXTENSIONS = [
    {mimetype: 'application/x-liquid', extensions: %w(liquid), parents: 'text/plain'},
    {mimetype: 'application/json', extensions: %w(json), parents: 'text/plain'},
    {mimetype: 'application/js', extensions: %w(map), parents: 'text/plain'},
    {mimetype: 'application/vnd.ms-fontobject', extensions: %w(eot)},
    {mimetype: 'image/svg+xml', extensions: %w(svg svgz)}
  ]

  def self.configureMimeMagic
    PosthavenTheme::EXTENSIONS.each do |extension|
      MimeMagic.add(extension.delete(:mimetype), extension)
    end
  end

  class Cli < Thor
    include Thor::Actions

    IGNORE = %w(config.yml)
    DEFAULT_WHITELIST = %w(layouts/ assets/ config/ snippets/ templates/)
    TIMEFORMAT = "%H:%M:%S"

    tasks.keys.abbrev.each do |shortcut, command|
      map shortcut => command.to_sym
    end

    desc "check", "check configuration"
    def check
      if PosthavenTheme.check_config
        say("Configuration [OK]", :green)
      else
        say("Configuration [FAIL]", :red)
      end
    end

    desc 'configure EMAIL API_KEY THEME_ID',
         'generate a config file for the site to connect to'
    def configure(email=nil, api_key=nil, theme_id=nil)
      config = {email: email, api_key: api_key, theme_id: theme_id}
      create_file('config.yml', config.to_yaml)
    end

    # desc "open", "open the site in your browser"
    # def open(*paths)
    #   if Launchy.open site_theme_url
    #     say("Done.", :green)
    #   end
    # end

    desc "upload FILE", "upload all theme assets to site"
    method_option :quiet, type: :boolean, default: false
    def upload(*paths)
      assets = paths.empty? ? local_assets_list : paths
      assets.each do |asset|
        send_asset(asset, options['quiet'])
      end
      say("Done.", :green) unless options['quiet']
    end

    desc "replace FILE", "completely replace site theme assets with local theme assets"
    method_option :quiet, type: :boolean, default: false
    def replace(*paths)
      say("Are you sure you want to completely replace your site theme assets? This is not undoable.", :yellow)
      if ask("Continue? (Y/N): ") == "Y"
        # only delete files on remote that are not present locally
        # files present on remote and present locally get overridden anyway
        remote_assets = paths.empty? ? (PosthavenTheme.asset_list - local_assets_list) : paths
        remote_assets.each do |asset|
          delete_asset(asset, options['quiet']) unless PosthavenTheme.ignore_files.any? { |regex| regex =~ asset }
        end
        local_assets = paths.empty? ? local_assets_list : paths
        local_assets.each do |asset|
          send_asset(asset, options['quiet'])
        end
        say("Done.", :green) unless options['quiet']
      end
    end

    desc "remove FILE", "remove theme asset"
    method_option :quiet, type: :boolean, default: false
    def remove(*paths)
      paths.each do |path|
        delete_asset(path, options['quiet'])
      end
      say("Done.", :green) unless options['quiet']
    end

    desc "watch", "upload and delete individual theme assets as they change, use the --keep_files flag to disable remote file deletion"
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

    desc "systeminfo", "print out system information and actively loaded libraries for aiding in submitting bug reports"
    def systeminfo
      ruby_version = "#{RUBY_VERSION}"
      ruby_version += "-p#{RUBY_PATCHLEVEL}" if RUBY_PATCHLEVEL
      puts "Ruby: v#{ruby_version}"
      puts "Operating System: #{RUBY_PLATFORM}"
      %w(Thor Listen HTTParty Launchy).each do |lib|
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
      else
        report_error(Time.now, "Could not upload #{asset}", response)
      end
    end

    def delete_asset(path, quiet=false)
      return unless valid?(path)
      response = show_during("[#{timestamp}] Removing: #{path}", quiet) do
        PosthavenTheme.delete_asset(path)
      end
      if response.success?
        say("[#{timestamp}] Removed: #{path}", :green) unless quiet
      else
        report_error(Time.now, "Could not remove #{path}", response)
      end
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

    def report_error(time, message, response)
      say("[#{timestamp(time)}] Error: #{message}", :red)
      say("Error Details: #{errors_from_response(response)}", :yellow)
    end

    def errors_from_response(response)
      object = {status: response.headers['status'], request_id: response.headers['x-request-id']}

      errors = response.parsed_response ? response.parsed_response["errors"] : response.body

      object[:errors] = case errors
                        when NilClass
                          ''
                        when String
                          errors.strip
                        else
                          errors.values.join(", ")
                        end
      object.delete(:errors) if object[:errors].length <= 0
      object
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
  end
end
PosthavenTheme.configureMimeMagic
