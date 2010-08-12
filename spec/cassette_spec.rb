require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe VCR::Cassette do
  describe '#file' do
    temp_dir File.expand_path(File.dirname(__FILE__) + '/fixtures/file'), :assign_to_cassette_library_dir => true

    it 'combines the cassette_library_dir with the cassette name' do
      cassette = VCR::Cassette.new('the_file')
      cassette.file.should == File.join(VCR::Config.cassette_library_dir, 'the_file.yml')
    end

    it 'strips out disallowed characters so that it is a valid file name with no spaces' do
      cassette = VCR::Cassette.new("\nthis \t!  is-the_13212_file name")
      cassette.file.should =~ /#{Regexp.escape('_this_is-the_13212_file_name.yml')}$/
    end

    it 'keeps any path separators' do
      cassette = VCR::Cassette.new("dir/file_name")
      cassette.file.should =~ /#{Regexp.escape('dir/file_name.yml')}$/
    end

    it 'returns nil if the cassette_library_dir is not set' do
      VCR::Config.cassette_library_dir = nil
      cassette = VCR::Cassette.new('the_file')
      cassette.file.should be_nil
    end
  end

  describe '#record_http_interaction' do
    it 'adds the interaction to #recorded_interactions' do
      cassette = VCR::Cassette.new(:test_cassette)
      cassette.recorded_interactions.should == []
      cassette.record_http_interaction(:the_interaction)
      cassette.recorded_interactions.should == [:the_interaction]
    end
  end

  describe '#match_requests_on' do
    before(:each) { VCR::Config.default_cassette_options.merge!(:match_requests_on => [:uri, :method]) }

    it "returns the provided options" do
      c = VCR::Cassette.new('example', :match_requests_on => [:uri])
      c.match_requests_on.should == [:uri]
    end

    it "returns a the default #match_requests_on when it has not been specified for the cassette" do
      c = VCR::Cassette.new('example')
      c.match_requests_on.should == [:uri, :method]
    end
  end

  describe 'on creation' do
    it 'raises an error with a helpful message when loading an old unsupported cassette' do
      VCR::Config.cassette_library_dir = File.expand_path(File.dirname(__FILE__) + "/fixtures/#{YAML_SERIALIZATION_VERSION}")
      lambda { VCR::Cassette.new('0_3_1_cassette') }.should raise_error(/The VCR cassette 0_3_1_cassette.yml uses an old format that is now deprecated/)
    end

    it "raises an error if given an invalid record mode" do
      lambda { VCR::Cassette.new(:test, :record => :not_a_record_mode) }.should raise_error(ArgumentError)
    end

    it 'raises an error if given invalid options' do
      expect {
        VCR::Cassette.new(:test, :invalid => :option)
      }.to raise_error(ArgumentError)
    end

    it 'creates a stubs checkpoint on the http_stubbing_adapter' do
      VCR.http_stubbing_adapter.should_receive(:create_stubs_checkpoint).with('example').once
      VCR::Cassette.new('example')
    end

    describe 'ERB support' do
      before(:each) do
        @orig_default_options = VCR::Config.default_cassette_options
      end

      after(:each) do
        VCR::Config.default_cassette_options = @orig_default_options
      end

      def cassette_body(name, options = {})
        VCR::Config.cassette_library_dir = File.expand_path(File.dirname(__FILE__) + "/fixtures/#{YAML_SERIALIZATION_VERSION}/cassette_spec")
        VCR::Cassette.new(name, options.merge(:record => :new_episodes)).recorded_interactions.first.response.body
      end

      it "compiles a template as ERB if the :erb option is passed as true" do
        cassette_body('erb_with_no_vars', :erb => true).should == 'sum: 3'
      end

      it "compiles a template as ERB if the default :erb option is true, and no option is passed to the cassette" do
        VCR::Config.default_cassette_options = { :erb => true }
        cassette_body('erb_with_no_vars').should == 'sum: 3'
      end

      it "does not compile a template as ERB if the default :erb option is true, and :erb => false is passed to the cassette" do
        VCR::Config.default_cassette_options = { :erb => true }
        cassette_body('erb_with_no_vars', :erb => false).should == 'sum: <%= 1 + 2 %>'
      end

      it "compiles a template as ERB if the :erb option is passed a hash" do
        cassette_body('erb_with_vars', :erb => { :var1 => 'a', :var3 => 'c', :var2 => 'b' }).should == 'var1: a; var2: b; var3: c'
      end

      it "does not compile a template as ERB if the :erb option is not used" do
        cassette_body('erb_with_no_vars').should == 'sum: <%= 1 + 2 %>'
      end

      it "raises a helpful error if the ERB template references variables that are not passed in the :erb hash" do
        expect {
          cassette_body('erb_with_vars', :erb => { :var1 => 'a', :var2 => 'b' })
        }.to raise_error(VCR::Cassette::MissingERBVariableError,
          %{The ERB in the erb_with_vars.yml cassette file references undefined variable var3.  } +
          %{Pass it to the cassette using :erb => #{ { :var1 => 'a', :var2 => 'b' }.merge(:var3 => 'some value').inspect }.}
        )
      end

      it "raises a helpful error if the ERB template references variables and :erb => true is passed" do
        expect {
          cassette_body('erb_with_vars', :erb => true)
        }.to raise_error(VCR::Cassette::MissingERBVariableError,
          %{The ERB in the erb_with_vars.yml cassette file references undefined variable var1.  } +
          %{Pass it to the cassette using :erb => {:var1=>"some value"}.}
        )
      end
    end

    VCR::Cassette::VALID_RECORD_MODES.each do |record_mode|
      http_connections_allowed = (record_mode != :none)
      load_interactions = (record_mode != :all)

      context "when VCR::Config.default_cassette_options[:record] is :#{record_mode}" do
        before(:each) { VCR::Config.default_cassette_options = { :record => record_mode } }

        it "defaults the record mode to #{record_mode} when VCR::Config.default_cassette_options[:record] is #{record_mode}" do
          cassette = VCR::Cassette.new(:test)
          cassette.record_mode.should == record_mode
        end
      end

      context "when the record mode is :#{record_mode}" do
        it "sets http_connections_allowed to #{http_connections_allowed} on the http stubbing adapter" do
          VCR.http_stubbing_adapter.should_receive(:http_connections_allowed=).with(http_connections_allowed)
          VCR::Cassette.new(:name, :record => record_mode)
        end

        if load_interactions

          [true, false].each do |ignore_localhost|
            expected_uri_hosts = %w(example.com)
            expected_uri_hosts += VCR::LOCALHOST_ALIASES unless ignore_localhost

            it "#{ ignore_localhost ? 'does not load' : 'loads' } localhost interactions from the cassette file when http_stubbing_adapter.ignore_localhost is set to #{ignore_localhost}" do
              VCR.http_stubbing_adapter.stub!(:ignore_localhost?).and_return(ignore_localhost)
              VCR::Config.cassette_library_dir = File.expand_path(File.dirname(__FILE__) + "/fixtures/#{YAML_SERIALIZATION_VERSION}/cassette_spec")
              cassette = VCR::Cassette.new('with_localhost_requests', :record => record_mode)
              cassette.recorded_interactions.map { |i| URI.parse(i.uri).host }.should =~ expected_uri_hosts
            end
          end

          it "loads the recorded interactions from the library yml file" do
            VCR::Config.cassette_library_dir = File.expand_path(File.dirname(__FILE__) + "/fixtures/#{YAML_SERIALIZATION_VERSION}/cassette_spec")
            cassette = VCR::Cassette.new('example', :record => record_mode)

            cassette.should have(3).recorded_interactions

            i1, i2, i3 = *cassette.recorded_interactions

            i1.request.method.should == :get
            i1.request.uri.should == 'http://example.com:80/'
            i1.response.body.should =~ /You have reached this web page by typing.+example\.com/

            i2.request.method.should == :get
            i2.request.uri.should == 'http://example.com:80/foo'
            i2.response.body.should =~ /foo was not found on this server/

            i3.request.method.should == :get
            i3.request.uri.should == 'http://example.com:80/'
            i3.response.body.should =~ /Another example\.com response/
          end

          it "stubs the recorded requests with the http stubbing adapter" do
            VCR::Config.cassette_library_dir = File.expand_path(File.dirname(__FILE__) + "/fixtures/#{YAML_SERIALIZATION_VERSION}/cassette_spec")
            VCR.http_stubbing_adapter.should_receive(:stub_requests).with([an_instance_of(VCR::HTTPInteraction)]*3, anything)
            cassette = VCR::Cassette.new('example', :record => record_mode)
          end

          it "passes the :match_request_on option to #stub_requests" do
            VCR::Config.cassette_library_dir = File.expand_path(File.dirname(__FILE__) + "/fixtures/#{YAML_SERIALIZATION_VERSION}/cassette_spec")
            VCR.http_stubbing_adapter.should_receive(:stub_requests).with(anything, [:body, :headers])
            cassette = VCR::Cassette.new('example', :record => record_mode, :match_requests_on => [:body, :headers])
          end

        else

          it "does not stub the recorded requests with the http stubbing adapter" do
            VCR::Config.cassette_library_dir = File.expand_path(File.dirname(__FILE__) + "/fixtures/#{YAML_SERIALIZATION_VERSION}/cassette_spec")
            VCR.http_stubbing_adapter.should_not_receive(:stub_requests)
            cassette = VCR::Cassette.new('example', :record => record_mode)
          end

          it "does not load the recorded interactions from the library yml file" do
            VCR::Config.cassette_library_dir = File.expand_path(File.dirname(__FILE__) + "/fixtures/#{YAML_SERIALIZATION_VERSION}/cassette_spec")
            cassette = VCR::Cassette.new('example', :record => record_mode)
            cassette.should have(0).recorded_interactions
          end

        end
      end
    end
  end

  describe '#eject' do
    temp_dir File.expand_path(File.dirname(__FILE__) + '/fixtures/cassette_spec_eject'), :assign_to_cassette_library_dir => true

    [true, false].each do |orig_http_connections_allowed|
      it "resets #{orig_http_connections_allowed} on the http stubbing adapter if it was originally #{orig_http_connections_allowed}" do
        VCR.http_stubbing_adapter.should_receive(:http_connections_allowed?).and_return(orig_http_connections_allowed)
        cassette = VCR::Cassette.new(:name)
        VCR.http_stubbing_adapter.should_receive(:http_connections_allowed=).with(orig_http_connections_allowed)
        cassette.eject
      end
    end

    it "writes the recorded interactions to disk as yaml" do
      recorded_interactions = [
        VCR::HTTPInteraction.new(:req_sig_1, :response_1),
        VCR::HTTPInteraction.new(:req_sig_2, :response_2),
        VCR::HTTPInteraction.new(:req_sig_3, :response_3)
      ]

      cassette = VCR::Cassette.new(:eject_test)
      cassette.stub!(:recorded_interactions).and_return(recorded_interactions)

      lambda { cassette.eject }.should change { File.exist?(cassette.file) }.from(false).to(true)
      saved_recorded_interactions = File.open(cassette.file, "r") { |f| YAML.load(f.read) }
      saved_recorded_interactions.should == recorded_interactions
    end

    it "writes the recorded interactions to a subdirectory if the cassette name includes a directory" do
      recorded_interactions = [VCR::HTTPInteraction.new(:the_request, :the_response)]
      cassette = VCR::Cassette.new('subdirectory/test_cassette')
      cassette.stub!(:recorded_interactions).and_return(recorded_interactions)

      lambda { cassette.eject }.should change { File.exist?(cassette.file) }.from(false).to(true)
      saved_recorded_interactions = File.open(cassette.file, "r") { |f| YAML.load(f.read) }
      saved_recorded_interactions.should == recorded_interactions
    end

    it "writes both old and new recorded interactions to disk" do
      file = File.expand_path(File.dirname(__FILE__) + "/fixtures/#{YAML_SERIALIZATION_VERSION}/cassette_spec/example.yml")
      FileUtils.cp file, File.join(@temp_dir, 'previously_recorded_interactions.yml')
      cassette = VCR::Cassette.new('previously_recorded_interactions')
      cassette.should have(3).recorded_interactions
      new_recorded_interaction = VCR::HTTPInteraction.new(:the_request, :the_response)
      cassette.record_http_interaction(new_recorded_interaction)
      cassette.eject
      saved_recorded_interactions = File.open(cassette.file, "r") { |f| YAML.load(f.read) }
      saved_recorded_interactions.should have(4).recorded_interactions
      saved_recorded_interactions.last.should == new_recorded_interaction
    end
  end

  describe '#eject for a cassette with previously recorded interactions' do
    it "restore the stubs checkpoint on the http stubbing adapter" do
      VCR::Config.cassette_library_dir = File.expand_path(File.dirname(__FILE__) + "/fixtures/#{YAML_SERIALIZATION_VERSION}/cassette_spec")
      cassette = VCR::Cassette.new('example', :record => :none)
      VCR.http_stubbing_adapter.should_receive(:restore_stubs_checkpoint).with('example')
      cassette.eject
    end

    it "does not re-write to disk the previously recorded interactions if there are no new ones" do
      VCR::Config.cassette_library_dir = File.expand_path(File.dirname(__FILE__) + "/fixtures/#{YAML_SERIALIZATION_VERSION}/cassette_spec")
      yaml_file = File.join(VCR::Config.cassette_library_dir, 'example.yml')
      cassette = VCR::Cassette.new('example', :record => :none)
      File.should_not_receive(:open).with(cassette.file, 'w')
      lambda { cassette.eject }.should_not change { File.mtime(yaml_file) }
    end
  end
end
