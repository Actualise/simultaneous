require File.expand_path('../helper', __FILE__)

describe Simultaneous::Command do
  before do
    Simultaneous.domain = "example.net"
    @task = Simultaneous::TaskDescription.new(:publish, "/publish", 9, {:param1 => "value1", :param2 => "value2"})
  end
  it "should serialize and deserialize correctly" do
    task = Simultaneous::TaskDescription.new(:publish, "/publish", 9, {:param1 => "value1", :param2 => "value2"})
    cmd = Simultaneous::Command::CommandBase.new(task, {"param2" => "newvalue2", :param3 => "value3"})
    cmd2 = Simultaneous::Command.load(cmd.dump)
    task2 = cmd2.task
    task2.binary.must_equal task.binary
    task2.params.must_equal task.params
    task2.name.must_equal task.name
    cmd.params.must_equal({"param1" => "value1", "param2" => "newvalue2", "param3" => "value3"})
  end

  it "should only run scripts belonging to the same user as the ruby process" do
    stub(File).exist?("/publish") { true }
    stub(File).exists?("/publish") { true }
    stat = Object.new
    stub(stat).uid { Process.uid + 1 }
    stub(File).stat("/publish") { stat }
    cmd = Simultaneous::Command::Fire.new(@task)
    lambda { cmd.run }.must_raise(Simultaneous::PermissionsError)
  end

  it "should not raise an error if the binary belongs to this process" do
    stat = Object.new
    stub(stat).uid { Process.uid }
    stub(File).stat("/publish") { stat }
    cmd = Simultaneous::Command::Fire.new(@task)
    cmd.permitted?
  end

  it "should raise an error if the binary belongs to this process" do
    stat = Object.new
    uid = Process.uid
    stub(stat).uid { uid }
    stub(File).stat("/publish") { stat }
    stub(Process).euid { uid + 1 }
    cmd = Simultaneous::Command::Fire.new(@task)
    lambda { cmd.permitted? }.must_raise(Simultaneous::PermissionsError)
  end

  it "should give error if binary doesn't exist" do
    stub(File).exist?("/publish") { false }
    stub(File).exists?("/publish") { false }
    stub(File).owned?("/publish") { true }
    cmd = Simultaneous::Command::Fire.new(@task)
    lambda { cmd.run }.must_raise(Simultaneous::FileNotFoundError)
  end

  it "should raise error if command isn't one of the approved list" do
    cmd = Object.new
    mock(cmd).run.times(0)
    lambda { Simultaneous::Server.run(cmd) }.must_raise(Simultaneous::PermissionsError)
  end

  it "should work with binaries involving a command" do
    task = Simultaneous::TaskDescription.new(:publish, "/publish all")
    stat = Object.new
    stub(stat).uid { Process.uid }
    stub(File).stat("/publish") { stat }
    stub(File).exist?("/publish") { true }
    stub(File).exists?("/publish") { true }
    cmd = Simultaneous::Command::Fire.new(task)
    cmd.valid?
  end

end
