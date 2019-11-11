require 'open-uri'
require 'digest'
require File.expand_path(File.dirname(__FILE__) + '/util')

GWT_SNAPSHOT_URL = 'https://oss.sonatype.org/content/repositories/google-snapshots'

GWT_PREV_VERSION = '2.8.2'
GWT_TARGET_VERSION = '2.8.2-v20191108'
# Note: gwt is just a pom dependency
GWT_ARTIFACTS = [
    %w(com.google.jsinterop jsinterop-annotations 20191109.055159-844),
    %w(com.google.jsinterop jsinterop 20191109.055156-844),
    %w(com.google.gwt gwt-codeserver 20191108.055205-844),
    %w(com.google.gwt gwt-elemental 20191108.055211-844),
    %w(com.google.gwt gwt-servlet 20191108.055158-844),
    %w(com.google.gwt gwt-dev 20191108.055139-844),
    %w(com.google.gwt gwt-user 20191108.055147-844),
    %w(com.google.gwt gwt 20191108.055134-844),
    %w(com.google.web.bindery requestfactory 20191108.055218-844),
    %w(com.google.web.bindery requestfactory-apt 20191108.055234-844),
    %w(com.google.web.bindery requestfactory-client 20191108.055221-844),
    %w(com.google.web.bindery requestfactory-server 20191108.055228-844)
]

def gwt_download_file(file_path, output_filepath)
  source_url = "#{GWT_SNAPSHOT_URL}/#{file_path}"
  target_file = dist_dir(output_filepath)
  unless File.exist?(target_file)
    FileUtils.mkdir_p File.dirname(target_file)
    puts "Downloading #{source_url} to #{target_file}"
    IO.copy_stream(open(source_url), target_file)
  end
end

def gwt_calc_target_path(group_id, artifact_id, version, suffix)
  "org/realityforge/#{group_id.gsub('.', '/')}/#{artifact_id}/#{version}/#{artifact_id}-#{version}#{suffix}"
end

def gwt_download_file_set(group_id, artifact_id, version, suffix)
  file_path = "#{group_id.gsub('.', '/')}/#{artifact_id}/HEAD-SNAPSHOT/#{artifact_id}-HEAD-#{version}#{suffix}"
  target_path = gwt_calc_target_path(group_id, artifact_id, GWT_TARGET_VERSION, suffix)
  gwt_download_file(file_path, target_path)
  gwt_download_file("#{file_path}.md5", "#{target_path}.md5")
  gwt_download_file("#{file_path}.sha1", "#{target_path}.sha1")
end

task 'gwt:download' do
  GWT_ARTIFACTS.each do |data|
    group_id, artifact_id, version = data
    gwt_download_file_set(group_id, artifact_id, version, '.pom')
    unless is_pom_artifact?(artifact_id)
      gwt_download_file_set(group_id, artifact_id, version, '.jar')
      gwt_download_file_set(group_id, artifact_id, version, '-sources.jar')
      gwt_download_file_set(group_id, artifact_id, version, '-javadoc.jar')
    end
  end
end

task 'gwt:patch_poms' do
  GWT_ARTIFACTS.each do |data|
    group_id, artifact_id, version = data
    pom_file = dist_dir(gwt_calc_target_path(group_id, artifact_id, GWT_TARGET_VERSION, '.pom'))
    contents = IO.read(pom_file).
        # First replace com.google.jsinterop pom version
        gsub('                <version>HEAD-SNAPSHOT</version>', "                <version>#{GWT_TARGET_VERSION}</version>").
        # Then replace the version to reference the parent pom
        gsub('        <version>HEAD-SNAPSHOT</version>', "        <version>#{GWT_TARGET_VERSION}</version>").
        # Then replace the version of actual pom
        gsub('    <version>HEAD-SNAPSHOT</version>', "    <version>#{GWT_TARGET_VERSION}</version>").
        # Then update the groupIds
        gsub('<groupId>com.google.gwt</groupId>', '<groupId>org.realityforge.com.google.gwt</groupId>').
        gsub('<groupId>com.google.jsinterop</groupId>', '<groupId>org.realityforge.com.google.jsinterop</groupId>').
        gsub('<groupId>com.google.web.bindery</groupId>', '<groupId>org.realityforge.com.google.web.bindery</groupId>')

    IO.write(pom_file, contents)

    IO.write("#{pom_file}.md5", Digest::MD5.hexdigest(contents))
    IO.write("#{pom_file}.sha1", Digest::SHA1.hexdigest(contents))
  end
end

def gwt_sign(group_id, artifact_id, suffix)
  source_filename = dist_dir(gwt_calc_target_path(group_id, artifact_id, GWT_TARGET_VERSION, suffix))
  sign_task(source_filename) unless File.exist?("#{source_filename}.asc")
end

def is_pom_artifact?(artifact_id)
  'gwt' == artifact_id || 'requestfactory' == artifact_id || 'jsinterop' == artifact_id
end

task 'gwt:sign' do
  # Needs to run after poms have been patched
  GWT_ARTIFACTS.each do |data|
    group_id, artifact_id, version = data
    gwt_sign(group_id, artifact_id, '.pom')
    unless is_pom_artifact?(artifact_id)
      gwt_sign(group_id, artifact_id, '.jar')
      gwt_sign(group_id, artifact_id, '-sources.jar')
      gwt_sign(group_id, artifact_id, '-javadoc.jar')
    end
  end
end

def gwt_artifact_def(group_id, artifact_id, type, classifier = nil)
  Buildr.artifact({:group => "org.realityforge.#{group_id}",
                   :id => artifact_id,
                   :version => GWT_TARGET_VERSION,
                   :type => type,
                   :classifier => classifier}).
      from(dist_dir(gwt_calc_target_path(group_id, artifact_id, GWT_TARGET_VERSION, "#{classifier.nil? ? '' : "-#{classifier}"}.#{type}")))
end


def gwt_tasks_for_modules
  tasks = []
  GWT_ARTIFACTS.each do |data|
    group_id, artifact_id, version = data

    tasks << gwt_artifact_def(group_id, artifact_id, 'pom')
    tasks << gwt_artifact_def(group_id, artifact_id, 'pom.asc')
    unless is_pom_artifact?(artifact_id)
      tasks << gwt_artifact_def(group_id, artifact_id, 'jar')
      tasks << gwt_artifact_def(group_id, artifact_id, 'jar.asc')
      tasks << gwt_artifact_def(group_id, artifact_id, 'jar', 'sources')
      tasks << gwt_artifact_def(group_id, artifact_id, 'jar.asc', 'sources')
      tasks << gwt_artifact_def(group_id, artifact_id, 'jar', 'javadoc')
      tasks << gwt_artifact_def(group_id, artifact_id, 'jar.asc', 'javadoc')
    end
  end
  tasks
end

task 'gwt:install' do
  gwt_tasks_for_modules.each do |task|
    in_local_repository = Buildr.repositories.locate(task)
    rm_f in_local_repository
    mkdir_p File.dirname(in_local_repository)
    cp task.instance_variable_get('@from'), in_local_repository, :preserve => false
    info "Installed #{task.name} to #{in_local_repository}"
  end
end

task 'gwt:stage' do
  repositories.release_to = {
      :url => 'https://stocksoftware.jfrog.io/stocksoftware/staging',
      :username => ENV['STAGING_USERNAME'],
      :password => ENV['STAGING_PASSWORD'] }
  gwt_tasks_for_modules.select {|t| t.type != :pom}.each(&:upload)
  repositories.release_to = nil
end

RepackrMavenCentralReleaseTool.define_publish_tasks('gwt',
                                                    :profile_name => 'org.realityforge',
                                                    :username => 'realityforge') do
  task('gwt:install').invoke
  gwt_tasks_for_modules.select {|t| t.type != :pom}.each(&:upload)
end

task 'gwt:generate_email' do

  email = <<-EMAIL
To: google-web-toolkit@googlegroups.com
Subject: [ANN] (Unofficial) GWT #{GWT_TARGET_VERSION} release

GWT is a development toolkit for building and optimizing complex
browser-based applications. Its goal is to enable productive
development of high-performance web applications without the
developer having to be an expert in browser quirks,
XMLHttpRequest, and JavaScript. It’s open-source, completely
free, and used by thousands of developers around the world.

https://github.com/gwtproject/gwt

This is an unofficial release to Maven Central with the groupId
prefixed with "org.realityforge.". The intent is to get the current
version of GWT into more people's hands earlier. Please don't bug
the GWT project. Versions are released on demand.

The one significant difference in the way that it has been packaged
is to release the jsinterop-annotations artifact with the coordinate

org.realityforge.com.google.jsinterop:jsinterop-annotations:jar:#{GWT_TARGET_VERSION}

For most Maven users, it should be sufficient to update your
dependency declarations to something like:

    <dependency>
      <groupId>org.realityforge.com.google.gwt</groupId>
      <artifactId>gwt-user</artifactId>
      <version>#{GWT_TARGET_VERSION}</version>
    </dependency>
    <dependency>
      <groupId>org.realityforge.com.google.gwt</groupId>
      <artifactId>gwt-dev</artifactId>
      <version>#{GWT_TARGET_VERSION}</version>
    </dependency>

Hope this helps,

Peter Donald
  EMAIL

  File.open 'emails/gwt-email.txt', 'w' do |file|
    file.write email
  end
  puts 'Announce email template in emails/gwt-email.txt'
  puts email
end

desc 'Download the latest gwt project and push a local release'
task 'gwt:local_release' => %w(gwt:download gwt:patch_poms gwt:sign gwt:install)

desc 'Download the latest gwt project and push a staging release'
task 'gwt:stage_release' => %w(gwt:download gwt:patch_poms gwt:sign gwt:stage)

desc 'Download the latest gwt project and push a release'
task 'gwt:release' => %w(gwt:download gwt:patch_poms gwt:sign gwt:publish gwt:generate_email)
