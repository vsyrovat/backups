require 'rubygems'
require 'net/ssh'
require 'net/sftp'
require 'fileutils'


class Backup
  def self.require_task task
    @task = task
    require File.join(CONFS_PATH, task)
  end

  def self.task &block
    class_eval &block if block_given?
  end

  def self.ssh options={}, &block
    options[:port] ||= 22
    @ssh_host = options[:host]
    @ssh_user = options[:user]
    @ssh_password = options[:password]
    @time = Time.now.utc.to_s.gsub(' ', '_')
    @local_dir = File.join(DATA_PATH, @task, @time)
    FileUtils.mkdir_p(@local_dir)
    @task_data_dir = File.join(DATA_PATH, @task)
    begin
      puts "Connecting to #{options[:host]}"
      Net::SSH.start(options[:host], options[:user], {:password => options[:password], :port => options[:port]}) do |ssh|
        @ssh = ssh
        class_eval &block if block_given?
      end
      puts "Connection closed"
    rescue StandardError=>e
      puts "Error: #{e.message}"
    ensure
      unless @ssh.closed?
        @ssh.close
        puts "Connection closed"
      end
    end
  end

  def self.mysqldump options
    options[:host] ||= 'localhost'
    raise 'open ssh session first' unless @ssh
    raise ':dbname required' unless options[:dbname]
    raise ':user required' unless options[:user]
    raise ':password required' unless options[:password]
    puts "Backing up database #{options[:dbname]}"
    remote_sql_name = "#{options[:dbname]}_#{@time}.sql"
    remote_sql = "/tmp/#{remote_sql_name}"
    remote_tgz_name = "#{options[:dbname]}_#{@time}.sql.tar.gz"
    remote_tgz = "/tmp/#{remote_tgz_name}"
    local_tgz = File.join(@local_dir, "#{options[:dbname]}.sql.tar.gz")
    begin
      @ssh.exec!("mysqldump -u #{options[:user]} -p#{options[:password]} #{options[:dbname]} > #{remote_sql}")
      begin
        @ssh.exec!("tar --directory=/tmp -cvzf #{remote_tgz} #{remote_sql_name}")
        @ssh.sftp.download!(remote_tgz, local_tgz)
      ensure
        @ssh.exec!("rm #{remote_tgz}")
      end
    ensure
      @ssh.exec!("rm #{remote_sql}")
    end
    puts "Dump saved to #{local_tgz}"
  end

  def self.rsync remote_path
    local_files_dir = File.join(DATA_PATH, @task, 'current_files')
    begin
      puts "Start syncing #{remote_path} to #{local_files_dir}"
      FileUtils.mkdir_p local_files_dir
      #p %Q(rsync -e "sshpass -p '#{@ssh_password}' ssh" -avz "#{@ssh_user}@#{@ssh_host}:#{remote_path}" "#{local_files_dir}")
      puts %x(rsync -e "sshpass -p '#{@ssh_password}' ssh" -avz --delete "#{@ssh_user}@#{@ssh_host}:#{remote_path}" "#{local_files_dir}")
      tgz = File.join(DATA_PATH, @task, @time, 'files.tar.gz')
      puts "Compressing #{local_files_dir} to #{tgz}"
      %x(tar --directory="#{local_files_dir}" --force-local --use-compress-program=pigz -cvf "#{tgz}" ".")
    ensure
    end
  end
end