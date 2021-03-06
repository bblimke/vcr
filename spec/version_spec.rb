require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "VCR.version" do
  subject { VCR.version }

  it { should =~ /\A\d+\.\d+\.\d+\z/ }
  its(:parts) { should be_instance_of(Array)  }
  its(:major) { should be_instance_of(Fixnum) }
  its(:minor) { should be_instance_of(Fixnum) }
  its(:patch) { should be_instance_of(Fixnum) }
end
