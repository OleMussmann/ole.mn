#!/usr/bin/env python3
from bs4 import BeautifulSoup

HTML_FILE = "./04_cleaned_wget_output/index.html"

with open(HTML_FILE) as source:
    soup = BeautifulSoup(source.read(), 'html.parser')

# remove blog-specific elements
soup.header.extract()

for div in soup.find_all("div"):
    for html_class in ["intro", "social-icons", "list-container", "root_login"]:
        if div.get("class"):
            if html_class in div.get("class"):
                div.extract()

for a in soup.find_all("a"):
    if a.get("class"):
        if "root_login" in a.get("class"):
            a.extract()

soup.footer.extract()

# remove JavaScript
for script in soup.find_all("script"):
    script.extract()

# remove original CSS, index.xml and favicon
for link in soup.find_all("link"):
    if link.get("href"):
        if link["href"].endswith("css") or link["href"].endswith("ico") or link["href"].endswith("xml"):
            link.extract()

# add stipped-down CSS
soup.head.append(soup.new_tag("link", href="./assets/ebook.css", rel="stylesheet"))

# remove hashtags from headers
for header_type_number in range(5):
    for header in soup.find_all("h" + str(header_type_number)):
        if header.a:
            header.a.extract()

# remove dark image alternatives
for figure in soup.find_all("figure"):
    if "img-dark" in figure["class"]:
        figure.extract()

with open(HTML_FILE, 'w') as destination:
    destination.write(str(soup))
