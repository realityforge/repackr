require File.expand_path(File.dirname(__FILE__) + '/util')

ELEMENTAL2_GROUP_ID = 'org.realityforge.com.google.elemental2'
ELEMENTAL2_MODULES = %w(core dom indexeddb media promise svg webgl webstorage)
ELEMENTAL2_BRANCH = 'integration'

def elemental2_version
  "1.0.0-rf-#{get_version_suffix('elemental2')}"
end

def elemental2_output_artifact(artifact_key, type = :jar)
  version = elemental2_version
  artifact_id = "elemental2-#{artifact_key}"
  file_id = "#{artifact_id}-#{version}"
  filename = type == :javadocs ? "#{file_id}-javadocs.jar" : type == :sources ? "#{file_id}-sources.jar" : type == :pom ? "#{file_id}.pom" : "#{file_id}.jar"
  "#{dist_dir('elemental2')}/#{ELEMENTAL2_GROUP_ID.gsub('.', '/')}/#{artifact_id}/#{version}/#{filename}"
end

task 'elemental2:download' do
  git_clone('jsinterop', 'elemental2', 'https://github.com/realityforge/elemental2.git', :branch => ELEMENTAL2_BRANCH)
  commit_hash = nil
  in_dir(product_path('jsinterop', 'elemental2')) do
    commit_hash = `git describe --tags --always`.strip
  end
  record_branch('elemental2', ELEMENTAL2_BRANCH)
  if record_commit_hash('elemental2', commit_hash)
    load_and_increment_patch_version('elemental2')
  end
end

task 'elemental2:patch' do
  in_dir(product_path('jsinterop', 'elemental2')) do
    sh 'git reset --hard'
    new_content =
      IO.read('release_elemental.sh').
        gsub(/^read -s gpg_passphrase/, '#set gpg_passphrase=""').
        gsub(/^group_id="com\.google\.elemental2"/, "group_id=\"#{ELEMENTAL2_GROUP_ID}\"").
        gsub(/^\${gpg_passphrase}"/, '${gpg_passphrase}')
    IO.write('release_elemental.sh', new_content)
    IO.write('.bazelrc', <<-RC)
build --incompatible_package_name_is_a_function=false
    RC
  end
end

task 'elemental2:build' do
  output_dir = dist_dir('elemental2')
  rm_rf output_dir
  product_path = product_path('jsinterop', 'elemental2')
  in_dir(product_path) do
    version = elemental2_version
    sh 'bazel clean --expunge'
    ELEMENTAL2_MODULES.each do |artifact_key|
      sh "bazel build //java/elemental2/#{artifact_key}:lib#{artifact_key}.jar"
      sh "bazel build //java/elemental2/#{artifact_key}:lib#{artifact_key}-src.jar"
      artifact_path = "bazel-bin/java/elemental2/#{artifact_key}"
      unpack_dir = "#{WORKSPACE_DIR}/target/elemental2/#{artifact_key}"
      src_dir = "#{unpack_dir}/src"
      javadoc_dir = "#{unpack_dir}/doc"
      mkdir_p src_dir
      mkdir_p javadoc_dir
      in_dir(src_dir)do
      sh "jar -xf #{product_path}/#{artifact_path}/lib#{artifact_key}-src.jar"
      end
      sh "find #{src_dir} -type f -name \"*.java\" | xargs javadoc -d #{javadoc_dir}"

      javadocs_artifact = elemental2_output_artifact(artifact_key, :javadocs)
      mkdir_p File.dirname(javadocs_artifact)
      sh "jar -cf #{javadocs_artifact} -C #{src_dir}/ ."

      rm_rf "#{WORKSPACE_DIR}/target"

      source_artifact = elemental2_output_artifact(artifact_key, :sources)
      mkdir_p File.dirname(source_artifact)
      cp "#{artifact_path}/lib#{artifact_key}-src.jar", source_artifact

      task = Buildr::ZipTask.define_task(elemental2_output_artifact(artifact_key)).tap do |zip|
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
      IO.write(elemental2_output_artifact(artifact_key, :pom), pom)
    end
  end
end

def tasks_for_modules
  version = elemental2_version

  tasks = []
  ELEMENTAL2_MODULES.each do |artifact_key|
    id = "elemental2-#{artifact_key}"
    Buildr.artifact({ :group => ELEMENTAL2_GROUP_ID, :id => id, :version => version, :type => :pom },
                    elemental2_output_artifact(artifact_key, :pom))
    tasks << Buildr.artifact({ :group => ELEMENTAL2_GROUP_ID, :id => id, :version => version, :type => :jar },
                             elemental2_output_artifact(artifact_key, :jar))
    tasks << Buildr.artifact({ :group => ELEMENTAL2_GROUP_ID, :id => id, :version => version, :classifier => :sources, :type => :jar },
                             elemental2_output_artifact(artifact_key, :sources))
  end

  tasks
end

task 'elemental2:install' do
  tasks_for_modules.each do |task|
    in_local_repository = Buildr.repositories.locate(task)
    rm_f in_local_repository
    mkdir_p File.dirname(in_local_repository)
    cp task.name, in_local_repository, :preserve => false
    info "Installed #{task.name} to #{in_local_repository}"
  end
end

RepackrMavenCentralReleaseTool.define_publish_tasks('elemental2',
                                                    :profile_name => 'org.realityforge',
                                                    :username => 'realityforge') do
  task('elemental2:install').invoke
  tasks_for_modules.each(&:upload)
end

desc 'Download the latest elemental2 project and push a local release'
task 'elemental2:local_release' => %w(elemental2:download elemental2:patch elemental2:build elemental2:install)

desc 'Download the latest gwt project and push a release'
task 'elemental2:release' => %w(elemental2:download elemental2:patch elemental2:build elemental2:staging_deploy)
