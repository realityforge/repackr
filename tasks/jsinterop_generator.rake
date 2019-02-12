require File.expand_path(File.dirname(__FILE__) + '/util')

GENERATOR_GROUP_ID = 'org.realityforge.com.google.jsinterop'
GENERATOR_JARS = %w(closure:libclosure.jar closure/helper:libhelper.jar closure/visitor:libvisitor.jar helper:libhelper.jar model:libmodel.jar visitor:libvisitor.jar writer:libwriter.jar)
GENERATOR_BRANCH = 'upstream'
GENERATOR_BRANCHES_TO_MERGE = %w(TravisCiIntegration AddGitignore FixPomForMavenCentralPublish FixJavadocs)
GENERATOR_UPDATE_UPSTREAM = true

def generator_version
  "1.0.0-#{get_version_suffix('jsinterop-generator')}"
end

def generator_integration_branch
  "integration-b#{load_build_number('jsinterop-generator')}"
end

def generator_output_artifact(type = :jar, classifier = nil)
  version = generator_version
  artifact_id = 'closure-generator'
  filename = "#{artifact_id}-#{version}#{classifier.nil? ? '' : "-#{classifier}"}.#{type}"
  "#{dist_dir('jsinterop-generator')}/#{GENERATOR_GROUP_ID.gsub('.', '/')}/#{artifact_id}/#{version}/#{filename}"
end

task 'generator:download' do
  git_clone('jsinterop', 'jsinterop-generator', 'https://github.com/realityforge/jsinterop-generator.git')
  if GENERATOR_UPDATE_UPSTREAM
    in_dir(product_path('jsinterop', 'jsinterop-generator')) do
      `git remote rm upstream`
      sh 'git remote add upstream https://github.com/google/jsinterop-generator.git'
      sh 'git fetch upstream --prune'
      sh 'git checkout upstream'
      sh 'git reset --hard upstream/master'
      sh 'git push -f'
    end
  end
  # Remove all non master local branches
  in_dir(product_path('jsinterop', 'jsinterop-generator')) do
    sh 'git checkout master'
    sh 'git reset --hard origin/master'
    `git branch`.split("\n").reject {|line| line =~ / master$/}.each do |line|
      sh "git branch -D #{line}"
    end
  end

  # Checkout base branch/commit/etc
  commit_hash = nil
  in_dir(product_path('jsinterop', 'jsinterop-generator')) do
    sh "git checkout #{GENERATOR_BRANCH}"
    commit_hash = `git describe --tags --always`.strip
  end

  record_branch('jsinterop-generator', GENERATOR_BRANCH)
  if record_commit_hash('jsinterop-generator', commit_hash)
    load_and_increment_build_number('jsinterop-generator')
  end

  in_dir(product_path('jsinterop', 'jsinterop-generator')) do
    `git branch -D #{generator_integration_branch} 2>&1`
    `git push origin :#{generator_integration_branch} 2>&1`
    sh "git checkout -b#{generator_integration_branch}"
    GENERATOR_BRANCHES_TO_MERGE.each do |branch|
      sh "git merge --no-edit origin/#{branch}"
    end
  end
end

task 'generator:build' do
  output_dir = dist_dir('jsinterop-generator')
  rm_rf output_dir
  product_path = product_path('jsinterop', 'jsinterop-generator')
  in_dir(product_path) do
    unless ENV['BAZEL'] == 'no'
      #TODO: sh 'bazel clean --expunge'
      sh 'bazel build //...'
    end
    version = generator_version

    unpack_dir = "#{WORKSPACE_DIR}/target/jsinterop-generator"
    src_dir = "#{unpack_dir}/src"
    classes_dir = "#{unpack_dir}/classes"
    javadoc_dir = "#{unpack_dir}/doc"
    rm_rf unpack_dir
    mkdir_p src_dir
    mkdir_p classes_dir
    mkdir_p javadoc_dir
    GENERATOR_JARS.each do |jar_key|
      artifact_path = "bazel-bin/java/jsinterop/generator/#{jar_key}"
      unless ENV['BAZEL'] == 'no'
        sh "bazel build //java/jsinterop/generator/#{jar_key}"
        sh "bazel build //java/jsinterop/generator/#{jar_key.gsub('.jar', '-src.jar')}"
      end

      in_dir(src_dir) do
        src_filename = "#{product_path}/#{artifact_path.gsub(':', '/').gsub('.jar', '-src.jar')}"
        sh "jar -xf #{src_filename}" if File.exist?(src_filename)
      end
      in_dir(classes_dir) do
        sh "jar -xf #{product_path}/#{artifact_path.gsub(':', '/')}"
      end
    end

    sh 'bazel build //java/jsinterop/generator/closure:ClosureJsinteropGenerator_deploy.jar'

    sh "find #{src_dir} -type f -name \"*.java\" | xargs javadoc -d #{javadoc_dir}"

    javadocs_artifact = generator_output_artifact(:jar, :javadoc)
    mkdir_p File.dirname(javadocs_artifact)
    sh "jar -cf #{javadocs_artifact} -C #{javadoc_dir}/ ."

    source_artifact = generator_output_artifact(:jar, :sources)
    mkdir_p File.dirname(source_artifact)
    sh "jar -cf #{source_artifact} -C #{src_dir}/ ."

    jar_artifact = generator_output_artifact(:jar)
    mkdir_p File.dirname(jar_artifact)
    sh "jar -cf #{jar_artifact} -C #{classes_dir}/ ."

    all_artifact = generator_output_artifact(:jar, :all)
    mkdir_p File.dirname(all_artifact)
    cp 'bazel-bin/java/jsinterop/generator/closure/ClosureJsinteropGenerator_deploy.jar', all_artifact.to_s

    pom =
      IO.read('maven/pom-closure-generator.xml').
        gsub('__GROUP_ID__', GENERATOR_GROUP_ID).
        gsub('__VERSION__', version).
        gsub('__ARTIFICAT_ID__', 'closure-generator')

    pom_artifact = generator_output_artifact(:pom)
    IO.write(pom_artifact, pom)

    sign_task(pom_artifact)
    sign_task(jar_artifact)
    sign_task(all_artifact)
    sign_task(javadocs_artifact)
    sign_task(source_artifact)
  end
end

def artifact_def(type, classifier = nil)
  Buildr.artifact({ :group => GENERATOR_GROUP_ID, :id => 'closure-generator', :version => generator_version, :type => type, :classifier => classifier }).
    from(generator_output_artifact(type, classifier))
end

def tasks_for_modules
  tasks = []
  tasks << artifact_def(:pom)
  tasks << artifact_def('pom.asc')
  tasks << artifact_def(:jar)
  tasks << artifact_def('jar.asc')
  tasks << artifact_def(:jar, :sources)
  tasks << artifact_def('jar.asc', :sources)
  tasks << artifact_def(:jar, :javadoc)
  tasks << artifact_def('jar.asc', :javadoc)
  tasks
end

task 'generator:install' do
  tasks_for_modules.each do |task|
    in_local_repository = Buildr.repositories.locate(task)
    rm_f in_local_repository
    mkdir_p File.dirname(in_local_repository)
    cp task.instance_variable_get('@from'), in_local_repository, :preserve => false
    info "Installed #{task.name} to #{in_local_repository}"
  end
end

RepackrMavenCentralReleaseTool.define_publish_tasks('generator',
                                                    :profile_name => 'org.realityforge',
                                                    :username => 'realityforge') do
  task('generator:install').invoke
  tasks_for_modules.select {|t| t.type != :pom}.each(&:upload)
end

task 'generator:save_build' do
  sh 'git reset'
  sh 'git add versions.json'
  sh "git commit -m \"Release the #{generator_version} version of the jsinterop-generator project\""
  sh "git tag jsinterop-generator-#{generator_version}"
  sh "git push origin jsinterop-generator-#{generator_version}"
  sh 'git push'

  # Save integration branch
  in_dir(product_path('jsinterop', 'jsinterop-generator')) do
    sh "git push origin #{generator_integration_branch}"
  end
end

task 'generator:generate_email' do

  # TODO: Generate an API diff as part of the release and commit it locally and report it in email

  email = <<-EMAIL
To: google-web-toolkit@googlegroups.com
Subject: [ANNOUNCE] (Unofficial) JsInterop-Generator #{generator_version} packages published to Maven Central

The jsinterop generator is a java program that takes closure extern files as input and generates
Java classes annotated with JsInterop annotations.

The official JsInterop-Generator project is available via

https://github.com/google/jsinterop-generator

The JsInterop-Generator project does not yet provide regular releases
as it is primarily used to build Elemental2. This makes it difficult
to adopt the JsInterop-Generator in more traditional build systems.

Until regular JsInterop-Generator releases start occurring, I have
decided to periodically publish versions of the JsInterop-Generator
artifact to maven central. To avoid conflicts with the official releases
the groupId of the artifacts are prefixed with "org.realityforge." and
the artifacts use different versions.

This is completely unofficial so please don't bug the original
JsInterop-Generator authors. A new version will be released when I need
it or when I am explicitly asked.

The Maven dependency published to Maven Central can be added to your
pom.xml via

    <dependency>
      <groupId>org.realityforge.org.realityforge.com.google.jsinterop</groupId>
      <artifactId>closure-generator</artifactId>
      <version>#{generator_version}</version>
    </dependency>

Hope it helps someone,

Peter Donald
  EMAIL
  mkdir_p 'emails'
  File.open 'emails/generator-email.txt', 'w' do |file|
    file.write email
  end
  puts 'Announce email template in emails/generator-email.txt'
  puts email
end

desc 'Download the latest generator project and push a local release'
task 'generator:local_release' => %w(generator:download generator:build generator:install)

desc 'Download the latest generator project and push a release to Maven Central'
task 'generator:release' => %w(generator:download generator:build generator:publish generator:save_build generator:generate_email)
