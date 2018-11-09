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
      sh "git clone#{limit_clone_depth ? ' --depth 1' : ''} #{repository_url} #{name}"
    end
  end
end

def patch_version_json
  require 'json'
  filename = "#{WORKSPACE_DIR}/versions.json"
  data = File.exist?(filename) ? JSON.parse(IO.read(filename)) : {}
  result = yield data
  IO.write(filename, JSON.pretty_generate(data) + "\n")
  sh "git add #{filename}"
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
  patch_version_json do |data|
    data[name] ||= {}
    data[name]['commit'] = commit
  end
end
