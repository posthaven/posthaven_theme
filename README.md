# Posthaven Theme

The `posthaven_theme` gem provides command line tools for developing a Posthaven theme on your computer and pushing updates to Posthaven.

# Requirements

This gem with Ruby 2.0 and above.

# Installation

To install the `posthaven_theme` gem use 'gem install' (you might have use 'sudo gem install')

```
gem install posthaven_theme [optional_theme_id]
```

to update to the latest version

```
gem update posthaven_theme
```

# Usage

Generate a configuration file

```
phtheme configure email@example.org user-api-key example.posthaven.com

```


Download all the theme files

```
phtheme download
```

Upload a theme file

```
phtheme upload assets/layout.liquid
```

Remove a theme file

```
phtheme remove assets/layout.liquid
```

Completely replace shop theme assets with the local assets

```
phtheme replace
```

Watch the theme directory and upload any files as they change

```
phtheme watch
```

# Configuration

Configuration is done via a `config.yml` file in the base directory of your theme. If you are storing your theme in version control it is **highly recommended that you do not** store this file in version control, e.g. in git add it to your `.gitignore`.

`config.yml` has the following options:

* `email` – The email address of your Posthaven account
* `api_key` – Your Posthaven API key
* `site` – The full **Posthaven subdomain** your site, e.g. "my-site.posthaven.com". This **cannot** a custom domain.
* `theme-id` – An optional id for the theme you want to edit, if omitted the default theme for the site will be updated


See the `phtheme configure` command above for one step setup of the `config.yml` file.


# Thanks 

A huge thanks to [Shopify](https://www.shopify.com) for their [shopify_theme](https://github.com/shopify/shopify_theme) gem upon which this is based.
