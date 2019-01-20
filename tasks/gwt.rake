require File.expand_path(File.dirname(__FILE__) + '/util')

def deploy_gwt(repository_url, repo_id)
  in_dir(product_path('gwt', 'gwt')) do
    sh 'git reset --hard'
    Dir['maven/poms/**/*.xml'].each do |filename|
      content = IO.read(filename)
      content = content.
        gsub('<groupId>com.google.gwt</groupId>', '<groupId>org.realityforge.com.google.gwt</groupId>').
        gsub('<groupId>com.google.jsinterop</groupId>', '<groupId>org.realityforge.com.google.jsinterop</groupId>').
        gsub('<groupId>com.google.web.bindery</groupId>', '<groupId>org.realityforge.com.google.web.bindery</groupId>')
      IO.write(filename, content)
    end
    IO.write('maven/push-gwt.sh', IO.read('maven/push-gwt.sh').gsub(/^read/, '#read'))
    version_suffix = get_version_suffix('gwt')
    sh "GWT_MAVEN_REPO_ID=#{repo_id} GWT_VERSION=2.8.2-#{version_suffix} GWT_MAVEN_REPO_URL=#{repository_url} JSINTEROP_VERSION=1.0.2-#{version_suffix} GWT_GPG_PASS=#{ENV['GPG_PASS']} GWT_DIST_FILE= ./maven/push-gwt.sh"
  end
end

task 'gwt:download' do
  git_clone('gwt', 'tools', 'https://github.com/gwtproject/tools.git')
  git_clone('gwt', 'gwt', 'https://github.com/gwtproject/gwt.git')
  commit_hash = nil
  in_dir(product_path('gwt', 'gwt')) do
    commit_hash = `git describe --tags --always`.strip
  end
  record_commit_hash('gwt', commit_hash)
end

task 'gwt:build' do
  in_dir(product_path('gwt', 'gwt')) do
    sh 'ant clean elemental dist'
  end
end

task 'gwt:local_deploy' do
  deploy_gwt("file://#{product_path('gwt', 'repository')}", 'local')
end

task 'gwt:staging_deploy' do
  deploy_gwt('https://oss.sonatype.org/service/local/staging/deploy/maven2', 'sonatype-nexus-staging')
  puts "\n\n\n\n\nPlease manually close and release staged repositories at https://oss.sonatype.org/index.html#stagingRepositories"
end

desc 'Download the latest gwt project and push a local release'
task 'gwt:local_release' => %w(gwt:download gwt:build gwt:local_deploy)

desc 'Download the latest gwt project and push a release'
task 'gwt:release' => %w(gwt:download gwt:build gwt:staging_deploy)
