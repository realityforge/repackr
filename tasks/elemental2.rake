require File.expand_path(File.dirname(__FILE__) + '/util')

ELEMENTAL2_GROUP_ID = 'org.realityforge.com.google.elemental2'
ELEMENTAL2_MODULES = %w(core dom indexeddb media promise svg webgl webstorage)
ELEMENTAL2_BRANCH = 'upstream'
ELEMENTAL2_BRANCHES_TO_MERGE = %w(WebAssembly)
ELEMENTAL2_UPDATE_UPSTREAM = true

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
    `git branch`.split("\n").reject{|line| line =~ / master$/ }.each do |line|
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

task 'elemental2:patch' do
  in_dir(product_path('jsinterop', 'elemental2')) do
    new_content =
      IO.read('release_elemental.sh').
        gsub(/^read -s gpg_passphrase/, '#set gpg_passphrase=""').
        gsub(/^group_id="com\.google\.elemental2"/, "group_id=\"#{ELEMENTAL2_GROUP_ID}\"").
        gsub(/^\${gpg_passphrase}"/, '${gpg_passphrase}')
    IO.write('release_elemental.sh', new_content)
    sh 'git add release_elemental.sh'
    sh "git commit -m \"Patch script to enable automated release\""
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
      sh "jar -cf #{javadocs_artifact} -C #{src_dir}/ ."

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
          gsub('__ARTIFICAT_ID__', "elemental2-#{artifact_key}")

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
  puts "artifact_def(#{artifact_key}, #{type}, #{classifier}) => #{elemental2_output_artifact(artifact_key, type, classifier)}"
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
  sh "git commit -m \"Release the #{elemental2_version} version of the elemental2 project\""
  sh "git tag elemental2-#{elemental2_version}"
  sh "git push origin elemental2-#{elemental2_version}"
  sh 'git push'

  # Save integration branch
  in_dir(product_path('jsinterop', 'elemental2')) do
    sh "git push origin #{elemental2_integration_branch}"
  end
end

task 'elemental2:generate_email' do
  email = <<-EMAIL
To: google-web-toolkit@googlegroups.com
Subject: [ANNOUNCE] (Unofficial) Elemental2 #{elemental2_version} packages published to Maven Central

Elemental2 provides type checked access to browser APIs for Java
code. This is done by using closure extern files and generating
JsTypes, which are part of the new JsInterop specification that
is both implemented in GWT and J2CL.

The official Elemental2 project is available via

https://github.com/google/elemental2

The Elemental2 project does not yet provide regular releases but
is evolving as the underlying Closure compiler externs evolve and
this can make it difficult to adopt Elemental2 in more traditional
build systems.

Until regular Elemental2 releases start occurring, I have decided
to periodically publish versions of Elemental2 artifacts to maven
central. To avoid conflicts with the official releases the groupId
of the artifacts are prefixed with "org.realityforge." and artifacts
use different versions.

This is completely unofficial so please don't bug the original
Elemental2 authors. A new version will be released when I need a
feature present in newer externs or when I am explicitly asked.

The Maven dependencies published can be added to your pom.xml via

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

To see how these artifacts are published see:
https://github.com/realityforge/repackr

Hope it helps someone,

Peter Donald
  EMAIL
  mkdir_p 'emails'
  File.open 'emails/elemental2-email.txt', 'w' do |file|
    file.write email
  end
  puts 'Announce email template in emails/elemental2-email.txt'
  puts email
end

desc 'Download the latest elemental2 project and push a local release'
task 'elemental2:local_release' => %w(elemental2:download elemental2:patch elemental2:build elemental2:install)

desc 'Download the latest elemental2 project and push a release to Maven Central'
task 'elemental2:release' => %w(elemental2:download elemental2:patch elemental2:build elemental2:publish elemental2:save_build elemental2:generate_email)
