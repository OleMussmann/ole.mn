## PRs, changes
### typo/layouts/_default/home.html
homeCollectionsTitle: h1 -> h2 (SEO)

### typo/layouts/partials/head.html
preload fonts

### typo/layouts/partials/header.html
Title h1 -> div (SEO)
Title = .Site.Params.header (or fallback .Site.Title) (split page title and rendered title)

### typo-plus/archetypes/default.md

### typo-plus/layouts/_default/{single,slide}.html
### typo-plus/static/js/mermaid.js
make mermaid configurable from hugo.toml
remove inline js (increase security through server headers)
