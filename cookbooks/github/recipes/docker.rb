#
# Cookbook Name:: github
# Recipe:: docker
#
# All rights reserved. DigitalOcean, Inc. 2021

# frozen_string_literal: true

tag('cicd-actions-runner')

begin
  include_recipe 'docker::default'
rescue Chef::Exceptions::RecipeNotFound
  docker_service 'default' do
    action %i(create start)
    registry_mirror 'https://dockerhub-mirror.internal.digitalocean.com'
  end
end

__END__

group "docker" do
  action :modify
  members "buildkite"
  append true
end

remote_file "/usr/local/bin/docker-compose" do
  source "https://s3-us-west-2.amazonaws.com/do-packages/14.04/docker-compose/#{node['buildkite']['docker_compose']['version']}/docker-compose-Linux-x86_64"
  owner "root"
  mode "0755"
end

cookbook_file "/usr/local/bin/docker-cleanup" do
  owner "root"
  mode "0755"
end

cron "docker_cleanup" do
  action :create
  time :daily
  user "buildkite"
  command "/usr/local/bin/docker-cleanup"
end

execute "Log in to digitalocean quay.io registry" do
  user "buildkite"
  group "docker"
  # The environment must be evaluated at converge time since the user does not
  # yet exist. Otherwise, will will get an ArgumentError
  environment(lazy do
    {
      'HOME' => ::Dir.home('buildkite'),
      'USER' => 'buildkite'
    }
  end)
  command "docker login -u '#{node['buildkite']['quayio']['user']}' -p '#{node['buildkite']['quayio']['pass']}' quay.io"
end
