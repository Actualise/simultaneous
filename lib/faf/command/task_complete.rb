# encoding: UTF-8

module FireAndForget
  module Command
    class TaskComplete < CommandBase
      def initialize(task_name)
        @task_name = task_name
      end

      def run
        FireAndForget::Server.task_complete(namespaced_task_name)
      end
    end
  end
end