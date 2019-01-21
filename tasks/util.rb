require 'json'
require 'mcrt'

WORKSPACE_DIR = File.expand_path(File.dirname(__FILE__) + '/..')

def in_dir(dir)
  current = Dir.pwd
  begin
    Dir.chdir(dir)
    yield
  ensure
    Dir.chdir(current)
  end
end

REPOSITORY_DIR = "#{WORKSPACE_DIR}/projects"

VERSIONS_FILE = "#{WORKSPACE_DIR}/versions.json"

def category_path(category)
  "#{REPOSITORY_DIR}/#{category}"
end

def product_path(category, name)
  "#{category_path(category)}/#{name}"
end

def git_clone(category, name, repository_url, options = {})
  branch = options[:branch] || 'master'
  limit_clone_depth = options[:limit_clone_depth].nil? ? false : !!options[:limit_clone_depth]
  category_dir = category_path(category)
  FileUtils.mkdir_p category_dir
  local_dir = product_path(category, name)
  puts "Cloning #{category}:#{name}"
  if File.exist?(local_dir)
    puts "Local directory #{local_dir} exists. Performing fetch..."
    in_dir(local_dir) do
      sh 'git clean -f -d -x'
      sh 'git fetch --prune'
      sh "git checkout #{branch}"
      sh "git reset --hard origin/#{branch}"
    end
  else
    puts "Local directory #{local_dir} does not exist. Performing clone..."
    in_dir(category_dir) do
      sh "git clone#{limit_clone_depth ? ' --depth 1' : ''} --branch #{branch} #{repository_url} #{name}"
    end
  end
end

def load_version_data(name)
  data = File.exist?(VERSIONS_FILE) ? JSON.parse(IO.read(VERSIONS_FILE)) : {}
  data[name] || {}
end

def patch_version_json
  data = File.exist?(VERSIONS_FILE) ? JSON.parse(IO.read(VERSIONS_FILE)) : {}
  result = yield data
  IO.write(VERSIONS_FILE, JSON.pretty_generate(data) + "\n")
  in_dir(WORKSPACE_DIR) do
    sh "git add #{VERSIONS_FILE}"
  end
  result
end

def load_patch_version(name)
  load_version_data(name)['version'] || (raise "Unable to locate version data for #{name}")
end

def load_and_increment_patch_version(name)
  patch_version_json do |data|
    data[name] ||= {}
    data[name]['version'] = (data[name]['version'] || 0) + 1
    data[name]['version']
  end
end

def record_commit_hash(name, commit)
  record_attribute(name, 'commit', commit)
end

def record_branch(name, branch)
  record_attribute(name, 'branch', branch)
end

def record_attribute(name, key, value)
  patch_version_json do |data|
    data[name] ||= {}
    if data[name][key] != value
      data[name][key] = value
      return true
    end
  end
  false
end

def get_version_suffix(name)
    patch_version = load_patch_version(name)
  commit_hash = load_version_data(name)['commit']
  "p#{patch_version}-#{commit_hash}"
end

def dist_dir(name)
  "#{WORKSPACE_DIR}/dist/#{name}"
end

class RepackrMavenCentralReleaseTool
  class << self
    def define_publish_tasks(name, options = {}, &block)
      desc "Publish #{name} release on maven central"
      task "#{name}:publish" do
        profile_name = options[:profile_name] || (raise ':profile_name not specified when defining tasks')
        username = options[:username] || (raise ':username name not specified when defining tasks')
        password = options[:password] || ENV['MAVEN_CENTRAL_PASSWORD'] || (raise "Unable to locate environment variable with name 'MAVEN_CENTRAL_PASSWORD'")
        RepackrMavenCentralReleaseTool.perform_buildr_release(profile_name, username, password, &block)
      end
    end

    def perform_buildr_release(profile_name, username, password, &block)
      release_to_url = Buildr.repositories.release_to[:url]
      release_to_username = Buildr.repositories.release_to[:username]
      release_to_password = Buildr.repositories.release_to[:password]

      begin
        Buildr.repositories.release_to[:url] = 'https://oss.sonatype.org/service/local/staging/deploy/maven2'
        Buildr.repositories.release_to[:username] = username
        Buildr.repositories.release_to[:password] = password

        r = MavenCentralReleaseTool.new
        r.username = username
        r.password = password
        r.user_agent = "Buildr-#{Buildr::VERSION}"
        while r.get_staging_repositories(profile_name, false).size != 0
          puts 'Another project currently staging. Waiting for other repository to complete. Please visit the website https://oss.sonatype.org/index.html#stagingRepositories to view the other staging attempts.'
          sleep 1
        end
        puts "Beginning upload to staging repository #{profile_name}"

        yield block

        r.release_sole_auto_staging(profile_name)
      ensure
        Buildr.repositories.release_to[:url] = release_to_url
        Buildr.repositories.release_to[:username] = release_to_username
        Buildr.repositories.release_to[:password] = release_to_password
      end
    end
  end
end
