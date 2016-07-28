require 'httparty'

module PosthavenTheme
  include HTTParty
  @@current_api_call_count = 0
  @@total_api_calls = 40

  class APIError < StandardError
    attr_accessor :response

    def initialize(response)
      @response = response
    end

    def message
      "#{@response.code} #{response_error_message(response)}"
    end

    private

    def response_error_message(response)
      errors = @response.parsed_response ? @response.parsed_response["errors"] : @response.body
      case errors
      when NilClass
        ''
      when String
        errors.strip
      when Array
        errors.join(", ")
      end
    end
  end

  NOOPParser = Proc.new {|data, format| {} }
  TIMER_RESET = 10
  PERMIT_LOWER_LIMIT = 3

  DEFAULT_API_ENDPOINT = 'https://api.posthaven.com/v1'

  def self.test?
    ENV['test']
  end

  def self.manage_timer(response)
    return unless response.headers['x-posthaven-api-call-limit']
    @@current_api_call_count, @@total_api_calls = response.headers['x-posthaven-api-call-limit']
                                                          .split('/')
    @@current_timer = Time.now if @current_timer.nil?
  end

  def self.critical_permits?
    @@total_api_calls.to_i - @@current_api_call_count.to_i < PERMIT_LOWER_LIMIT
  end

  def self.passed_api_refresh?
    delta_seconds > TIMER_RESET
  end

  def self.delta_seconds
    Time.now.to_i - @@current_timer.to_i
  end

  def self.needs_sleep?
    critical_permits? && !passed_api_refresh?
  end

  def self.sleep
    if needs_sleep?
      Kernel.sleep(TIMER_RESET - delta_seconds)
      @current_timer = nil
    end
  end

  def self.api_usage
    "[API Limit: #{@@current_api_call_count || "??"}/#{@@total_api_calls || "??"}]"
  end

  def self.theme_list
    handle_response(get(themes_path))
  end

  def self.create_theme(data)
    handle_response(post(themes_path, body: {theme: data}))
  end

  def self.asset_list
    handle_response(get(assets_path))
  end

  def self.get_asset(asset)
    handle_response(get(asset_path(asset)))
  end

  def self.send_asset(data)
    handle_response(put(asset_path(data[:path]), body: {asset: data}))
  end

  def self.delete_asset(asset)
    handle_response(delete(asset_path(asset)))
  end

  def self.config
    @config
  end

  def self.config=(config)
    @config = config && Hash[config.map { |k, v| [k.to_sym, v] }]
    setup
  end

  def self.themes_path
    '/themes.json'
  end
  def self.theme_path(theme_id = config[:theme_id])
    "/themes/#{theme_id}"
  end

  def self.assets_path
    theme_path + "/assets.json"
  end
  def self.asset_path(path)
    theme_path + "/asset.json?path=#{path}"
  end

  def self.ignore_files
    (config[:ignore_files] || []).compact.map { |r| Regexp.new(r) }
  end

  def self.whitelist_files
    (config[:whitelist_files] || []).compact
  end

  def self.is_binary_data?(string)
    if string.respond_to?(:encoding)
      string.encoding == "US-ASCII"
    else
      unless string.empty?
        (string.count("^ -~", "^\r\n").fdiv(string.size) > 0.3 || string.index("\x00"))
      end
    end
  end

  private

  def self.handle_response(response)
    manage_timer(response)

    if response.success?
      if response.parsed_response
        response.parsed_response["data"]
      else
        response
      end
    else
      raise APIError.new(response)
    end
  end

  def self.setup
    # Basics
    basic_auth config[:email], config[:api_key]
    base_uri (config[:api_endpoint] || DEFAULT_API_ENDPOINT)

    # Dev
    debug_output $stdout  if config[:debug] || ENV['PHTHEME_DEBUG']
    require 'resolv-replace'  if base_uri.include?(':')
    default_options.update(verify: false)  if ENV['PHTHEME_IGNORE_SSL_VERIFY']
  end
end
