#!/usr/bin/env perl

use strict;
use warnings;
use File::Temp;

# args: vouch host, vouch port, dokku domain/host fqdn
# returns: string of the patch contents
sub get_patch_conts {
  my $vouch_host = shift;
  my $vouch_port = shift;
  my $dokku_domain = shift;

  my $patch = <<'END';
diff --git a/nginx.conf b/nginx.conf
--- a/nginx.conf
+++ b/nginx.conf
@@ -72,10 +72,41 @@
   ssl_protocols             TLSv1.2 TLSv1.3;
   ssl_prefer_server_ciphers off;

   keepalive_timeout   70;

+  # VOUCH_AUTH: send all requests to `/validate` endpoint for authorization
+  auth_request /validate;
+
+  location = /validate {
+    # forward the /validate request to Vouch Proxy
+    proxy_pass http://127.0.0.1:{{VOUCH_PORT}}/validate;
+    # be sure to pass the original host header
+    proxy_set_header Host $http_host;
+
+    # Vouch Proxy only acts on the request headers
+    proxy_pass_request_body off;
+    proxy_set_header Content-Length "";
+
+    # optionally add X-Vouch-User as returned by Vouch Proxy along with the
+    # request
+    auth_request_set $auth_resp_x_vouch_user $upstream_http_x_vouch_user;
+
+    # these return values are used by the @error401 call
+    auth_request_set $auth_resp_jwt $upstream_http_x_vouch_jwt;
+    auth_request_set $auth_resp_err $upstream_http_x_vouch_err;
+    auth_request_set $auth_resp_failcount $upstream_http_x_vouch_failcount;
+  }
+
+  # if validate returns `401 not authorized` then forward the request to the
+  # error401block
+  error_page 401 = @error401;
+
+  location @error401 {
+      # redirect to Vouch Proxy for login
+      return 302 https://{{VOUCH_HOST}}.{{DOKKU_DOMAIN}}/login?url=$scheme://$http_host$request_uri&vouch-failcount=$auth_resp_failcount&X-Vouch-Token=$auth_resp_jwt&error=$auth_resp_err;
+  }

   location    / {

     gzip on;
     gzip_min_length  1100;
END

  # adjust template

  $patch =~ s/\{\{VOUCH_HOST}}/$vouch_host/g;
  $patch =~ s/\{\{VOUCH_PORT}}/$vouch_port/g;
  $patch =~ s/\{\{DOKKU_DOMAIN}}/$dokku_domain/g;

  return $patch;
}

# args: contents of patch to apply (a string)
# returns: nothing
# effects: applies a patch file.
#
# Prints a warning and exits if GNU patch reports the patch can't
# be applied; exits using `die` if any other error occurs.
sub add_vouch_auth {
  my $patch = shift;

  my $tmp_fh = File::Temp->new( TEMPLATE => 'dokku-add-vouch-tempXXXXX'
                         );
  my $tmp_path = $tmp_fh->filename;

  print $tmp_fh $patch;

  my $res = `ls $tmp_path`;
  if ($? != 0) { die "can't ls tmp file $tmp_path";}
  my $res2 = `cat $tmp_path`;
  if ($? != 0) { die "can't cat tmp file $tmp_path";}
  if (length $res2 < 100) { die "implausible cat conts"; }

  `cp $tmp_path ./xx-${tmp_path}`; 
  if ($? != 0) { die "can't cp tmp file $tmp_path";}

  # test patch
  my $error = system "patch -p1 --dry-run --ignore-whitespace --force < $tmp_path";
  if ($error != 0) {
      warn "couldn't apply patch";
      exit;
  }
  # actually apply patch
  $error = system "patch -p1 --ignore-whitespace --force  --backup --version-control=numbered < $tmp_path";
  if ($error != 0) {
      die "couldn't apply patch";
  }
  print "applied patch\n";
}

if (scalar @ARGV != 3) {
  die "expected 3 args: vouch host, vouch port, main dokku domain";
}

my $vouch_host    = shift @ARGV;
my $vouch_port    = shift @ARGV;
my $dokku_domain  = shift @ARGV;

my $patch = get_patch_conts( $vouch_host, $vouch_port, $dokku_domain);

my $APP;
my $DOKKU_ROOT;

if (defined $ENV{'APP'}) {
  $APP = $ENV{'APP'};
} else {
  die "no APP env var";
}

if (defined $ENV{'DOKKU_ROOT'}) {
  $DOKKU_ROOT = $ENV{'DOKKU_ROOT'};
} else {
  die "no DOKKU_ROOT env var";
}

my $APP_ROOT="$DOKKU_ROOT/$APP";

chdir $APP_ROOT;

open my $ngx_fh, '<', 'nginx.conf' or die "Can't open file $!";
my $ngx_conts = do { local $/; <$ngx_fh> };

if ($ngx_conts =~ /VOUCH_AUTH/) {
  print "nginx.conf already has VOUCH_AUTH, not amending\n";
} else {
  add_vouch_auth($patch);
}

