# Vouch-proxy authentication for Dokku apps

A [Dokku][dokku] plugin which allows access to dokku apps to be limited to users
authenticated with any of the OAuth login providers supported by
[Vouch proxy][vouch]: for instance, Google, GitHub, and many others.

**WARNING: the code in this plugin is extremely fragile, and I can't
guarantee it'll work on any systems other than my own. It's only here until
I can migrate my web apps from Dokku to some other PAAS – probably
[CapRover][caprover].**

[dokku]:    https://github.com/dokku/dokku
[vouch]:    https://github.com/vouch/vouch-proxy
[caprover]: https://github.com/caprover/caprover

As a side effect, this plugin also allows dokku apps to specify commands
that need to be run when the ["nginx-pre-reload"][nginx-pre-reload] event
happens in the lifecycle of the app -- i.e., just before dokku reloads ningx
conf files. (This actually can happen more often than you might expect
-- so make sure any actions taken by your commands allow for the
possibility they might already have been run -- i.e. are idempotent.)

["nginx-pre-reload"]: http://dokku.viewdocs.io/dokku~v0.21.4/development/plugin-triggers/#nginx-pre-reload

Why might you want to do that? Well, one reason would be to get around the
constraints Dokku imposes on how Docker-based apps may customize the nginx
configuration -- they have to store a complete `.sigil` template inside the
Docker container, even if it is never used by anything running in the
container... There seems to be no easy way of overriding *bits*
of the app=specific Nginx config. Anyway.
If you're careful, this plugin should let you alter or check the nginx.conf
file just before it loads.

## Installation

```shell
# for dokku >= 0.4.x
dokku plugin:install https://github.com/phlummox/dokku-vouch-auth
```

To update it later:

```shell
dokku plugin:update vouch-auth
```

## Usage

For your Docker-based Dokku app, put a script you want to run in
your Git repository, with the filename `hooks/nginx-pre-reload`.

It can be in any sort of language you want, as long as the
file is executable. A typical thing you might want to do is
run the script
`/var/lib/dokku/plugins/available/vouch-auth/add-vouch-auth.pl`.
(There's probably an environment var that's more portable than
hard=coding `/var/lib/dokku/plugins/available/`, but I forget
what it is.)

`add-vouch-auth.pl` expects three arguments:

- the *app name* for a Dokku app running a Vouch proxy – conventionally,
  `vouch`.
- the *port* on the localhost where a vouch proxy can be accessed –
  conventionally, port 9090.
- the domain your Dokku apps are running under – e.g.
  `mysubdomain.mydomain.org`.

(These, too, could probably be got from environment vars with a little
effort.) Also it expects the `APP` environment var to contain the name
of your Dokku app.

Triggers:
 - [x] post-extract: The plugin executes code when the
   [`post-extract`][post-extract] trigger occurs, to copy the
   file `hooks/nginx-pre-reload` from your Git repository,
   into the directory `/home/dokku/myapp` (or similar) where
   Dokku stores the config files for your app.
 - [x] nginx-pre-reload: You can supply a script in `hooks/nginx-pre-reload`
   which will be executed before ningx reload is done.

[post-extract]: http://dokku.viewdocs.io/dokku~v0.21.4/development/plugin-triggers/#post-extract
[nginx-pre-reload]: http://dokku.viewdocs.io/dokku~v0.21.4/development/plugin-triggers/#nginx-pre-reload

### How it works

`add-vouch-auth.pl` generates a patch file, intended to add
Vouch-proxy-based authentication to your app's `nginx.conf`
configuration file, and uses the [`patch`][patch] program to apply it.
If it can't, it emits a warning but doesn't fail.

[patch]: http://savannah.gnu.org/projects/patch/ 

### Configuration

The folder where scripts are loaded can be overridden by setting the
`HOOKS_DIR` variable for a dokku app.

## Example

Add a script `hooks/nginx-pre-reload` in a Docker-based
dokku project:

```bash
#!/usr/bin/env bash

set -eoux pipefail;

vouch_host="vouch";
vouch_port="9090";
dokku_domain="mydomain.com";

APP=$APP /var/lib/dokku/plugins/available/vouch-auth/add-vouch-auth.pl "$vouch_host" "$vouch_port" "$dokku_domain";
```

When deploying you app to dokku, a whole bunch of new log messages should
now appear during the build-and-deploy process.
 you should see the following instructions

## Pre-requisites

- Dokku, obviously; used with Dokku version 0.21.4
- [Perl 5](https://www.perl.org)
- [GNU patch][patch]

## Credits

I hesitate to blame anyone but myself for the infelicities of this code;
but as far as inspiration goes, the source for [@fteychene][ftcheyene]'s
[dokku-build-hook](https://github.com/fteychene/dokku-build-hook)
plugin was helpful when the Dokku documentation was lacking.

[ftcheyene]: https://github.com/fteychene

