#!/usr/bin/env sh

echo
echo "### Clear out previous files to start with a clean slate..."
rm -rf ./01_source_files/*
rm -rf ./02_hugo_output/*
rm -rf ./03_wget_output/*
rm -rf ./04_cleaned_wget_output/*

echo
echo "### Copy image files..."
for post_folder in \
  "../../content/posts/2025-06-neurodiversity-1/" \
  "../../content/posts/2025-07-neurodiversity-2/" \
  "../../content/posts/2025-07-neurodiversity-3/" \
  "../../content/posts/2025-07-neurodiversity-4/" \
  "../../content/posts/2025-07-neurodiversity-glossary/"; do
  cp $post_folder/* ./01_source_files/
done

echo
echo "### Remove original index.md files..."
rm -rf ./01_source_files/index.md
rm -rf ./01_source_files/_index.md

echo
echo "### Merge index.md files and write to ./01_source_files/index.md ..."
python3 ./merge_md_files.py

cd ../..

echo
echo "### Start \`hugo\` server in background..."
hugo serve --buildDrafts --cleanDestinationDir --contentDir ./ebook/neurodiversity/01_source_files/ --destination ./ebook/neurodiversity/02_hugo_output/ --gc --ignoreCache --port 1314 &
cd -

echo
echo "### Wait for the \`hugo\` server to start..."
sleep 3

echo
echo "### \`wget\`-ing the rendered HTML..."
wget --recursive --level=inf --no-parent --page-requisites --adjust-extension --convert-links --directory-prefix=./03_wget_output/ http://localhost:1314

echo
echo "### Killing the \`hugo\` server..."
pkill -f "hugo serve"

echo
echo "### Copying files to \`04_cleaned_wget_output\` folder"
cp ./03_wget_output/localhost:1314/*.{png,jpg,svg} ./04_cleaned_wget_output/
cp ./03_wget_output/localhost:1314/index.html ./04_cleaned_wget_output/
cp -r ./03_wget_output/localhost:1314/fonts ./04_cleaned_wget_output/
mkdir ./04_cleaned_wget_output/assets/
cp ./ebook.css ./04_cleaned_wget_output/assets/

echo
echo "### Clean up HTML file..."
python3 ./clean_up_html.py

echo
echo "### Create ebook..."
cd ./04_cleaned_wget_output/
#style_sheet=$(ls ./assets/*.css)
# ebook-convert index.html Neurodiversity_at_the_Workplace.epub --level1-toc="//h:h1" --level2-toc="//h:h2" --level3-toc="//h:h3" --extra-css="../ebook.css" --title="Neurodiversity at the Workplace — a Handbook" --authors="Ole Mussmann" --language="English" --epub-version=3  --cover="../cover.jpg" --page-breaks-before="//h:h1"
ebook-convert index.html Neurodiversity_at_the_Workplace.epub --level1-toc="//h:h1" --level2-toc="//h:h2" --level3-toc="//h:h3" --title="Neurodiversity at the Workplace — a Handbook" --authors="Ole Mussmann" --language="English" --epub-version=3  --cover="../cover.jpg" --page-breaks-before="//h:h1" --base-font-size=0

ebook-polish --embed-fonts --subset-fonts --jacket --remove-unused-css --add-soft-hyphens Neurodiversity_at_the_Workplace.epub Neurodiversity_at_the_Workplace.epub
