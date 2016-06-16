# Posthaven Theme

# Requirements

This gem works with OS X or Windows with Ruby 1.9. 

# Installation

To install the posthaven_theme gem use 'gem install' (you might have use 'sudo gem install')

```
gem install posthaven_theme [optional_theme_id]
```

to update to the latest version

```
gem update posthaven_theme
```

# Usage

TODO - config

Download all the theme files

```
theme download
```

Upload a theme file

```
theme upload assets/layout.liquid
```

Remove a theme file

```
theme remove assets/layout.liquid
```

Completely replace shop theme assets with the local assets

```
theme replace
```

Watch the theme directory and upload any files as they change

```
theme watch
```

# Thanks 

A huge thanks to [Shopify](https://www.shopify.com) for their [shopify_theme](https://github.com/shopify/shopify_theme) gem upon which this is based.
