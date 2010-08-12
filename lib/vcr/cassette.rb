require 'fileutils'
require 'yaml'
require 'erb'

module VCR
  class Cassette
    class MissingERBVariableError < NameError; end

    VALID_RECORD_MODES = [:all, :none, :new_episodes].freeze

    attr_reader :name, :record_mode, :match_requests_on

    def initialize(name, options = {})
      options = VCR::Config.default_cassette_options.merge(options)
      invalid_options = options.keys - [:record, :erb, :allow_real_http, :match_requests_on]

      if invalid_options.size > 0
        raise ArgumentError.new("You passed the following invalid options to VCR::Cassette.new: #{invalid_options.inspect}.")
      end

      @name, @record_mode, @erb, @match_requests_on = name, options[:record], options[:erb], options[:match_requests_on]

      deprecate_old_cassette_options(options)
      raise_error_unless_valid_record_mode(record_mode)

      set_http_connections_allowed
      load_recorded_interactions
    end

    def eject
      write_recorded_interactions_to_disk
      VCR.http_stubbing_adapter.restore_stubs_checkpoint(name)
      restore_http_connections_allowed
      restore_ignore_localhost_for_deprecation
    end

    def recorded_interactions
      @recorded_interactions ||= []
    end

    def record_http_interaction(interaction)
      recorded_interactions << interaction
    end

    def file
      File.join(VCR::Config.cassette_library_dir, "#{sanitized_name}.yml") if VCR::Config.cassette_library_dir
    end

    private

    def sanitized_name
      name.to_s.gsub(/[^\w\-\/]+/, '_')
    end

    def raise_error_unless_valid_record_mode(record_mode)
      unless VALID_RECORD_MODES.include?(record_mode)
        raise ArgumentError.new("#{record_mode} is not a valid cassette record mode.  Valid options are: #{VALID_RECORD_MODES.inspect}")
      end
    end

    def new_recorded_interactions
      recorded_interactions - @original_recorded_interactions
    end

    def should_allow_http_connections?
      [:new_episodes, :all].include?(record_mode)
    end

    def set_http_connections_allowed
      @orig_http_connections_allowed = VCR.http_stubbing_adapter.http_connections_allowed?
      VCR.http_stubbing_adapter.http_connections_allowed = should_allow_http_connections?
    end

    def restore_http_connections_allowed
      VCR.http_stubbing_adapter.http_connections_allowed = @orig_http_connections_allowed
    end

    def load_recorded_interactions
      VCR.http_stubbing_adapter.create_stubs_checkpoint(name)
      @original_recorded_interactions = []
      return if record_mode == :all

      if file
        @original_recorded_interactions = begin
          interactions = YAML.load(raw_yaml_content)

          if VCR.http_stubbing_adapter.ignore_localhost?
            interactions.reject! do |i|
              i.uri.is_a?(String) && VCR::LOCALHOST_ALIASES.include?(URI.parse(i.uri).host)
            end
          end

          interactions
        rescue TypeError
          raise unless raw_yaml_content =~ /VCR::RecordedResponse/
          raise "The VCR cassette #{sanitized_name}.yml uses an old format that is now deprecated.  VCR provides a rake task to migrate your old cassettes to the new format.  See http://github.com/myronmarston/vcr/blob/master/CHANGELOG.md for more info."
        end if File.exist?(file)

        recorded_interactions.replace(@original_recorded_interactions)
      end

      VCR.http_stubbing_adapter.stub_requests(recorded_interactions, match_requests_on)
    end

    @@struct_cache = Hash.new do |hash, attributes|
      hash[attributes] = Struct.new(*attributes)
    end

    def raw_yaml_content
      content = File.read(file)
      return content unless @erb

      template = ERB.new(content)

      begin
        return template.result unless @erb.is_a?(Hash)

        # create an object with methods for each desired local variable...
        local_variables = @@struct_cache[@erb.keys].new(*@erb.values)

        # instance_eval seems to be the only way to get the binding for ruby 1.9: http://redmine.ruby-lang.org/issues/show/2161
        template.result(local_variables.instance_eval { binding })
      rescue NameError => e
        var_name = e.message[/undefined local variable or method `(.*)' for/, 1].to_sym
        example_hash = (@erb.is_a?(Hash) ? @erb : {}).merge(var_name => 'some value')

        raise MissingERBVariableError.new(
          "The ERB in the #{sanitized_name}.yml cassette file references undefined variable #{var_name}.  " +
          "Pass it to the cassette using :erb => #{ example_hash.inspect }."
        )
      end
    end

    def write_recorded_interactions_to_disk
      if VCR::Config.cassette_library_dir && new_recorded_interactions.size > 0
        directory = File.dirname(file)
        FileUtils.mkdir_p directory unless File.exist?(directory)
        File.open(file, 'w') { |f| f.write recorded_interactions.to_yaml }
      end
    end
  end
end
