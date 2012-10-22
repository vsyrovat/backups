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
    @task_dir = File.join(DATA_PATH, @task)
    @snapshot_dir = File.join(DATA_PATH, @task, @time)
    FileUtils.mkdir_p(@snapshot_dir)
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
    # remote files
    remote_sql_basename = "#{options[:dbname]}_#{@time}.sql"
    remote_sql = "/tmp/#{remote_sql_basename}"
    remote_tgz_basename = "#{options[:dbname]}_#{@time}.sql.gz"
    remote_tgz = "/tmp/#{remote_tgz_basename}"
    # local files
    task_sql_basename = "#{options[:dbname]}.sql"
    task_sql = File.join(@task_dir, task_sql_basename)
    task_gz_basename = "#{options[:dbname]}.sql.gz"
    task_gz = File.join(@task_dir, task_gz_basename)
    snapshot_gz = File.join(@snapshot_dir, task_gz_basename)
    begin
      puts "Create remote dump of #{options[:dbname]}..."
      @ssh.exec!("mysqldump -u #{options[:user]} -p#{options[:password]} #{options[:dbname]} > #{remote_sql}")
      begin
        #puts "Compress dump on remote..."
        ##@ssh.exec!("tar --directory=/tmp -cvzf #{remote_tgz} #{remote_sql_basename}")
        #puts "gzip --rsyncable --fast #{remote_sql}"
        #@ssh.exec!("gzip --rsyncable --fast #{remote_sql}")
        puts "Download dump..."
        puts %x(rsync -e "sshpass -p '#{@ssh_password}' ssh" -avz "#{@ssh_user}@#{@ssh_host}:#{remote_sql}" "#{task_sql}")
        puts "Compress dump on local..."
        %x(pigz -k #{task_sql})
        FileUtils.mv(task_gz, snapshot_gz)
        #@ssh.sftp.download!(remote_tgz, local_tgz)
        puts "Dump saved to #{task_gz_basename}"
      ensure
        #@ssh.exec!("rm #{remote_tgz}")
      end
    ensure
      @ssh.exec!("rm #{remote_sql}")
    end
  end

  def self.rsync remote_path
    local_files_dir = File.join(DATA_PATH, @task, 'current_files')
    begin
      puts "Start syncing #{remote_path} to #{local_files_dir}"
      FileUtils.mkdir_p local_files_dir
      puts %x(rsync -e "sshpass -p '#{@ssh_password}' ssh" -az --delete "#{@ssh_user}@#{@ssh_host}:#{remote_path}" "#{local_files_dir}")
      tgz = File.join(DATA_PATH, @task, @time, 'files.tar.gz')
      puts "Compressing #{local_files_dir} to #{tgz}"
      %x(tar --directory="#{local_files_dir}" --force-local --use-compress-program=pigz -cvf "#{tgz}" ".")
    ensure
    end
  end
end