require File.expand_path(File.dirname(__FILE__) + '/util')

BASE_GROUP_ID = 'org.realityforge.com.google.jsinterop'
BASE_BRANCH = 'upstream'
BASE_BRANCHES_TO_MERGE = %w(TravisCiIntegration AddGitIgnore FixPOM)
BASE_UPDATE_UPSTREAM = true
# TODO: This should be automated somehow
BASE_PREV_VERSION = '1.0.0-RC1'

def base_version
  "1.0.0-#{get_version_suffix('jsinterop-base')}"
end

def base_integration_branch
  "integration-b#{load_build_number('jsinterop-base')}"
end

def base_output_artifact(type = :jar, classifier = nil)
  version = base_version
  artifact_id = 'base'
  filename = "#{artifact_id}-#{version}#{classifier.nil? ? '' : "-#{classifier}"}.#{type}"
  "#{dist_dir('jsinterop-base')}/#{BASE_GROUP_ID.gsub('.', '/')}/#{artifact_id}/#{version}/#{filename}"
end

task 'base:download' do
  git_clone('jsinterop', 'jsinterop-base', 'https://github.com/realityforge/jsinterop-base.git')
  if BASE_UPDATE_UPSTREAM
    in_dir(product_path('jsinterop', 'jsinterop-base')) do
      `git remote rm upstream`
      sh 'git remote add upstream https://github.com/google/jsinterop-base.git'
      sh 'git fetch upstream --prune'
      sh 'git checkout upstream'
      sh 'git reset --hard upstream/master'
      sh 'git push -f'
    end
  end
  # Remove all non master local branches
  in_dir(product_path('jsinterop', 'jsinterop-base')) do
    sh 'git checkout master'
    sh 'git reset --hard origin/master'
    `git branch`.split("\n").reject {|line| line =~ / master$/}.each do |line|
      sh "git branch -D #{line}"
    end
  end

  # Checkout base branch/commit/etc
  commit_hash = nil
  in_dir(product_path('jsinterop', 'jsinterop-base')) do
    sh "git checkout #{BASE_BRANCH}"
    commit_hash = `git describe --tags --always`.strip
  end

  record_branch('jsinterop-base', BASE_BRANCH)
  if record_commit_hash('jsinterop-base', commit_hash)
    load_and_increment_build_number('jsinterop-base')
  end

  in_dir(product_path('jsinterop', 'jsinterop-base')) do
    `git branch -D #{base_integration_branch} 2>&1`
    `git push origin :#{base_integration_branch} 2>&1`
    sh "git checkout -b#{base_integration_branch}"
    BASE_BRANCHES_TO_MERGE.each do |branch|
      sh "git merge --no-edit origin/#{branch}"
    end
  end
end

task 'base:build' do
  output_dir = dist_dir('jsinterop-base')
  rm_rf output_dir
  product_path = product_path('jsinterop', 'jsinterop-base')
  in_dir(product_path) do
    unless ENV['BAZEL'] == 'no'
      sh 'bazel clean --expunge'
      sh 'bazel build //java/jsinterop/base:libbase.jar //java/jsinterop/base:libbase-src.jar'
    end
    version = base_version

    unpack_dir = "#{WORKSPACE_DIR}/target/jsinterop-base"
    rm_rf unpack_dir

    src_dir = "#{unpack_dir}/src"
    mkdir_p src_dir
    in_dir(src_dir) do
      sh "jar -xf #{product_path}/bazel-bin/java/jsinterop/base/libbase-src.jar"
    end

    javadoc_dir = "#{unpack_dir}/doc"
    mkdir_p javadoc_dir
    sh "find #{src_dir} -type f -name \"*.java\" | xargs javadoc -d #{javadoc_dir}"

    javadocs_artifact = base_output_artifact(:jar, :javadoc)
    mkdir_p File.dirname(javadocs_artifact)
    sh "jar -cf #{javadocs_artifact} -C #{javadoc_dir}/ ."

    source_artifact = base_output_artifact(:jar, :sources)
    cp_r 'bazel-bin/java/jsinterop/base/libbase-src.jar', source_artifact

    jar_artifact = base_output_artifact(:jar)
    cp_r 'bazel-bin/java/jsinterop/base/libbase.jar', jar_artifact

    pom =
      IO.read('maven/pom-base.xml').
        gsub('__GROUP_ID__', BASE_GROUP_ID).
        gsub('__VERSION__', version).
        gsub('__ARTIFICAT_ID__', 'base')

    pom_artifact = base_output_artifact(:pom)
    IO.write(pom_artifact, pom)

    sign_task(pom_artifact)
    sign_task(jar_artifact)
    sign_task(javadocs_artifact)
    sign_task(source_artifact)
  end
end

def base_artifact_def(type, classifier = nil)
  Buildr.artifact({ :group => BASE_GROUP_ID, :id => 'base', :version => base_version, :type => type, :classifier => classifier }).
    from(base_output_artifact(type, classifier))
end

def base_tasks_for_modules
  tasks = []
  tasks << base_artifact_def(:pom)
  tasks << base_artifact_def('pom.asc')
  tasks << base_artifact_def(:jar)
  tasks << base_artifact_def('jar.asc')
  tasks << base_artifact_def(:jar, :sources)
  tasks << base_artifact_def('jar.asc', :sources)
  tasks << base_artifact_def(:jar, :javadoc)
  tasks << base_artifact_def('jar.asc', :javadoc)
  tasks
end

task 'base:install' do
  base_tasks_for_modules.each do |task|
    in_local_repository = Buildr.repositories.locate(task)
    rm_f in_local_repository
    mkdir_p File.dirname(in_local_repository)
    cp task.instance_variable_get('@from'), in_local_repository, :preserve => false
    info "Installed #{task.name} to #{in_local_repository}"
  end
end

RepackrMavenCentralReleaseTool.define_publish_tasks('base',
                                                    :profile_name => 'org.realityforge',
                                                    :username => 'realityforge') do
  task('base:install').invoke
  base_tasks_for_modules.select {|t| t.type != :pom}.each(&:upload)
end

task 'base:save_build' do
  sh 'git reset'
  sh 'git add versions.json'
  sh "git commit --allow-empty -m \"Release the #{base_version} version of the jsinterop-base project\""
  sh "git tag jsinterop-base-#{base_version}"
  sh "git push origin jsinterop-base-#{base_version}"
  sh 'git push'

  # Save integration branch
  in_dir(product_path('jsinterop', 'jsinterop-base')) do
    sh "git push origin #{base_integration_branch}"
  end
end

task 'base:generate_email' do

  email = <<-EMAIL
To: google-web-toolkit@googlegroups.com
Subject: [ANN] (Unofficial) JsInterop-Base #{base_version} release

The jsInterop-base library contains a set of utilities to implement functionality that
cannot be expressed with Jsinterop alone.

https://github.com/google/jsinterop-base

This is an unofficial release to Maven Central under a different groupId.
Please don't bug the original authors. Versions are released on demand.
  EMAIL
  puts 'Retrieving changes for jsinterop-base'

  revapi_diff = Buildr.artifact(:revapi_diff)

  old_api = Buildr.artifact("com.google.jsinterop:base:jar:#{BASE_PREV_VERSION}")
  new_api = Buildr.artifact("#{BASE_GROUP_ID}:base:jar:#{base_version}")

  revapi_diff.invoke
  old_api.invoke
  new_api.invoke

  mkdir_p 'emails'
  output_file = "emails/jsinterop-base-#{BASE_PREV_VERSION}-to-#{elemental2_version}-diff.json"

  sh ['java', '-jar', revapi_diff.to_s, '--old-api', old_api.to_s, '--new-api', new_api.to_s, '--output-file', output_file].join(' ')

  json = JSON.parse(IO.read(output_file))
  non_breaking_changes = json.select {|j| j['classification']['SOURCE'] == 'NON_BREAKING'}.size
  potentially_breaking_changes = json.select {|j| j['classification']['SOURCE'] == 'POTENTIALLY_BREAKING'}.size
  breaking_changes = json.select {|j| j['classification']['SOURCE'] == 'BREAKING'}.size
  if json.size > 0

    email += <<-EMAIL

API Changes relative to version #{BASE_PREV_VERSION}

    EMAIL
    email += <<-EMAIL
Full details at https://diff.revapi.org/?groupId=org.realityforge.com.google.elemental2&artifactId=base&old=#{BASE_PREV_VERSION}&new=#{base_version}
    EMAIL
    email += <<-EMAIL if non_breaking_changes > 0
  #{non_breaking_changes} non breaking changes.
    EMAIL
    email += <<-EMAIL if potentially_breaking_changes > 0
  #{potentially_breaking_changes} potentially breaking changes.
    EMAIL
    email += <<-EMAIL if breaking_changes > 0
  #{breaking_changes} breaking changes.
    EMAIL
  else
    rm_f output_file
  end
  email += <<-EMAIL

The Maven dependency can be added to your pom.xml via

    <dependency>
      <groupId>org.realityforge.org.realityforge.com.google.jsinterop</groupId>
      <artifactId>base</artifactId>
      <version>#{base_version}</version>
    </dependency>

Hope this helps,

Peter Donald
  EMAIL
  mkdir_p 'emails'
  File.open 'emails/base-email.txt', 'w' do |file|
    file.write email
  end
  puts 'Announce email template in emails/base-email.txt'
  puts email
end

desc 'Download the latest base project and push a local release'
task 'base:local_release' => %w(base:download base:build base:install)

desc 'Download the latest base project and push a release to Maven Central'
task 'base:release' => %w(base:download base:build base:publish base:save_build base:generate_email)
