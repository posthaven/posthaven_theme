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


  def self.asset_list
    response = get(path)
    manage_timer(response)

    if response.success?
      assets = JSON.parse(response.body).collect {|a| a['path'] }
      # Remove any .css files if a .css.liquid file exists
      assets.reject{|a| assets.include?("#{a}.liquid") }
    else
      raise APIError.new(response)
    end
  end

  def self.get_asset(asset)
    response = get(path(asset), query: {path: asset})
    manage_timer(response)

    if response.success?
      asset = response.code == 200 ? response.parsed_body["asset"] : {}
      asset['response'] = response
      asset
    else
      raise APIError.new(response)
    end
  end

  def self.send_asset(data)
    response = put(path(data[:path]), query: {path: data[:path]}, body: {asset: data})
    raise APIError.new(response)  unless response.success?

    manage_timer(response)
    response
  end

  def self.delete_asset(asset)
    response = delete(path(asset), query: {path: asset})
    raise APIError.new(response)  unless response.success?

    manage_timer(response)
    response
  end

  def self.config
    @config
  end

  def self.config=(config)
    @config = config && Hash[config.map { |k, v| [k.to_sym, v] }]
    setup
  end

  def self.path(asset_path = nil)
    asset_path ? "/asset.json" : '/assets.json'
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

  def self.setup
    basic_auth config[:email], config[:api_key]
    base_uri (config[:api_endpoint] || DEFAULT_API_ENDPOINT) + "/themes/#{config[:theme_id]}"
    debug_output $stdout  if config[:debug]
    require 'resolv-replace'  if base_uri.include?(':')
  end
end
