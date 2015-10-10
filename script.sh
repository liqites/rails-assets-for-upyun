# !/bin/bash

echo $(rbenv version)

rm rails-assets-for-upyun-0.0.9.gem
gem uninstall rails-assets-for-upyun
gem build rails-assets-for-upyun.gemspec
gem install rails-assets-for-upyun-0.0.9.gem