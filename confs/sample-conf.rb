Backup.task do
  ssh :host=>'123.456.789.0', :user=>'user', :password=>'password' do
    mysqldump :dbname=>'dbname', :user => 'user', :password => 'password'
    rsync '~/path/to/project/'
  end
end