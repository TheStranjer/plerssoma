# PleRSSoma

A bot that looks at one or more RSS feeds and uploads new content from them into Pleroma.

# Installation

This requires:
* Ruby >=3.0.0
* The `bundler` gem

How to install:

```bash
git clone git@github.com:TheStranjer/plerssoma.git
cd plerssoma
bundle # pre-required
```

# Running

You will need to edit `feeds.json` or another similar file. It is a JSON file where the top element is an array. Each array element therein will have an object with the following values:

* `url` -- the URI of the RSS feed that is being examined
* `instance` -- a domain name of the instance that the bot uses
* `bearer_token` -- the token used on the `instance` to identify and authenticate which bot account to upload this to
* `status` -- the format of the status that is uploaded
* `visibility` (Optional, Default: `public`) -- the visibility on Pleroma

There are some variables which ultimately get translated by `status` from the RSS item:

* `$TITLE` -- the title of the item
* `$URL` -- the URL of the item
* `$PUBDATE` -- the DateTime of the item's publication date

Once the `feeds.json` file is ready, you can run this to execute it:

```bash
bundle exec ruby plerssoma.rb
```