require 'json'

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
  limit_clone_depth = options[:limit_clone_depth].nil? ? true : !!options[:limit_clone_depth]
  category_dir = category_path(category)
  FileUtils.mkdir_p category_dir
  local_dir = product_path(category, name)
  puts "Cloning #{category}:#{name}"
  if File.exist?(local_dir)
    puts "Local directory #{local_dir} exists. Performing fetch..."
    in_dir(local_dir) do
      sh 'git clean -f -d -x'
      sh "git checkout #{branch}"
      sh 'git fetch --prune'
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
  sh "git add #{VERSIONS_FILE}"
  result
end

def load_and_increment_patch_version(name)
  patch_version_json do |data|
    data[name] ||= {}
    data[name]['version'] = (data[name]['version'] || 0) + 1
    data[name]['version']
  end
end

def record_commit_hash(name, commit)
  commit_changed = false
  patch_version_json do |data|
    data[name] ||= {}
    if data[name]['commit'] != commit
      data[name]['commit'] = commit
      commit_changed
    end
  end
  commit_changed
end

def get_version_suffix(name)
    patch_version = load_and_increment_patch_version(name)
  commit_hash = load_version_data(name)['commit']
  "p#{patch_version}-#{commit_hash}"
end
