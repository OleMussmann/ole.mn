#!/usr/bin/env python3

import re

TITLE = '"Neurodiversity At The Workplace: A Handbook"'
SUMMARY = '"my_summary"'
DESCRIPTION = '"my_description"'

CHAPTERS = [
        "../../content/posts/2025-06-neurodiversity-1/index.md",
        "../../content/posts/2025-07-neurodiversity-2/index.md",
        "../../content/posts/2025-07-neurodiversity-3/index.md",
        "../../content/posts/2025-07-neurodiversity-4/index.md",
        "../../content/posts/2025-07-neurodiversity-glossary/_index.md",
        ]

OUTPUT_FILE_NAME = "./01_source_files/index.md"

BLOG_START_TAG = "<!-- START_FOR_BLOG -->"
BLOG_END_TAG = "<!-- END_FOR_BLOG -->"
EBOOK_START_TAG = "<!-- START_FOR_EBOOK"
EBOOK_END_TAG = "END_FOR_EBOOK -->"

# Read first chapter
with open(CHAPTERS[0]) as first_chapter_file:
    post_text = first_chapter_file.read()

# Read other chapters
OTHER_CHAPTERS = []
for file in CHAPTERS[1:]:
    with open(file) as chapter_file:
        OTHER_CHAPTERS.append(chapter_file.read())

def replace_in_header(item: str, replacement_string: str, text_body: str) -> str:
    return re.sub(
        item + " = .*",
        item + ' = ' + replacement_string,
        text_body)

def strip_header(text_body: str) -> str:
    return re.sub(
        "\\+\\+\\+.*\\+\\+\\+",
        "",
        text_body,
        flags=re.DOTALL
        )

def blog_to_ebook_content(text_body: str) -> str:
    return re.sub(
            # remove blog-only content non-greedily with .*?
            BLOG_START_TAG + ".*?" + BLOG_END_TAG + "|" + \
                    # remove ebook tags
                    EBOOK_START_TAG + "|" + \
                    EBOOK_END_TAG,
            "",
            text_body,
            flags=re.DOTALL
            )

def dont_convert_images(text_body: str) -> str:
    return re.sub(
            "\\.jpg",
            ".jpg#nowebp",
            text_body
            )

post_text = replace_in_header("title", TITLE, post_text)
post_text = replace_in_header("summary", SUMMARY, post_text)
post_text = replace_in_header("description", DESCRIPTION, post_text)
post_text = replace_in_header("hideBackToTop", "true", post_text)
post_text = replace_in_header("readTime", "false", post_text)
post_text = replace_in_header("showTags", "false", post_text)
post_text = replace_in_header("toc", "false", post_text)
post_text = blog_to_ebook_content(post_text)
post_text = dont_convert_images(post_text)

for chapter in OTHER_CHAPTERS:
    post_text += dont_convert_images(blog_to_ebook_content(strip_header(chapter)))

with open(OUTPUT_FILE_NAME, 'w') as output_file:
    output_file.write(post_text)
