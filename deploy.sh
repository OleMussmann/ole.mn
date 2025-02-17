#!/usr/bin/env bash

export NUM_PARALLEL_JOBS=8

set -e  # exit on first error

echo "### remove public folder..."
rm -r public

echo "### build new blog..."
hugo --minify

echo "### strip all EXIF data except ICC color profiles..."
find public -type f -iregex ".*\.\(jpeg\|jpg\|png\|tif\|tiff\|webp\|wav\)" -print0 | xargs -0 -I {} -n1 -P$NUM_PARALLEL_JOBS bash -c 'exiftool -all= -tagsfromfile @ -icc_profile "{}"' &>/dev/null

echo "### deploying blog..."
ssh cosmo "rm -rf /tmp/blog && mkdir /tmp/blog"
rsync -r -z ./public cosmo:/tmp/blog
ssh -t cosmo "\
  sudo rm -rf /var/www/ole.mn/blog/public;
  sudo mv /tmp/blog/public /var/www/ole.mn/blog;
  sudo chown -R nginx:nginx /var/www/ole.mn/blog;
  sudo systemctl restart nginx.service"

echo "### ...deploying done"
