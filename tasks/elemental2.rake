require File.expand_path(File.dirname(__FILE__) + '/util')

ELEMENTAL2_GROUP_ID = 'org.realityforge.com.google.elemental2'
ELEMENTAL2_MODULES = %w(core dom indexeddb media promise svg webgl webstorage webassembly)
ELEMENTAL2_BRANCH = 'upstream'
ELEMENTAL2_BRANCHES_TO_MERGE = %w(VertispanChanges NameEventHandlerParameters UseWhatWGConsoleDefinition)
ELEMENTAL2_UPDATE_UPSTREAM = true
# TODO: This should be automated somehow
ELEMENTAL2_PREV_VERSION='1.0.0-b19-fb227e3'

def elemental2_version
  "1.0.0-#{get_version_suffix('elemental2')}"
end

def elemental2_integration_branch
  "integration-b#{load_build_number('elemental2')}"
end

def elemental2_output_artifact(artifact_key, type = :jar, classifier = nil)
  version = elemental2_version
  artifact_id = "elemental2-#{artifact_key}"
  filename = "#{artifact_id}-#{version}#{classifier.nil? ? '' : "-#{classifier}"}.#{type}"
  "#{dist_dir('elemental2')}/#{ELEMENTAL2_GROUP_ID.gsub('.', '/')}/#{artifact_id}/#{version}/#{filename}"
end

task 'elemental2:download' do
  git_clone('jsinterop', 'elemental2', 'https://github.com/realityforge/elemental2.git')
  if ELEMENTAL2_UPDATE_UPSTREAM
    in_dir(product_path('jsinterop', 'elemental2')) do
      `git remote rm upstream`
      sh 'git remote add upstream  https://github.com/google/elemental2.git'
      sh 'git fetch upstream --prune'
      sh 'git checkout upstream'
      sh 'git reset --hard upstream/master'
      sh 'git push -f'
    end
  end
  # Remove all non master local branches
  in_dir(product_path('jsinterop', 'elemental2')) do
    sh 'git checkout master'
    sh 'git reset --hard origin/master'
    `git branch`.split("\n").reject {|line| line =~ / master$/}.each do |line|
      sh "git branch -D #{line}"
    end
  end

  # Checkout base branch/commit/etc
  commit_hash = nil
  in_dir(product_path('jsinterop', 'elemental2')) do
    sh "git checkout #{ELEMENTAL2_BRANCH}"
    commit_hash = `git describe --tags --always`.strip
  end

  record_branch('elemental2', ELEMENTAL2_BRANCH)
  if record_commit_hash('elemental2', commit_hash)
    load_and_increment_build_number('elemental2')
  end

  in_dir(product_path('jsinterop', 'elemental2')) do
    `git branch -D #{elemental2_integration_branch} 2>&1`
    `git push origin :#{elemental2_integration_branch} 2>&1`
    sh "git checkout -b#{elemental2_integration_branch}"
    ELEMENTAL2_BRANCHES_TO_MERGE.each do |branch|
      sh "git merge --no-edit origin/#{branch}"
    end
  end
end

task 'elemental2:build' do
  output_dir = dist_dir('elemental2')
  rm_rf output_dir
  product_path = product_path('jsinterop', 'elemental2')
  in_dir(product_path) do
    version = elemental2_version
    sh 'bazel clean --expunge' unless ENV['BAZEL'] == 'no'
    ELEMENTAL2_MODULES.each do |artifact_key|
      sh "bazel build //java/elemental2/#{artifact_key}:lib#{artifact_key}.jar" unless ENV['BAZEL'] == 'no'
      sh "bazel build //java/elemental2/#{artifact_key}:lib#{artifact_key}-src.jar" unless ENV['BAZEL'] == 'no'
      artifact_path = "bazel-bin/java/elemental2/#{artifact_key}"
      unpack_dir = "#{WORKSPACE_DIR}/target/elemental2/#{artifact_key}"
      src_dir = "#{unpack_dir}/src"
      javadoc_dir = "#{unpack_dir}/doc"
      mkdir_p src_dir
      mkdir_p javadoc_dir
      in_dir(src_dir) do
        sh "jar -xf #{product_path}/#{artifact_path}/lib#{artifact_key}-src.jar"
      end
      sh "find #{src_dir} -type f -name \"*.java\" | xargs javadoc -d #{javadoc_dir}"

      javadocs_artifact = elemental2_output_artifact(artifact_key, :jar, :javadoc)
      mkdir_p File.dirname(javadocs_artifact)
      sh "jar -cf #{javadocs_artifact} -C #{javadoc_dir}/ ."

      rm_rf "#{WORKSPACE_DIR}/target"

      source_artifact = elemental2_output_artifact(artifact_key, :jar, :sources)
      mkdir_p File.dirname(source_artifact)
      cp "#{artifact_path}/lib#{artifact_key}-src.jar", source_artifact

      jar_artifact = elemental2_output_artifact(artifact_key, :jar)
      task = Buildr::ZipTask.define_task(jar_artifact).tap do |zip|
        zip.merge("#{artifact_path}/lib#{artifact_key}.jar")
        zip.merge("#{artifact_path}/lib#{artifact_key}-src.jar")
      end
      task.invoke
      Buildr.application.instance_variable_get('@tasks').delete(task.name)
      pom =
        IO.read("maven/pom-#{artifact_key}.xml").
          gsub('__GROUP_ID__', ELEMENTAL2_GROUP_ID).
          gsub('__VERSION__', version).
          gsub('__ARTIFICAT_ID__', "elemental2-#{artifact_key}").
            gsub(<<DEP,<<REPLACEMENT)
    <dependency>
      <groupId>com.google.jsinterop</groupId>
      <artifactId>base</artifactId>
      <version>1.0.0-RC1</version>
    </dependency>
DEP
    <dependency>
      <groupId>#{BASE_GROUP_ID}</groupId>
      <artifactId>base</artifactId>
      <version>#{base_version}</version>
    </dependency>
REPLACEMENT

      pom_artifact = elemental2_output_artifact(artifact_key, :pom)
      IO.write(pom_artifact, pom)

      sign_task(pom_artifact)
      sign_task(jar_artifact)
      sign_task(javadocs_artifact)
      sign_task(source_artifact)
    end
  end
end

def artifact_def(artifact_key, type, classifier = nil)
  Buildr.artifact({ :group => ELEMENTAL2_GROUP_ID,
                    :id => "elemental2-#{artifact_key}",
                    :version => elemental2_version,
                    :type => type,
                    :classifier => classifier }).
    from(elemental2_output_artifact(artifact_key, type, classifier))
end

def tasks_for_modules
  tasks = []
  ELEMENTAL2_MODULES.each do |artifact_key|
    tasks << artifact_def(artifact_key, :pom)
    tasks << artifact_def(artifact_key, 'pom.asc')
    tasks << artifact_def(artifact_key, :jar)
    tasks << artifact_def(artifact_key, 'jar.asc')
    tasks << artifact_def(artifact_key, :jar, :sources)
    tasks << artifact_def(artifact_key, 'jar.asc', :sources)
    tasks << artifact_def(artifact_key, :jar, :javadoc)
    tasks << artifact_def(artifact_key, 'jar.asc', :javadoc)
  end

  tasks
end

task 'elemental2:install' do
  tasks_for_modules.each do |task|
    in_local_repository = Buildr.repositories.locate(task)
    rm_f in_local_repository
    mkdir_p File.dirname(in_local_repository)
    cp task.instance_variable_get('@from'), in_local_repository, :preserve => false
    info "Installed #{task.name} to #{in_local_repository}"
  end
end

RepackrMavenCentralReleaseTool.define_publish_tasks('elemental2',
                                                    :profile_name => 'org.realityforge',
                                                    :username => 'realityforge') do
  task('elemental2:install').invoke
  tasks_for_modules.select {|t| t.type != :pom}.each(&:upload)
end

task 'elemental2:save_build' do
  sh 'git reset'
  sh 'git add versions.json'
  sh "git commit --allow-empty -m \"Release the #{elemental2_version} version of the elemental2 project\""
  sh "git tag elemental2-#{elemental2_version}"
  sh "git push origin elemental2-#{elemental2_version}"
  sh 'git push'

  # Save integration branch
  in_dir(product_path('jsinterop', 'elemental2')) do
    sh "git push origin #{elemental2_integration_branch}"
  end
end

task 'elemental2:generate_email' do

  # TODO: Generate an API diff as part of the release and publish it somewhere rather than linking to online service

  email = <<-EMAIL
To: google-web-toolkit@googlegroups.com
Subject: [ANN] (Unofficial) Elemental2 #{elemental2_version} release

Elemental2 provides type checked access to browser APIs for Java
code. This is done by using closure extern files and generating
JsTypes, which are part of the new JsInterop specification that
is both implemented in GWT and J2CL.

https://github.com/google/elemental2

This is an unofficial release to Maven Central under a different groupId.
Please don't bug the original authors. Versions are released on demand.
  EMAIL

  require 'json'

  added_header = false

  ELEMENTAL2_MODULES.each do |m|
    puts "Retrieving changes for #{m}"

    revapi_diff = Buildr.artifact(:revapi_diff)

    old_api = Buildr.artifact("org.realityforge.com.google.elemental2:elemental2-#{m}:jar:#{ELEMENTAL2_PREV_VERSION}")
    new_api = Buildr.artifact("org.realityforge.com.google.elemental2:elemental2-#{m}:jar:#{elemental2_version}")

    revapi_diff.invoke
    old_api.invoke
    new_api.invoke

    mkdir_p 'emails'
    output_file = "emails/elemental2-#{m}-#{ELEMENTAL2_PREV_VERSION}-to-#{elemental2_version}-diff.json"

    sh ['java', '-jar', revapi_diff.to_s, '--old-api', old_api.to_s, '--new-api', new_api.to_s, '--output-file', output_file].join(' ')

    json = JSON.parse(IO.read(output_file))
    non_breaking_changes = json.select{|j|j['classification']['SOURCE'] == 'NON_BREAKING'}.size
    potentially_breaking_changes = json.select{|j|j['classification']['SOURCE'] == 'POTENTIALLY_BREAKING'}.size
    breaking_changes = json.select{|j|j['classification']['SOURCE'] == 'BREAKING'}.size
    if json.size > 0
      unless added_header
        added_header = true
        email += <<-EMAIL

API Changes relative to Elemental2 version #{ELEMENTAL2_PREV_VERSION}

        EMAIL
      end
      email += <<-EMAIL
elemental2-#{m}: Full details at https://diff.revapi.org/?groupId=org.realityforge.com.google.elemental2&artifactId=elemental2-#{m}&old=#{ELEMENTAL2_PREV_VERSION}&new=#{elemental2_version}
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
  end

  email += <<-EMAIL

The Maven dependencies can be added to your pom.xml via

    <dependency>
      <groupId>org.realityforge.com.google.elemental2</groupId>
      <artifactId>${artifact-id}</artifactId>
      <version>#{elemental2_version}</version>
    </dependency>

where artifact-id is one of

* elemental2-core
* elemental2-dom
* elemental2-promise
* elemental2-indexeddb
* elemental2-svg
* elemental2-webgl
* elemental2-media
* elemental2-webstorage
* elemental2-webassembly

Hope this helps,

Peter Donald
  EMAIL

  File.open 'emails/elemental2-email.txt', 'w' do |file|
    file.write email
  end
  puts 'Announce email template in emails/elemental2-email.txt'
  puts email
end

desc 'Download the latest elemental2 project and push a local release'
task 'elemental2:local_release' => %w(elemental2:download elemental2:build elemental2:install)

desc 'Download the latest elemental2 project and push a release to Maven Central'
task 'elemental2:release' => %w(elemental2:download elemental2:build elemental2:publish elemental2:save_build elemental2:generate_email)
