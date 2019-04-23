desc 'Download site that hosts API diff reports'
task 'apidiff:download' do
  git_clone('jsinterop', 'site', 'https://github.com/jsinterop/jsinterop.github.io.git')
  in_dir(product_path('jsinterop', 'site')) do
    sh 'git checkout master'
    sh 'git reset --hard origin/master'
    sh 'git pull'
  end
end
