include_recipe 'python'

virt_path = File.join(node[:gitpaste][:directory], 'virtenv')
repo_path = File.join(node[:gitpaste][:directory], 'repository')
python_path = File.join(virt_path, 'bin', 'python')
pip_path = File.join(virt_path, 'bin', 'pip')

[node[:gitpaste][:directory], virt_path, repo_path].each do |dir|
  directory dir do
    action :create
    recursive true
    owner 'nobody'
    group 'nogroup'
  end
end

# Setup virtual environment
python_virtualenv virt_path do
  action :create
  owner 'nobody'
  group 'nogroup'
end

# Check out the gitpaste repo
git repo_path do
  repository "git://github.com/justinvh/gitpaste.git"
  revision node[:gitpaste][:revision]
  action :sync
  user 'nobody'
  group 'nogroup'
  notifies :run, 'execute[requirements_install]', :immediately
end

execute 'requirements_install' do
  command "#{pip_path} install -r requirements.txt"
  cwd repo_path
  user 'nobody'
  group 'nogroup'
  action :nothing
  notifies :create, 'ruby_block[fix_admin_symlink]', :immediately
  notifies :run, 'execute[run_setup]', :immediately
end

ruby_block 'fix_admin_symlink' do
  block do
    target_file = File.join(repo_path, 'saic', 'paste', 'static', 'admin') 
    File.delete(target_file)
    File.symlink(
      File.join(virt_path, 'lib', 'python2.6', 'site-packages', 'django', 'contrib', 'admin'),
      target_file
    )
    FileUtils.chown('nobody', 'nogroup', target_file)
  end
  not_if do
    File.exists?(
      File.expand_path(
        File.readlink(
          File.join(repo_path, 'saic', 'paste', 'static', 'admin')
        )
      )
    )
  end
  action :nothing
end

execute 'run_setup' do
  command "#{python_path} manage.py syncdb --noinput"
  cwd File.join(repo_path, 'saic')
  user 'nobody'
  group 'nogroup'
  not_if do
    File.exists?(File.join(repo_path, 'saic', 'paste.db'))
  end
  notifies :run, 'execute[enable_admin]', :immediately
end

execute 'enable_admin' do
  command '/bin/true'
  cwd File.join(repo_path, 'saic')
  user 'nobody'
  group 'nogroup'
  not_if do
  end
end

# Ensure required attributes are set
node.set[:gunicorn][:virtualenv] = virt_path
unless(node[:gitpaste][:gunicorn][:pid])
  node.set[:gitpaste][:gunicorn][:pid] = File.join(
    node[:gitpaste][:directory], 'gitpaste.pid'
  )
end
unless(node[:gitpaste][:gunicorn][:listen])
  node.set[:gitpaste][:gunicorn][:listen] = "unix:" +
    File.join(
      node[:gitpaste][:directory], 'gitpaste.sock'
    )
end
unless(node[:gitpaste][:gunicorn][:exec])
  node.set[:gitpaste][:gunicorn][:exec] = File.join(
    virt_path, 'bin', 'gunicorn_django'
  )
end
node.set[:gitpaste][:red_unicorn] = 'red_unicorn' unless node[:gitpaste][:red_unicorn]

include_recipe "gunicorn"

gunicorn_config node[:gitpaste][:gunicorn][:config] do
  worker_processes node[:gitpaste][:gunicorn][:workers]
  backlog node[:gitpaste][:gunicorn][:backlog]
  listen node[:gitpaste][:gunicorn][:listen]
  pid node[:gitpaste][:pid]
  action :create
end

# Add gunicorn for running pastebin
python_pip 'gunicorn' do
  action :install
  virtualenv virt_path
end

case node[:gitpaste][:web_server].to_sym
when :nginx
  include_recipe 'gitpaste::nginx'
else
  raise 'Unsupported web server requested'
end

case node[:gitpaste][:init_type].to_sym
when :bluepill
  include_recipe 'gitpaste::bluepill'
else
  raise 'Unsupported init type requested'
end
