#
# Cookbook Name:: github
# Recipe:: actions_runner
#
# All rights reserved. DigitalOcean, Inc. 2021

# frozen_string_literal: true

tag('cicd-actions-runner')

__END__

## EVERYTHING BELOW THIS LINE WAS COPIED AND PASTED -- NEEDS REVIEW
## {{

vault_auth(node['concourse']['vault']['role_id'], node['concourse']['vault']['secret_id'])

secrets = vault_bag_item(node['concourse']['vault']['path'])
raise Chef::Error, "Could not find secrets for #{node.chef_environment}!" unless secrets

private_slack_url = secrets.data[:slack_hooks][:cicdprivate]
worker_creds = secrets.data[:keys]

directory '/opt/concourse/keys' do
  mode '0700'
  owner 'root'
  group 'root'
  recursive true
end

file node['concourse']['config']['worker']['TSA_WORKER_PRIVATE_KEY'] do
  content worker_creds[:worker_key]
  mode '0600'
  owner 'root'
  group 'root'
end

file node['concourse']['config']['worker']['TSA_PUBLIC_KEY'] do
  content worker_creds[:host_key_pub]
  mode '0600'
  owner 'root'
  group 'root'
end

tsa_hosts = search(:node, "role:cicd-concourse-web AND chef_environment:#{node.chef_environment}").map { |s| s['fqdn'] }
if tsa_hosts
  # multiple TSA_HOSTS need to be in CSV format for TSA_HOST env var
  tmp_hosts = []
  tsa_hosts.each do |tsa_host|
    tmp_hosts << "#{tsa_host}:2222"
  end
  node.override['concourse']['config']['worker']['TSA_HOST'] = tmp_hosts.sort.join(',')
end

if node['fqdn'].include? '.s2r1'
  unless node['concourse']['config']['worker']['TAG'].empty?
    node.override['concourse']['config']['worker']['TAG'] = node['concourse']['config']['worker']['TAG'] + ','
  end
  node.override['concourse']['config']['worker']['TAG'] = node['concourse']['config']['worker']['TAG'] + 'stage2'
end

concourse_worker 'worker' do
  checksum  node['concourse']['release']['checksum']
  config    node['concourse']['config']['worker']
  filename  node['concourse']['release']['filename']
  url       node['concourse']['release']['url']
  version   node['concourse']['release']['version']
  action :install
end

service 'apport' do
  action %i[stop disable]
end

template '/opt/concourse/bin/concourse_worker_watchdog.sh' do
  source 'watchdog/concourse_worker_watchdog.sh.erb'
  owner  'root'
  group  'root'
  mode   '0700'
  variables(
    slack_url: private_slack_url,
    slack_channel: '#concourse-alerts',
    slack_username: 'Concourse Worker Watchdog'
  )
end

template '/opt/concourse/bin/land_worker.sh' do
  source 'scripts/land_worker.sh'
  owner 'root'
  group 'root'
  mode '0755'
  variables(
    tsa_hosts:               tsa_hosts,
    tsa_public_key_path:     node['concourse']['config']['worker']['TSA_PUBLIC_KEY'],
    worker_private_key_path: node['concourse']['config']['worker']['TSA_WORKER_PRIVATE_KEY']
  )
end

template '/opt/concourse/bin/retire_worker.sh' do
  source 'scripts/retire_worker.sh'
  owner 'root'
  group 'root'
  mode '0755'
  variables(
    tsa_hosts:               tsa_hosts,
    tsa_public_key_path:     node['concourse']['config']['worker']['TSA_PUBLIC_KEY'],
    worker_private_key_path: node['concourse']['config']['worker']['TSA_WORKER_PRIVATE_KEY']
  )
end

template '/opt/concourse/bin/reset_worker.sh' do
  source 'scripts/reset_worker.sh'
  owner 'root'
  group 'root'
  mode '0755'
end

# Ensure KVM module is working to allow nested virtualization in pipelines
kernel_module 'kvm_intel' do
  parameters('nested' => 'Y')
end

# Collect BTRFS stats
cookbook_file '/opt/concourse/bin/btrfs_stats.py' do
  source   'btrfs_stats.py'
  owner    'root'
  group    'root'
  mode     '0700'
end

cron 'btrfs_stats' do
  minute  '*/1'
  command '/opt/concourse/bin/btrfs_stats.sh'
end

cookbook_file '/opt/concourse/bin/btrfs_stats.sh' do
  source   'btrfs_stats.sh'
  owner    'root'
  group    'root'
  mode     '0700'
end
## }}
