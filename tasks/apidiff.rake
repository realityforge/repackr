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
def apidiff_url(key, old_version, new_version)
  "https://jsinterop.github.io/api-diff/?key=#{key}&old=#{old_version}&new=#{new_version}"
end

# Generate local filename for api diff report
def apidiff_local_file(key, old_version, new_version)
  "#{product_path('jsinterop', 'site')}/api-diff/data/#{key}/#{old_version}-to-#{new_version}.json"
end

# Generate API diff report
def apidiff_generate(partial_spec, key, old_version, new_version)
  puts "Generating API diff for #{key}"

  revapi_diff = Buildr.artifact(:revapi_diff)

  old_api = Buildr.artifact("#{partial_spec}:#{old_version}")
  new_api = Buildr.artifact("#{partial_spec}:#{new_version}")

  revapi_diff.invoke
  old_api.invoke
  new_api.invoke

  output_file = apidiff_local_file(key, old_version, new_version)
  mkdir_p File.dirname(output_file)

  sh ['java', '-jar', revapi_diff.to_s, '--old-api', old_api.to_s, '--new-api', new_api.to_s, '--output-file', output_file].join(' ')

  in_dir(product_path('jsinterop', 'site')) do
    sh "git add #{output_file}"
  end
  output_file
end
