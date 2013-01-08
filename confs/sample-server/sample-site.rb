# Replace 'server/site' with your server's and site's names
Backup.task 'server/site' do
  # Describe ssh-connection
  ssh :host=>'123.456.789.0', :user=>'user', :password=>'password' do
    # Describe mysql-connection on remote host
    mysqldump :dbname=>'dbname', :user => 'user', :password => 'password'
    # Specify path on remote host for sync into local folder
    rsync '~/path/to/project/'
  end
  # Remove obsolete backups, older than arg seconds
  # 86400 = one day
  # 7*86400 = one week
  remove_obsolete 7*86400
end