require File.expand_path('../helper', __FILE__)

describe FireAndForget::Server do
  before do
    FAF.reset!
  end

  after do
    FileUtils.rm(SOCKET) if File.exist?(SOCKET)
  end

  describe "task messages" do
    it "should generate events in clients on the right domain" do
      client1 = client2 = client3 = nil
      result1 = result2 = result3 = nil
      result4 = result5 = result6 = nil

      EM.run {
        FAF::Server.start(SOCKET)

        client1 = FAF::Client.new("domain1", SOCKET)
        client2 = FAF::Client.new("domain1", SOCKET)
        client3 = FAF::Client.new("domain2", SOCKET)

        command = FAF::Command::ClientEvent.new("domain1", "a", "data")

        client1.on_event(:a) { |data| result1 = [:a, data] }
        client2.on_event(:a) { |data| result2 = [:a, data] }
        client3.on_event(:a) { |data| result3 = [:a, data] }
        client1.on_event(:b) { |data| result4 = [:b, data] }
        client2.on_event(:b) { |data| result5 = [:b, data] }
        client3.on_event(:b) { |data| result6 = [:b, data] }

        $receive_count = 0

        $test = proc {
          result1.must_equal [:a, "data"]
          result2.must_equal [:a, "data"]
          result3.must_be_nil
          result4.must_be_nil
          result5.must_be_nil
          result6.must_be_nil
          EM.stop
        }

        def client1.notify!
          super
          $receive_count += 1
          if $receive_count == 3
            $test.call
          end
        end

        def client2.notify!
          super
          $receive_count += 1
          if $receive_count == 3
            $test.call
          end
        end

        def client3.notify!
          super
          $receive_count += 1
          if $receive_count == 3
            $test.call
          end
        end

        Thread.new {
          FAF::Server.run(command)
        }.join
      }
    end
  end

  describe "Task" do
    it "should make it intact from client to process" do
      FAF.domain = "example.org"
      FAF.connection = SOCKET

      default_params = { :param1 => "param1" }
      env = { "ENV_PARAM" => "envparam" }
      args = {:param2 => "param2"}
      niceness = 10
      task_uid = 9999
      task = FAF.add_task(:publish, "/path/to/binary", niceness, default_params, env)
      command = FAF::Command::Fire.new(task, args)
      dump = command.dump
      mock(command).dump { dump }
      mock(FAF::Command::Fire).new(task, args) { command }
      mock(FAF::Command).load(is_a(String)) { command }
      mock(command).valid? { true }
      mock(command).task_uid.twice { task_uid }

      EM.run do
        FAF::Server.start(SOCKET)

        mock(Process).detach(9999)

        mock(command).fork do |block|
          mock(command).daemonize(%[/path/to/binary --param1="param1" --param2="param2"], is_a(String))
          mock(Process).setpriority(Process::PRIO_PROCESS, 0, niceness)
          mock(Process::UID).change_privilege(task_uid)
          mock(File).umask(0022)
          mock(command).exec(%[/path/to/binary --param1="param1" --param2="param2"])
          block.call

          ENV["ENV_PARAM"].must_equal "envparam"
          ENV[FAF::ENV_DOMAIN].must_equal "example.org"
          ENV[FAF::ENV_TASK_NAME].must_equal "publish"
          ENV[FAF::ENV_CONNECTION].must_equal SOCKET
          EM.stop
          9999
        end

        Thread.new do
          FAF.fire(:publish, args)
        end.join
      end
    end

    it "should report back to the server to set the task PID" do
      pids = {}
      pid = 99999
      FAF.domain = "example.com"
      FAF.connection = SOCKET


      EM.run do
        FAF::Server.start(SOCKET)

        ENV[FAF::ENV_DOMAIN] = "example.com"
        ENV[FAF::ENV_TASK_NAME] = "publish"
        ENV[FAF::ENV_CONNECTION] = SOCKET

        mock(FAF::Task).pid { pid }
        mock(FireAndForget::Server).pids { pids }
        mock(pids).[]=("example.com/publish", pid) { EM.stop }

        Thread.new do
          class FAFTask
            include FAF::Task
          end
        end.join
      end
    end

    it "should be able to trigger messages on the client" do
      FAF.domain = "example2.com"
      FAF.connection = SOCKET


      EM.run do
        FAF::Server.start(SOCKET)

        ENV[FAF::ENV_DOMAIN] = "example2.com"
        ENV[FAF::ENV_TASK_NAME] = "publish"
        ENV[FAF::ENV_CONNECTION] = SOCKET

        c = FAF::TaskClient.new("example2.com", SOCKET)
        mock(FAF::TaskClient).new { c }
        mock(c).run(is_a(FAF::Command::SetPid))
        proxy(c).run(is_a(FAF::Command::ClientEvent))
        client = FAF::Client.new("example2.com", SOCKET)

        client.on_event(:publish_status) { |data|
          data.must_equal "completed"
          EM.stop
        }

        Thread.new do
          class FAFTask
            include FAF::Task
            def run
              faf_event("publish_status", "completed")
            end
          end
          FAFTask.new.run
        end.join

      end
    end

    it "should be able to kill task processes" do
      pid = 99999
      pids = {"example3.com/publish" => pid}
      FAF.domain = "example3.com"
      FAF.connection = SOCKET


      EM.run do
        FAF::Server.start(SOCKET)

        ENV[FAF::ENV_DOMAIN] = "example3.com"
        ENV[FAF::ENV_TASK_NAME] = "publish"
        ENV[FAF::ENV_CONNECTION] = SOCKET

        c = FAF::TaskClient.new("example3.com", SOCKET)
        mock(FAF::TaskClient).new { c }
        mock(c).run(is_a(FAF::Command::SetPid))
        proxy(c).run(is_a(FAF::Command::Kill))

        mock(FAF::Task).pid { pid }
        mock(FireAndForget::Server).pids { pids }

        Thread.new do
          class FAFTask
            include FAF::Task
          end
        end.join

        Thread.new do
          mock(Process).kill("TERM", pid) { EM.stop }
          FAF.kill(:publish)
        end.join
      end
    end

    it "should divert STDOUT and STDERR to file and inform the server when finished" do
      FAF.domain = "example4.com"
      FAF.connection = SOCKET

      EM.run do
        FAF::Server.start(SOCKET)
        # mock(FAF::Server).task_complete("example4.com/example") { EM.stop }
        task = FAF.add_task(:example, File.expand_path("../tasks/example.rb", __FILE__))
        # command = FAF::Command::Fire.new(task)
        # stub(Process::UID).change_privilege(anything)
          proxy(FAF::Server).run(is_a(FAF::Command::Fire))
          mock(FAF::Server).run(is_a(FAF::Command::SetPid)) { puts "PID" }
          mock(FAF::Server).run(is_a(FAF::Command::ClientEvent)) { puts "EVENT" }
          mock(FAF::Server).run(is_a(FAF::Command::TaskComplete)) { EM.stop }
          # FAF.client.on_event(:"example") { |data|
          #   puts "\\\\\\\\n\\\\\\\\nEVENT #{data}"
          # }
          # p command.valid?
          #
          # Thread.new do
          puts ">"*50
          puts ">"*50
        # end.join
        EM.schedule do
        FAF.fire(:example, {"param" => "value"})
        end
      end
    end
  end
end
