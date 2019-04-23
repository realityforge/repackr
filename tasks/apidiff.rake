desc 'Download site that hosts API diff reports'
task 'apidiff:download' do
  git_clone('jsinterop', 'site', 'https://github.com/jsinterop/jsinterop.github.io.git')
  in_dir(product_path('jsinterop', 'site')) do
    sh 'git checkout master'
    sh 'git reset --hard origin/master'
    sh 'git pull'
  end
end

# Generate url for api diff
def apidiff_url(title, key, old_version, new_version)
  "https://jsinterop.github.io/api-diff/?key=#{key}&title=#{title}&old=#{old_version}&new=#{new_version}"
end
