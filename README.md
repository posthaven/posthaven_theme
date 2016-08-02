# Posthaven Theme

The `posthaven_theme` gem provides command line tools for developing a Posthaven theme on your computer and pushing updates to Posthaven.

# Requirements

## Ruby

This gem requires Ruby 2.0 or above. 

## Posthaven Account

### API Key

Get your [Posthaven account API key here](https://posthaven.com/account/theme_api_key).

### Theme ID

You'll need to create a new theme or copy an existing theme into your account. Once done you can navigate to the theme editor for your theme and find the theme id in the URL.


# Installation

To install the `posthaven_theme` gem use 'gem install' (you might have use 'sudo gem install')

```
gem install posthaven_theme
```

to update to the latest version

```
gem update posthaven_theme
```

# Usage

List available commands

```
phtheme help
```

Generate a configuration file. For your API key see [above](#posthaven_account).

```
phtheme configure api-key

```

Upload a theme file

```
phtheme upload assets/layout.liquid
```

Remove a theme file

```
phtheme remove assets/layout.liquid
```

Completely remove all old theme files and replace them with current local versions

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

* `api_key` – Your Posthaven API key
* `theme_id` – The ID of the theme to edit. If you do not know the ID run the `configure` command above with only a api-key and you'll be guided through selecting an existing theme or creating a new one.

See the `phtheme configure` command above for one step setup of the `config.yml` file.

# Thanks 

A huge thanks to [Shopify](https://www.shopify.com) for their [shopify_theme](https://github.com/shopify/shopify_theme) gem upon which this is based.
